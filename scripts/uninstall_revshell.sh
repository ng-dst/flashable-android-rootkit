#MAGISK
############################################
#
# Revshell uninstaller
#
# Two options available:
#  1. full /boot restore using backup
#     requires boot image (.gz) at
#     /tmp/backup_original_partitions/magisk_backup/boot.img.gz
#
#  2. restore init in-place using backed up init in /boot
#     warning: may not restore stock /boot signature!
#     use 1st option if you want to revert to stock /boot
#
############################################

##############
# Preparation
##############

# This path should work in any cases
TMPDIR=/dev/tmp

INSTALLER=$TMPDIR/install
CHROMEDIR=$INSTALLER/chromeos

# Default permissions
umask 022

OUTFD=$2
ZIP=$3

if [ ! -f $INSTALLER/util_functions.sh ]; then
  echo "! Unable to extract zip file!"
  exit 1
fi

# Load utility functions
. $INSTALLER/util_functions.sh

setup_flashable

ui_print " "
ui_print "     Android Rootkit uninstaller     "
ui_print " "

mount_partitions


# ================================================================================================ #

# SILENTPOLICY - check backups uploaded
ORIGINALBACKUPSDIR=/tmp/backup_original_partitions
if [ ! -d $ORIGINALBACKUPSDIR ]
then
  ui_print " "
  ui_print " ! Note: "
  ui_print " Original backups not provided. Uninstall script may not restore stock /boot signature."
  ui_print " Push your backups before running uninstaller if you want to revert to stock boot:"
  ui_print " "
  ui_print " $ adb push backup_original_partitions /tmp"
  ui_print " "
else
  ui_print "- Backups uploaded and ready"
fi
# ================================================================================================ #

api_level_arch_detect

ui_print "- Device platform: $ARCH"
MAGISKBIN=$INSTALLER/$ARCH32
mv $CHROMEDIR $MAGISKBIN
chmod -R 755 $MAGISKBIN

$BOOTMODE || recovery_actions

############
# Uninstall
############

get_flags
find_boot_image

[ -e $BOOTIMAGE ] || abort "! Unable to detect boot image"
ui_print "- Found target image: $BOOTIMAGE"
[ -z $DTBOIMAGE ] || ui_print "- Found dtbo image: $DTBOIMAGE"

cd $MAGISKBIN

CHROMEOS=false


ui_print "- Unpacking boot image"

# Dump image for MTD/NAND character device boot partitions
if [ -c $BOOTIMAGE ]; then
  nanddump -f boot.img $BOOTIMAGE
  BOOTNAND=$BOOTIMAGE
  BOOTIMAGE=boot.img
fi
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

./magiskboot cpio ramdisk.cpio test
STATUS=$?

# Restore the original boot partition path
[ "$BOOTNAND" ] && BOOTIMAGE=$BOOTNAND

BACKUPDIR=/tmp/backup_original_partitions/magisk_backup

if [ -d $BACKUPDIR ]; then
  ui_print "- Restoring stock boot image"
  flash_image $BACKUPDIR/boot.img.gz $BOOTIMAGE
  for name in dtb dtbo dtbs; do
    [ -f $BACKUPDIR/${name}.img.gz ] || continue
    IMAGE=`find_block $name$SLOT`
    [ -z $IMAGE ] && continue
    ui_print "- Restoring stock $name image"
    flash_image $BACKUPDIR/${name}.img.gz $IMAGE
  done
else
  [ $((STATUS & 2)) -ne 0 ] || abort "! Rootkit isn't installed. If it is, use backups to uninstall."
  ui_print "- Restoring init in-place"

  # Internal restore
  ./magiskboot cpio ramdisk.cpio restore
  if ! ./magiskboot cpio ramdisk.cpio "exists init"; then
    # A only system-as-root
    rm -f ramdisk.cpio
  fi
  ./magiskboot repack $BOOTIMAGE

  # Sign chromeos boot
  $CHROMEOS && sign_chromeos
  ui_print "- Flashing restored boot image"
  flash_image new-boot.img $BOOTIMAGE || abort "! Insufficient partition size"

  ui_print "- OK rootkit uninstalled"
fi

cd /

# Remove rootkit's persistence directory
rm -rf /data/adb/.fura

recovery_cleanup
ui_print "- Done"

ui_print " "

rm -rf $TMPDIR
exit 0
