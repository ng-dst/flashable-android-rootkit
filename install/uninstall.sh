#!/bin/bash

wfr() {
	adb wait-for-recovery
}

wfs() {
	adb wait-for-sideload
}

TWRP_PATH=./twrp

BACKUP_PATH=backup_original_partitions
BUILD_PATH=../out

ZIP_UNINSTALL=zip_reverse_shell_uninstall.zip

if [ ! -f "$TWRP_PATH" ]; then
  echo "TWRP not found at '$TWRP_PATH'. Exiting."
  exit 1
fi

if [ ! -d "$BACKUP_PATH" ]; then
	echo "The '$BACKUP_PATH' directory is missing."
  echo "Cannot uninstall without backups."
  exit 1
fi

adb reboot bootloader
fastboot boot $TWRP_PATH

#  Uninstall
wfr && adb push "$BACKUP_PATH" /tmp/backup_original_partitions
wfr && adb shell twrp sideload
wfs && adb sideload "$BUILD_PATH/$ZIP_UNINSTALL"
if [ $? -ne 0 ]; then
	echo "Uninstall failed. Something is wrong?"
	echo "Ignore if there are no problems"
	exit 1
fi

wfr && adb reboot
