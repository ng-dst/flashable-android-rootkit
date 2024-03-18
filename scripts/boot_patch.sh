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

#SHA1=`./magiskboot sha1 "$BOOTIMAGE" 2>/dev/null`
cat $BOOTIMAGE > stock_boot.img
cp -af ramdisk.cpio ramdisk.cpio.orig 2>/dev/null

##################
# Ramdisk Patches
##################

ui_print "- Patching ramdisk"

echo "KEEPVERITY=$KEEPVERITY" > config
echo "KEEPFORCEENCRYPT=$KEEPFORCEENCRYPT" >> config
echo "RECOVERYMODE=$RECOVERYMODE" >> config
#[ ! -z $SHA1 ] && echo "SHA1=$SHA1" >> config

./magiskboot cpio ramdisk.cpio \
"add 750 init magiskinit" \
"patch" \
"backup ramdisk.cpio.orig" \
"mkdir 000 .backup" \
"add 000 .backup/.rtk config"

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
