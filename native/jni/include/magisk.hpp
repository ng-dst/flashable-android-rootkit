#pragma once

#include <string>

#define SECURE_DIR      "/data/adb"
#define MODULEROOT      SECURE_DIR "/modules"

// tmpfs paths (base path changed to .rtk)
extern std::string  MAGISKTMP;
#define INTLROOT    ".rtk"
#define MIRRDIR     INTLROOT "/mirror"
#define RULESDIR    MIRRDIR "/sepolicy.rules"
#define BLOCKDIR    INTLROOT "/block"
#define MODULEMNT   INTLROOT "/modules"
#define BBPATH      INTLROOT "/busybox"
#define ROOTOVL     INTLROOT "/rootdir"
#define ROOTMNT     ROOTOVL "/.mount_list"

#define POST_FS_DATA_WAIT_TIME       40
#define POST_FS_DATA_SCRIPT_MAX_TIME 35
