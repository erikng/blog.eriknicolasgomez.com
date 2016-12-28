---
layout: post
title: "The Untouchables Pt 2: Offline TouchBar activation with a purged disk"
description: "I've got FDRData in my ESP."
tags: [Activation, macOS, watchOS, TouchBar, MacBook Pro, Sierra]
comments: true
---

### Preface
While I have tried to document and piece together as much as possible here, some of the statements could be inaccurate. Until Apple posts more information about this process, take everything you read below with a grain of salt. If you choose to use the methodologies in production, I offer no warranties to the integrity of your sytem.

If you just want the answer, go to [Baking The Cake](#baking-the-cake)

### ROOT_DARWIN_USER_TEMP_DIR
While the preflight container data located in _/Library/Updates/PreflightContainers_ (Example: /Library/Updates/PreflightContainers/865FA1BB-3EF6-4F77-A4B7-01529BCE33F0.preflightContainer) changed each reboot, there was one common folder across all of my test machines:

`/private/var/folders/zz/zyxvpxvq6csfxvn_n0000000000000/T`

After discussing this with some colleagues (thanks yet again [Michael](https://twitter.com/mikeymikey) and [Pepijn](https://twitter.com/bruienne)) we realized that EmbeddedOSInstallService utilizes the temporary directory for the root user.

```
root# getconf DARWIN_USER_TEMP_DIR
/private/var/folders/zz/zyxvpxvq6csfxvn_n0000000000000/T/
```

More on this soon.

### FDRData and ESP
In the EOSIS logging events, Apple often refers to two items: FDRData and ESP. From what I can tell, FDRData stands for _FirmwareDirectoryRestoreData_ and ESP stands for _EFI System Partition_.

You can find FDRData in inside of the ESP and the root temp directory:

- /Volumes/EFI/EFI/APPLE/EMBEDDEDOS/FDRData
- /private/var/folders/zz/zyxvpxvq6csfxvn_n0000000000000/T/FDRData

### PersonalizedBundle

When contacting the internet for activation, a folder is created at `ROOT_DARWIN_USER_TEMP_DIR/%RANDOM_GUID%-EmbeddedOSInstall-PersonalizedBundle`.

This bundle contains Apple's signed firmware files (img4 format), and a few plists.

A request is sent to URL (which I will not post) with a tss-request. Apple sends back a tss-response and then creates the BuildManifest.plist, EOS_RestoreOptions.plist and Restore.plist. These files have several certificates that have been signed by Apple.

``` ruby
/bin/ls -R /private/var/folders/zz/zyxvpxvq6csfxvn_n0000000000000

/private/var/folders/zz/zyxvpxvq6csfxvn_n0000000000000/T/%RANDOM_GUID%-EmbeddedOSInstall-PersonalizedBundle:
BuildManifest.plist
EOS_RestoreOptions.plist
Firmware
KernelCache_kernelcache.release.img4
OSRamdisk_058-40573-247.img4
Restore.plist
RestoreKernelCache_kernelcache.release.img4
RestoreRamDisk_058-27707-457.img4
amai

/private/var/folders/zz/zyxvpxvq6csfxvn_n0000000000000/T/%RANDOM_GUID%-EmbeddedOSInstall-PersonalizedBundle/Firmware:
all_flash
dfu

/private/var/folders/zz/zyxvpxvq6csfxvn_n0000000000000/T/%RANDOM_GUID%-EmbeddedOSInstall-PersonalizedBundle/Firmware/all_flash:
all_flash.x619ap.production

/private/var/folders/zz/zyxvpxvq6csfxvn_n0000000000000/T/%RANDOM_GUID%-EmbeddedOSInstall-PersonalizedBundle/Firmware/all_flash/all_flash.x619ap.production:
DeviceTree_DeviceTree.x619ap.img4
LLB_LLB.x619.RELEASE.img4
RestoreDeviceTree_DeviceTree.x619ap.img4
RestoreSEP_sep-firmware.x619.RELEASE.img4
SEP_sep-firmware.x619.RELEASE.img4
iBoot_iBoot.x619.RELEASE.img4
manifest

/private/var/folders/zz/zyxvpxvq6csfxvn_n0000000000000/T/%RANDOM_GUID%-EmbeddedOSInstall-PersonalizedBundle/Firmware/dfu:
iBEC_iBEC.x619.RELEASE.img4
iBSS_iBSS.x619.RELEASE.img4

/private/var/folders/zz/zyxvpxvq6csfxvn_n0000000000000/T/%RANDOM_GUID%-EmbeddedOSInstall-PersonalizedBundle/amai:
apimg4ticket.der
debug
receipt.plist

/private/var/folders/zz/zyxvpxvq6csfxvn_n0000000000000/T/%RANDOM_GUID%-EmbeddedOSInstall-PersonalizedBundle/amai/debug:
tss-request.plist
tss-response.plist
```

### combined.memboot
You can find the combined.memboot in inside of the ESP:

- /Volumes/EFI/EFI/APPLE/EMBEDDEDOS/combined.memboot.

While I have not been able to look into the subcomponents of this file, this is the boot file that is loaded into the TouchBar's memory.

My __theory__ is this file is combined both with the _PersonalizedBundle_ and the local firmware currently located in `/usr/standalone/firmware/iBridge1_1Customer.bundle`.

### The differences between online activation and offline activation/upgrades.

#### Online Activation

Online Activation is typically required after Internet Recovery or a full disk wipe and subsequent re-image. During online activation the following occurs through EmbeddedOSInstallService:

1. EOSIS detects that the TouchBar cannot boot and attempts to heal
2. After failing to detect the EMBEDDEDOS folder structure in the EFI partition __and__ the corresponding FDRData, EOSIS triggers an _online_ repair
3. EOSIS downloads a package from Apple with an identifier of _com.apple.mac.EmbeddedOSInstall_
- For an example of this package see this [url](http://swcdn.apple.com/content/downloads/55/51/031-91415/awf2bwxbgsvc6pc6wd7i49uvxwgqt2lz6r/EmbeddedOSFirmware.pkg)
4. The PersonalizedBundle, FDRData and combined.memboot are created in the ROOT_DARWIN_USER_TEMP folder.
5. The ESP is mounted (equivalent to `diskutil mount disk0s1`)
6. The EMBEDDEDOS folder is created if it does not exist and the FDRData and combined.memboot are copied over.
7. Any EmbeddedOSInstall-FDRMemoryStore temporary folders are purged.
8. The TouchBar attempts to boot and if everything goes well the machine presents the loginwindow.
9. TouchID is now available for configuration via SetupAssistant

#### Offline Activation

Offline Activation seems to occur each time the machine is booted. During offline activation the following occurs through EmbeddedOSInstallService:

1. EOSIS finds the combined.memboot and FDRData from the ESP and matches the FDRData from the ROOT_DARWIN_USER_TEMP folder.
2. EOSIS attempts to boot the TouchBar with the combined.memboot
3. After a successful load, the PersonalizedPreflight container is created in /Library/Updates/PreflightContainers
4. Loginwindow is presented
5. User authenticates, unlocks the login.keychain, and TouchID is then available for use.

#### Offline Upgrades

Offline Upgrades seems to occur each time the machine there is a new firmware detected in the `iBridge1_1Customer.bundle`. During offline activation the following occurs through EmbeddedOSInstallService:

1. EOSIS finds the combined.memboot and FDRData from the ESP and matches the FDRData from the ROOT_DARWIN_USER_TEMP folder and iBridge1_1Customer.bundle.
2. EOSIS detects a difference in version between the combined.memboot and the iBridge1_1Customer.bundle
3. The PersonalizedBundle, FDRData and combined.memboot are re-created in the ROOT_DARWIN_USER_TEMP folder.
4. The ESP is mounted (equivalent to `diskutil mount disk0s1`)
5. The old FDRData and combined.memboot are purged and replaced.
6. Any EmbeddedOSInstall-FDRMemoryStore temporary folders are purged.
7. The TouchBar attempts to boot and if everything goes well the machine presents the loginwindow.
8. User authenticates, unlocks the login.keychain, and TouchID is then available for use.

---

## Baking The Cake

My spidey sense tingled when I first noticed offline activations and offline upgrades. It was clear that Apple didn't want to force a "Critical Update required" screen every time there was a new point release and we could use this to our advantage.

With this I tried multiple re-images and finally found the correct procedure to wipe a full disk and still have offline activation during the first boot of the OS.

Here are the steps you must do:

- Mount the EFI partition
- Capture EFI folder from EFI Partition (ex: `cp -r /Volumes/EFI/EFI /path/to/EFIbackup`)
- Capture contents of FDRData from preflight folder (ex: `cp -r /Volumes/Macintosh\ HD/private/var/folders/zz/zyxvpxvq6csfxvn_n0000000000000/T /path/to/PersonalizedBundleBackup`)
- Destroy entire disk
- Apply image
- Copy EFI folder back to new ESP
- Copy PersonalizedBundle(s) and FDRData back to the ROOT_DARWIN_USER_TEMP_DIR
- Boot machine normally

If done correctly, you should be presented the normal SetupAssistant without the Critical Update required message.

#### Caveats
- In order to capture the contents of the FDRData and preflight folders from a FileVault encrypted volume, you will need to unlock this disk. This may be a tall order if you still require 100% automation.
- It is currently unknown what would happen if you capture a combined.memboot and FDRData on an older OS (Ex. 10.12.1) and then apply it to a newer OS image (10.12.2 once it is released).
- __Apple may not like us doing this and could break it at any time.__

### Final Thoughts
Quite a bit of time has been taken to piecemeal this together. While it has been a great academic study, I will emphasize once again that Apple needs to document this process for enterprise customers.

This _will_ impact both imaging workflows _and_ DEP workflows and __once__ again, people who _"remain in the past"_ can continue to fully automate this process if needed.

Modern workflows? Yeah about that...

## Table Of Contents
* Do not remove this line (it will not be displayed)
{:toc}
