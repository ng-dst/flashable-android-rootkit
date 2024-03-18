#!/bin/bash

wfr() {
	adb wait-for-recovery
}

wfs() {
	adb wait-for-sideload
}

BACKUP_PATH=backup_original_partitions
BUILD_PATH=../out

ZIP_INSTALL=zip_reverse_shell_v2.zip

pull_backups=1

if [ -d "$BACKUP_PATH" ]; then
	echo "The 'backup_original_partitions' directory is already present."
    read -p "Overwrite? (y/N) " answer
    if [ "$answer" != "y" ] && [ "$answer" != "Y" ] && [ "$answer" != "yes" ]; then
        echo "Will not pull backups"
        pull_backups=0
    fi
fi

adb reboot bootloader
fastboot boot twrp

#  Install
wfr && adb shell twrp sideload
wfs && adb sideload "$BUILD_PATH/$ZIP_INSTALL"

if [[ $pull_backups == 1 ]]; then
	adb pull "/tmp/backup_original_partitions" "$BACKUP_PATH" && echo "Backups pulled to '$BACKUP_PATH'" && adb reboot
else
	adb reboot
fi
