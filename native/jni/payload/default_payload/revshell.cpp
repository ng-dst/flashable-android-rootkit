//  Dummy program to spam logcat
//  Credits to LuigiVampa92  (see README)

#include "revshell.hpp"

bool check_fs_decrypted() {
    bool result = false;
    struct dirent *entry;
    DIR *dir = opendir(ENCRYPTED_FS_CHECK_DIR);
    if (dir == NULL) {
        return result;
    }
    while ((entry = readdir(dir)) != NULL) {
        if (strstr(entry->d_name, ENCRYPTED_FS_CHECK_PROOF)) {
            result = true;
        }
    }
    closedir(dir);
    return result;
}

int run_in_main_proc() {
    LOGD("Start successfull!\n");

    signal(SIGINT, SIG_IGN);
    signal(SIGHUP, SIG_IGN);
    signal(SIGQUIT, SIG_IGN);
    signal(SIGPIPE, SIG_IGN);
    signal(SIGCHLD, SIG_IGN);
    signal(SIGTTOU, SIG_IGN);
    signal(SIGTTIN, SIG_IGN);
    signal(SIGTERM, SIG_IGN);
    signal(SIGKILL, SIG_IGN);

    LOGD("Signals are set to ignore\n");

    int timer_counter = 0;
    int timer_step = 5;

    LOGD("Hey I'm a revshell process!\n");
    LOGD("My PID -- %d\n", getpid());
    LOGD("My parent PID -- %d\n", getppid());
    LOGD("My UID -- %d\n", getuid());
    LOGD("Awaiting encrypted FS decryption now...");

    while (true) {
        sleep(timer_step);
        timer_counter = (timer_counter + timer_step) % INT_MAX;
        if (check_fs_decrypted()) {
            LOGD("FS has been decrypted!");
            break;
        }
    }

    LOGD("Starting reverse shell now");
    while (true) {
        sleep(timer_step);
        timer_counter = (timer_counter + timer_step) % INT_MAX;
        LOGD("tick ! %d seconds since process started", timer_counter);
    }

    LOGD("Exit!\n");

    return 0;
}

int main(int argc, char *argv[]) {
    return run_in_main_proc();
}