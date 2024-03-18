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
ZIP_UNINSTALL=zip_reverse_shell_uninstall.zip

backups_present=1

if [ ! -d "$BACKUP_PATH" ]; then
	backups_present=0
	echo "The 'backup_original_partitions' directory is missing."
    echo "You should continue ONLY if your device has stock boot image!"
    read -p "Continue? (y/N) " answer
    if [ "$answer" != "y" ] && [ "$answer" != "Y" ] && [ "$answer" != "yes" ]; then
        echo "Aborting installation."
        exit 1
    fi
fi

adb reboot bootloader
fastboot boot twrp

#  Uninstall
if [[ $backups_present == 1 ]]; then
	wfr && adb push "$BACKUP_PATH" /tmp/backup_original_partitions
	sleep 1
	wfr && adb shell twrp sideload
	sleep 1
	wfs && adb sideload "$BUILD_PATH/$ZIP_UNINSTALL"
	if [ $? -ne 0 ]; then
		echo "Uninstall failed. Something is wrong?"
		echo "Restart the script if there are no problems"
		exit 1
	fi
fi

#  Install
wfr && adb shell twrp sideload
wfs && adb sideload $BUILD_PATH/$ZIP_INSTALL

wfr && adb reboot
