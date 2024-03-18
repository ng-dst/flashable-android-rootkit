#MAGISK
############################################
#
# Revshell uninstaller (restore to stock /boot)
#
# requires boot image (.gz) at
#     /tmp/backup_original_partitions/magisk_backup/boot.img.gz
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
  ui_print " "
  ui_print " ! WARNING !"
  ui_print " Original backups not provided. Uninstall is not possible."
  ui_print " Please push previously saved backups to device via adb first:"
  ui_print " "
  ui_print " $ adb push backup_original_partitions /tmp"
  ui_print " "
  ui_print " Once it is done you will be able to uninstall the tool"
  ui_print " (directory $ORIGINALBACKUPSDIR must exist) "
  ui_print " "
  abort "!!!"
  exit 1
fi
ui_print "- Backups uploaded and ready"

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
  abort "! Boot image backup unavailable"
fi

cd /

# Remove rootkit's persistence directory
rm -rf /data/adb/.cache

recovery_cleanup
ui_print "- Done"

ui_print " "

rm -rf $TMPDIR
exit 0
