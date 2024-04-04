#include <base.hpp>

#include "policy.hpp"

using namespace std;

void sepolicy::magisk_rules() {
    // Legacy log handling (<= v25.0)
    auto bak = log_cb.w;
    log_cb.w = nop_log;

    // Prevent anything to change sepolicy except ourselves
    deny(ALL, "kernel", "security", "load_policy");

    // what if...    seems ok!
    //   Note:  "domain" type grants access from some contexts by stock policy
    //           so we use "coredomain" instead. Seems working so far...
    type(SEPOL_PROC_DOMAIN, "coredomain");
    typeattribute(SEPOL_PROC_DOMAIN, "file_type");
    typeattribute(SEPOL_PROC_DOMAIN, "exec_type");

    typeattribute(SEPOL_PROC_DOMAIN, "appdomain");
    typeattribute(SEPOL_PROC_DOMAIN, "mlstrustedsubject");
    typeattribute(SEPOL_PROC_DOMAIN, "netdomain");
    typeattribute(SEPOL_PROC_DOMAIN, "bluetoothdomain");

    // Deny any unwanted access to our domain (except permissions below)
    // Basically hides all our processes, directories, and files
    deny(ALL, SEPOL_PROC_DOMAIN, ALL, ALL);
    denyxperm(ALL, SEPOL_PROC_DOMAIN, ALL, ALL);

    // Suppress audit logs for our domain
    dontaudit(ALL, SEPOL_PROC_DOMAIN, ALL, ALL);
    dontauditxperm(ALL, SEPOL_PROC_DOMAIN, ALL, ALL);
    dontaudit(SEPOL_PROC_DOMAIN, ALL, ALL, ALL);

    permissive(SEPOL_PROC_DOMAIN);  /* Just in case something is missing */

    // Make our root domain unconstrained
    allow(SEPOL_PROC_DOMAIN, ALL, ALL, ALL);
    // Allow us to do any ioctl
    if (impl->db->policyvers >= POLICYDB_VERSION_XPERMS_IOCTL) {
        allowxperm(SEPOL_PROC_DOMAIN, ALL, "blk_file", ALL);
        allowxperm(SEPOL_PROC_DOMAIN, ALL, "fifo_file", ALL);
        allowxperm(SEPOL_PROC_DOMAIN, ALL, "chr_file", ALL);
    }

    // Let everyone access tmpfs files (for SAR sbin overlay)
    allow(ALL, "tmpfs", "file", ALL);

    // Allow magiskinit daemon to handle mock selinuxfs
    allow("kernel", "tmpfs", "fifo_file", "write");
    allow("kernel", "tmpfs", "filesystem", "associate");

    // For relabelling files
    allow("rootfs", "labeledfs", "filesystem", "associate");

    // Let init transit to SEPOL_PROC_DOMAIN
    allow("kernel", "kernel", "process", "setcurrent");
    allow("kernel", SEPOL_PROC_DOMAIN, "process", "dyntransition");

    // Let init run stuffs
    allow("kernel", SEPOL_PROC_DOMAIN, "fd", "use");
    allow("init", SEPOL_PROC_DOMAIN, "process", ALL);
    allow("init", "tmpfs", "file", "getattr");
    allow("init", "tmpfs", "file", "execute");

    // suRights
    allow("servicemanager", SEPOL_PROC_DOMAIN, "binder", ALL);
    allow(ALL, SEPOL_PROC_DOMAIN, "process", "sigchld");

    // allowLog
    allow("logd", SEPOL_PROC_DOMAIN, "dir", "search");
    allow("logd", SEPOL_PROC_DOMAIN, "file", "read");
    allow("logd", SEPOL_PROC_DOMAIN, "file", "open");
    allow("logd", SEPOL_PROC_DOMAIN, "file", "getattr");

    // bootctl
    allow("hwservicemanager", SEPOL_PROC_DOMAIN, "dir", "search");
    allow("hwservicemanager", SEPOL_PROC_DOMAIN, "file", "read");
    allow("hwservicemanager", SEPOL_PROC_DOMAIN, "file", "open");
    allow("hwservicemanager", SEPOL_PROC_DOMAIN, "process", "getattr");

    // For mounting loop devices, mirrors, tmpfs
    allow("kernel", ALL, "file", "read");
    allow("kernel", ALL, "file", "write");

    // For changing file context
    allow("rootfs", "tmpfs", "filesystem", "associate");

    // Shut llkd up
    dontaudit("llkd", SEPOL_PROC_DOMAIN, "process", "ptrace");

    // Allow update_engine/addon.d-v2 to run permissive on all ROMs
    permissive("update_engine");

#ifdef MAGISK_DEBUG
    // Remove all dontaudit in debug mode
    impl->strip_dontaudit();
#endif

    log_cb.w = bak;
}
