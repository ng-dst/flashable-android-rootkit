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
ZIP_UNINSTALL=zip_reverse_shell_uninstall.zip

backups_present=1

if [ ! -f "$TWRP_PATH" ]; then
  echo "[-] TWRP not found at '$TWRP_PATH'. Exiting."
  exit 1
fi

if [ ! -d "$BACKUP_PATH" ]; then
	backups_present=0
	echo "[?] The 'backup_original_partitions' directory is missing. Will perform 'dirty' installation."
  echo "[?] You should continue ONLY if your device has stock boot image!"
  read -p "[?] Continue? (y/N) " answer
  if [ "$answer" != "y" ] && [ "$answer" != "Y" ] && [ "$answer" != "yes" ]; then
    echo "Aborting installation."
    exit 1
  fi
fi

echo "[*] Rebooting into bootloader"
adb reboot bootloader || echo "[!] Please enter Fastboot manually. Usually by holding 'Volume-' and 'Power' until reboot"
echo "[*] Booting '$TWRP_PATH'"
fastboot boot $TWRP_PATH

#  Uninstall
if [[ $backups_present == 1 ]]; then
  echo "[*] Pushing backups from '$BACKUP_PATH'"
	wfr && adb push "$BACKUP_PATH" /tmp/backup_original_partitions
	wfr && sleep 10 && adb shell twrp sideload || echo "[!] Please enter ADB sideload manually. Go to Advanced -> ADB sideload"
  wfs && echo "[*] Running uninstaller"
	adb sideload "$BUILD_PATH/$ZIP_UNINSTALL"
	if [ $? -ne 0 ]; then
		echo "[-] Uninstall failed. Something is wrong?"
		echo "[-] Restart the script if there are no problems"
		exit 1
	fi
  echo "[+] Uninstall complete"
fi

#  Install
wfr && adb shell twrp sideload || echo "[!] Please enter ADB sideload manually. Go to Advanced -> ADB sideload"
wfs && echo "[*] Running installer"
adb sideload $BUILD_PATH/$ZIP_INSTALL && \
echo "[+] Reinstall complete. Rebooting" && \
wfr && adb reboot
