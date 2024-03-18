#include <magisk.hpp>
#include <selinux.hpp>

#define quote(s) #s
#define str(s) quote(s)


constexpr char PAYLOAD_RC[] =
"\n"

// Define oneshot service for payload executor

"service %2$s %1$s/executor\n"
"    disabled\n"
"    user root\n"
"    group root\n"
"    seclabel u:r:" SEPOL_PROC_DOMAIN ":s0\n"
"    oneshot\n"
"\n"

"on property:sys.boot_completed=1\n"
"    start %2$s\n"
"\n"
;
