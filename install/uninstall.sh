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
  echo "[-] TWRP not found at '$TWRP_PATH'. Exiting."
  exit 1
fi

BACKUPS_PRESENT=1
if [ ! -d "$BACKUP_PATH" ]; then
  BACKUPS_PRESENT=0
	echo "[?] The '$BACKUP_PATH' directory is missing."
  echo "[?] If you uninstall without backups, your /boot image may not match the stock one."
  read -p "[?] Continue? (Y)es / (n)o " answer
    if [ "$answer" == "n" ] || [ "$answer" == "N" ] || [ "$answer" == "no" ]; then
        echo "[-] Cancelled by user"
        exit 1
    fi
else
  echo "[+] Uninstalling using backups"
fi

echo "[*] Rebooting into bootloader"
adb reboot bootloader || echo "[!] Please enter Fastboot manually. Usually by holding 'Volume-' and 'Power' until reboot"
fastboot boot $TWRP_PATH

#  Uninstall
if [ $BACKUPS_PRESENT -ne 0 ]; then
  echo "[*] Pushing backups from '$BACKUP_PATH'"
  wfr && adb push "$BACKUP_PATH" /tmp/backup_original_partitions
fi

echo "[*] Loading TWRP. Please wait..."
wfr && sleep 10 && adb shell twrp sideload || echo "[!] Please start ADB sideload manually. Go to Advanced -> ADB sideload"
wfs && echo "[*] Running uninstaller"
adb sideload "$BUILD_PATH/$ZIP_UNINSTALL"
if [ $? -ne 0 ]; then
	echo "[-] Uninstall failed. Something is wrong?"
	echo "[-] Ignore if TWRP shows no problems"
	exit 1
fi

echo "[+] Uninstall complete. Rebooting"
wfr && adb reboot
