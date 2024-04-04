#include <sys/stat.h>
#include <sys/types.h>
#include <sys/sysmacros.h>
#include <fcntl.h>
#include <libgen.h>
#include <vector>

#include <magisk.hpp>
#include <utils.hpp>

#include "init.hpp"

using namespace std;

// Debug toggle
#define ENABLE_TEST 0


class RecoveryInit : public BaseInit {
public:
    RecoveryInit(char *argv[], cmdline *cmd) : BaseInit(argv, cmd) {}
    void start() override {
        LOGD("Ramdisk is recovery, abort\n");
        rename("/.rtk_backup/init", "/init");
        rm_rf("/.rtk_backup");
        exec_init();
    }
};

int main(int argc, char *argv[]) {
    umask(0);

    if (getpid() != 1)
        return 1;

    BaseInit *init;
    cmdline cmd{};

    if (argc > 1 && argv[1] + 1 == "elinux_setup"sv) {
        setup_klog();
        init = new SecondStageInit(argv);
    } else {
        // This will also mount /sys and /proc
        load_kernel_info(&cmd);

        if (cmd.skip_initramfs) {
            init = new SARInit(argv, &cmd);
        } else {
            if (cmd.force_normal_boot)
                init = new FirstStageInit(argv, &cmd);
            else if (access("/sbin/recovery", F_OK) == 0 || access("/system/bin/recovery", F_OK) == 0)
                init = new RecoveryInit(argv, &cmd);
            else if (check_two_stage())
                init = new FirstStageInit(argv, &cmd);
            else
                init = new RootFSInit(argv, &cmd);
        }
    }

    init->start();
    exit(1);
}
