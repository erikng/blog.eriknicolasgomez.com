---
layout: post
title: "The Untouchables - Apple's new OS 'activation' for Touch Bar MacBook Pros"
description: "A critical software update is required for your Mac."
tags: [Activation, macOS, watchOS, Touch Bar, MacBook Pro, Sierra]
comments: true
---
![Critical Update Hero](/images/critical_update.jpg "Critical Update Hero")

---

Last week [Joe Chilcote](https://twitter.com/chilcote) discovered an interesting message when imaging a Late 2016 MacBook Pro TouchBar (from here on out referred to as TBP):

`A critical software update is required for your Mac. To install this update you need to connect to a network. Select a Wi-Fi network below, or click Other Network Options to connect to the internet using other network devices.`

Given that I did not see this issue when testing DEP, I set forth to to attempt to duplicate the issue and find out what triggered this event.

(If you don't want to read this whole post or want to dupe the radars I submitted, scroll down to `As a macadmin, does this impact me?` for a TL;DR version.)

## Critical Software Update?

I think it's safe to say the macadmin community has been hearing rumblings about the future of macOS administration. Whether it was Michael Lynn's excellent blog post, [m(DM)acOS](http://michaellynn.github.io/2016/10/04/mDMacOS/), APFS or even Sal Saghoian's position being [axed](http://www.macrumors.com/2016/11/16/mac-automation-sal-soghoian-position-eliminated/), many macadmins (myself included) are worried about the future of macOS administration being a MDM only world.

What if the new TBP Macs were the first piece to this future?

I was initially worried about this discovery due to it breaking a _very_ typical thin imaging workflow:

1. asr an AutoDMG thin image
2. Install/Touch /private/var/db/.AppleSetupDone
3. Run bootstrapping software

Upon reboot, SetupAssistant was _not_ skipped and you were instead greeted with this lovely screen:

![Critical Update 1](https://github.com/erikng/blogposts/blob/master/SierraTBP/Critical%20Software%20Update%201.png?raw=true "Critical Update 1")

Attempting to skip this page would lead to an additional failure:

`A critical software update is required for your Mac, but an error was encountered while installing this update.`

Even more worrying was the final note:
`Your Mac can't be used until this update is installed. Shutdown / Try Again`
![Critical Update 2](https://github.com/erikng/blogposts/blob/master/SierraTBP/Critical%20Software%20Update%202.png?raw=true "Critical Update 2")

If you did connect your TBP to an online source, the critical update was downloaded, installed and your system was rebooted.
![Critical Update 3](https://github.com/erikng/blogposts/blob/master/SierraTBP/Critical%20Software%20Update%203.png?raw=true "Critical Update 3")

This entire process takes about two minutes to finish and then you can login into the Mac. Obviously a lot of engineering effort went into this - this is not a fluke.

What triggers this? Is Mac imaging _finally_ dead?

## Trying to recreate the issue

Good news everyone: Mac imaging isn't dead ... yet. While trying to recreate this issue, I started off with most simple workflow and methodically tried adding features.

### Uneventful Workflow tests
* Workflow 1
  * Deploy image to current volume - no wipe
* Workflow 2
  * Same as workflow 1
  * Add fingerprint to Touch ID
* Workflow 3
  * Same as workflow 2
  * Convert booted volume to Core Storage
* Workflow 4
  * Same as workflow 2
  * Enable FileVault 2
* Workflow 5
  * In Imagr NetInstall environment
  * Open up Disk Utility
  * Delete FileVault 2 volume
  * Re-run Workflow 4

In _none_ of these tests did I receive the critical software update. For informational purposes, workflow 5 was tested due to Imagr's inability to wipe FileVault encrypted volumes and was the closest thing to Joe's testing. After some discussions with Joe, we had a theory as to the true culpit of the issue.

### Workflow Goldmine
* Workflow 6
  * In Image NetInstall environment
    * Open up Disk Utility
      * Delete entire disk
  * Deploy image to newly created volume

It was with this workflow that I was finally able to recreate the issue. SetupAssistant immediately prompted the critical software update.

So what is being deleted when wiping the entire disk?

## Apple's EFI container for TouchBar
For some time, Apple has been installing EFI/firmware updates through standalone packages. Allister Banks first wrote about this during the [Thunderstrike](https://www.afp548.com/2015/03/05/thunderstrike-need-to-know/) vulnerability and I have been complaining about this for [some time](http://openradar.appspot.com/20025715).

Unfortunately, it looks like this how now been taken to a new level:

As a guess, I decided to look at the EFI volume

```bash
diskutil list
/dev/disk0 (internal):
#: TYPE NAME SIZE IDENTIFIER
0: GUID_partition_scheme 500.3 GB disk0
1: EFI EFI 314.6 MB disk0s1
2: Apple_HFS Macintosh HD 499.3 GB disk0s2
3: Apple_Boot Recovery HD 650.0 MB disk0s3
```

```css
diskutil mount disk0s1

ls /Volumes/EFI/EFI/APPLE/EMBEDDEDOS/
FDRData
combined.memboot
version.plist
```

Embedded OS you say. And something called `FDRData`

After searching for Embedded OS logs (thanks to Joe Chilcote), we found some interesting tidbits:

```bash
log show --debug --predicate 'process =="EmbeddedOSInstallService"'
```

```bash
EmbeddedOSInstallService: Couldnt find memboot image in ESP:
file:///Volumes/EFI/EFI/APPLE/EMBEDDEDOS/combined.memboot
```

So clearly, Apple is looking for this "Embedded OS" and if it can't find it, it attempts to rebuild the boot process.

## EmbeddedOSInstallService
As a test, I decided to delete the contents of /Volumes/EFI/EFI, reboot and look at the logs.
It appears that the following happens:

* During macOS system start, the TouchBar attempts to boot running it's own derivative of iOS.
* If it cannot find the embedded OS in the EFI volume, it triggers a repair.
* Taking iOS files from `/usr/standalone/firmware/iBridge1_1Customer.bundle/Contents/Resources` and `/Library/Updates/PreflightContainers`:
* If a valid preflight exists, no internet connection is required.
* macOS will show an extended/long boot process to the user, typically taking 2-3 minutes before the desktop is available.
* If a valid preflight does not exist, an internet connection is required
* SetupAssistant is triggered, informing the user of a Critical Update needed
* Once the TouchBar has either repaired itself or booted properly, biometrics/Touch ID is now available to the user.

Valid Preflight:

```ruby
EmbeddedOSInstallService: network reachability check
EmbeddedOSInstallService: ---- Starting network reachability check ----
EmbeddedOSInstallService: We have a valid preflighted container, no network is required
EmbeddedOSInstallService: (EmbeddedOSInstall) prepare device
```

Invalid Preflight:

```ruby
EmbeddedOSInstallService: No matching preflight container found
EmbeddedOSInstallService: network reachability check
EmbeddedOSInstallService: ---- Starting network reachability check ----
EmbeddedOSInstallService: Checking for reachability to gs.apple.com
EmbeddedOSInstallService: personalization
EmbeddedOSInstallService: ---- Starting personalization ----
```

No Internet

```ruby
EmbeddedOSInstallService: Can't continue the restore because you are not connected to the Internet.
```

Here is an abridged version of the logging events:

```ruby
EmbeddedOSInstallService: (EmbeddedOSInstall) FDR preflight
EmbeddedOSInstallService: ---- Starting FDR preflight ----
EmbeddedOSInstallService: Waiting for device to be connected
EmbeddedOSInstallService: Device connected: EOSDevice , boardID: 0x12, chipID: 0x8002, secure: YES, prod fused: YES>
EmbeddedOSInstallService: Starting FDR preflight
EmbeddedOSInstallService: Wrote preflighted FDR to memory store URL: /var/folders/zz/zyxvpxvq6csfxvn_n0000000000000/T/6140FB57-C5C9-4E4D-8534-1BA6F879A77A-EmbeddedOSInstall-FDRMemoryStore
EmbeddedOSInstallService: (EmbeddedOSInstall) preflight container stash
EmbeddedOSInstallService: ---- Starting preflight container stash ----
EmbeddedOSInstallService: Saved preflight container to disk: EOSPreflightContainer <file:///Library/Updates/PreflightContainers/FE0EC8F3-E032-49C1-B6E2-EA42171165AB.preflightContainer> (preflighted on 2016-11-24 07:00:02 +0000)
EmbeddedOSInstallService: Preflight time: 3.0 seconds
EmbeddedOSInstallService: Preflight was successful!
EmbeddedOSInstallService: Diagnostic summary: Preflight (14Y363 -> 14Y363 (Customer Boot), preflighted = 0, prod fused = 1, user auth = 0, retries = 0, after boot failure = 0, failing phase = 0, uuid = A21D9039-E0B8-42DA-A3D6-A037EE04484B): success
EmbeddedOSInstallService: ---- End Embedded OS Preflight ----
EmbeddedOSInstallService: [com.apple.mac.install.EmbeddedOSInstall] Adding client: loginwindow (pid = 91, uid = 0, path = /System/Library/CoreServices/loginwindow.app/Contents/MacOS/loginwindow)
EmbeddedOSInstallService: Checking if we should heal the device
EmbeddedOSInstallService: No data found in ios-boot-in-progress NVRAM key
EmbeddedOSInstallService: Device isn't booted yet and boot isn't in progress (EFI failed to bootstrap?)
EmbeddedOSInstallService: ---- Begin Embedded OS Boot ----
EmbeddedOSInstallService: (EmbeddedOSInstall) force reset
EmbeddedOSInstallService: ---- Starting force reset ----
EmbeddedOSInstallService: Resetting device
EmbeddedOSInstallService: (EmbeddedOSSupportHost) connection with driver establish (connect: 4907, service: 4807)
EmbeddedOSInstallService: Waiting for device to be connected
EmbeddedOSInstallService: Entering recovery mode, starting command prompt
EmbeddedOSInstallService: recovery mode device matches (using device type)
EmbeddedOSInstallService: ---- Starting memboot from EFI system partition ----
EmbeddedOSInstallService: Waiting for device to be connected
EmbeddedOSInstallService: recovery mode device matches (using locationID)
EmbeddedOSInstallService: (EmbeddedOSSupportHost) registered for 'com.apple.EmbeddedOS.DeviceConnected' darwin notification
EmbeddedOSInstallService: (EmbeddedOSSupportHost) registered for 'com.apple.EmbeddedOS.DeviceUnresponsive' darwin notification
EmbeddedOSInstallService: Waiting for Storage Kit to populate disks
EmbeddedOSInstallService: Done waiting for Storage Kit to populate disks
EmbeddedOSInstallService: Mounting ESP
EmbeddedOSInstallService: Couldn't find memboot image in ESP: file:///Volumes/EFI/EFI/APPLE/EMBEDDEDOS/combined.memboot
EmbeddedOSInstallService: Unmounting ESP
EmbeddedOSInstallService: Boot failed with error: Code=1201 "No memboot image was found in the EFI system partition."
EmbeddedOSInstallService: ---- End Embedded OS Boot ----
EmbeddedOSInstallService: Resetting the device into recovery mode since an error occurred during boot
EmbeddedOSInstallService: Waiting for recovery mode device
EmbeddedOSInstallService: Done waiting for recovery mode device
EmbeddedOSInstallService: Waiting for device boot
EmbeddedOSInstallService: Checking for healing overrides
EmbeddedOSInstallService: SMC is in app mode
EmbeddedOSInstallService: Should heal: YES, Found recovery mode device (after reboot attempt) (took 4.915 seconds)
EmbeddedOSInstallService: Enqueuing restore
EmbeddedOSInstallService: Starting restore
EmbeddedOSInstallService: Disabling retrying with AC for loginwindow
EmbeddedOSInstallService: Setting bootFailedAfterShouldHeal
EmbeddedOSInstallService: (EmbeddedOSInstall) Embedded OS Restore
EmbeddedOSInstallService: Getting information about current device for diagnostics
EmbeddedOSInstallService: Choosing between bundle specifiers: ("EOSRestoreBundle (14Y363)")
EmbeddedOSInstallService: Chose EOSRestoreBundle (14Y363)
EmbeddedOSInstallService: Using restore bundle: EOSRestoreBundle (14Y363)
EmbeddedOSInstallService: Attempting to locate preflight container for restore bundle
EmbeddedOSInstallService: Preflight container matches bundle specifier: EOSPreflightContainer <file:///Library/Updates/PreflightContainers/FE0EC8F3-E032-49C1-B6E2-EA42171165AB.preflightContainer/> (preflighted on 2016-11-24 07:00:02 +0000)
EmbeddedOSInstallService: Found preflight container: EOSPreflightContainer <file:///Library/Updates/PreflightContainers/FE0EC8F3-E032-49C1-B6E2-EA42171165AB.preflightContainer/> (preflighted on 2016-11-24 07:00:02 +0000)
EmbeddedOSInstallService: Set restore bundle: EOSRestoreBundle (14Y363) (PKBundleComponentVersion )
EmbeddedOSInstallService: Set FDR memory store: /Library/Updates/PreflightContainers/FE0EC8F3-E032-49C1-B6E2-EA42171165AB.preflightContainer/FDRData.plist
EmbeddedOSInstallService: Loading restoreOptions from plist: /Library/Updates/PreflightContainers/FE0EC8F3-E032-49C1-B6E2-EA42171165AB.preflightContainer/personalized/EOS_RestoreOptions.plist
EmbeddedOSInstallService: Updating restore options with preflight container paths
EmbeddedOSInstallService: (EmbeddedOSInstall) network reachability check
EmbeddedOSInstallService: ---- Starting network reachability check ----
EmbeddedOSInstallService: We have a valid preflighted container, no network is required
EmbeddedOSInstallService: (EmbeddedOSInstall) prepare device
EmbeddedOSInstallService: ---- Starting prepare device ----
EmbeddedOSInstallService: Waiting for Storage Kit to populate disks
EmbeddedOSInstallService: Done waiting for Storage Kit to populate disks
EmbeddedOSInstallService: Restore bundle was preflighted, forcing reset into recovery for restore
EmbeddedOSInstallService: Entering recovery mode, starting command prompt
EmbeddedOSInstallService: Device is now in recovery mode
EmbeddedOSInstallService: (EmbeddedOSInstall) personalization
EmbeddedOSInstallService: ---- Starting personalization ----
EmbeddedOSInstallService: We already have a valid preflighted container, skipping
EmbeddedOSInstallService: (EmbeddedOSInstall) bootstrap recovery mode
EmbeddedOSInstallService: ---- Starting bootstrap recovery mode ----
EmbeddedOSInstallService: Starting recovery mode restore
EmbeddedOSInstallService: Starting recovery restore
EmbeddedOSInstallService: Recovery mode restore succeeded
EmbeddedOSInstallService: Waiting for device to be disconnected
EmbeddedOSInstallService: ---- Starting restore mode restore (using restored) ----
EmbeddedOSInstallService: Waiting for device to be connected
EmbeddedOSInstallService: Starting restore mode restore
EmbeddedOSInstallService: Restore mode restore success!
EmbeddedOSInstallService: Sleeping 10 seconds to wait for nvram flush
EmbeddedOSInstallService: (EmbeddedOSInstall) force reset
EmbeddedOSInstallService: ---- Starting force reset ----
EmbeddedOSInstallService: Resetting device
EmbeddedOSInstallService: Waiting for device to be connected
EmbeddedOSInstallService: (EmbeddedOSInstall) recovery mode restore (OS ramdisk)
EmbeddedOSInstallService: ---- Starting recovery mode restore (OS ramdisk) ----
EmbeddedOSInstallService: Waiting for device to be connected
EmbeddedOSInstallService: Using OSRamdisk tag for second boot
EmbeddedOSInstallService: Starting recovery restore
EmbeddedOSInstallService: Recovery mode restore succeeded
EmbeddedOSInstallService: Waiting for device to be disconnected
EmbeddedOSInstallService: (EmbeddedOSInstall) wait for boot
EmbeddedOSInstallService: ---- Starting wait for boot ----
EmbeddedOSInstallService: Waiting for device to be connected
EmbeddedOSInstallService: Device boot complete!
EmbeddedOSInstallService: (EmbeddedOSInstall) EFI system partition installation
EmbeddedOSInstallService: ---- Starting EFI system partition installation ----
EmbeddedOSInstallService: Memboot image checksum (/var/folders/zz/zyxvpxvq6csfxvn_n0000000000000/T/3E465740-A3BD-4EE6-98D6-FE4DB003C10B-EmbeddedOSInstallESPSandbox/combined.memboot): 1904138235
EmbeddedOSInstallService: Mounting EFI system partition
EmbeddedOSInstallService: Error getting size of directory: /Volumes/EFI/EFI/APPLE/EMBEDDEDOS, returning 0: Error Domain=NSPOSIXErrorDomain Code=2 "No such file or directory" UserInfo={NSFilePath=/Volumes/EFI/EFI/APPLE/EMBEDDEDOS}
EmbeddedOSInstallService: Creating intermediate directory: /Volumes/EFI/EFI/APPLE
EmbeddedOSInstallService: Shoving /var/folders/zz/zyxvpxvq6csfxvn_n0000000000000/T/3E465740-A3BD-4EE6-98D6-FE4DB003C10B-EmbeddedOSInstallESPSandbox to /Volumes/EFI/EFI/APPLE/EMBEDDEDOS
EmbeddedOSInstallService: Memboot image checksum (/Volumes/EFI/EFI/APPLE/EMBEDDEDOS/combined.memboot): 1904138235
EmbeddedOSInstallService: Cleaning up sandbox: /var/folders/zz/zyxvpxvq6csfxvn_n0000000000000/T/3E465740-A3BD-4EE6-98D6-FE4DB003C10B-EmbeddedOSInstallESPSandbox
EmbeddedOSInstallService: Unmounting EFI system partition
EmbeddedOSInstallService: (EmbeddedOSInstall) purge preflight containers
EmbeddedOSInstallService: ---- Starting purge preflight containers ----
EmbeddedOSInstallService: Purging all preflight containers
EmbeddedOSInstallService: (EmbeddedOSInstall) [com.apple.mac.install.EmbeddedOSSerial]
EmbeddedOSInstallService: Restore time: 104.8 seconds
EmbeddedOSInstallService: Restore was successful!
EmbeddedOSInstallService: Diagnostic summary: Restore ((null) -> 14Y363 (Customer Boot), preflighted = 1, prod fused = 1, user auth = 0, retries = 0, after boot failure = 1, failing phase = 0, uuid = 2359AA1C-98E9-4B21-96A5-D710317AD57E): success
EmbeddedOSInstallService: ---- End Embedded OS Restore ----
EmbeddedOSInstallService: Adding client: biometrickitd (pid = 232, uid = 0, path = /usr/libexec/biometrickitd)
EmbeddedOSInstallService: Enqueing get local FDR data
EmbeddedOSInstallService: Starting get local FDR data
EmbeddedOSInstallService: Waiting for Storage Kit to populate disks
EmbeddedOSInstallService: Done waiting for Storage Kit to populate disks
EmbeddedOSInstallService: (CoreFoundation) Loading Preferences From System CFPrefsD For Search List
```

### Local Preflight Container

The local preflight container has some interesting information, although I won't dive into this too much on this post.

```css
ls /Library/Updates/PreflightContainers/guid.preflightContainer
FDRData.plist
metadata.plist
personalized

ls /Library/Updates/PreflightContainers/guid.preflightContainer/personalized/
BuildManifest.plist
EOS_RestoreOptions.plist
Firmware
KernelCache_kernelcache.release.img4
OSRamdisk_058-40573-247.img4
Restore.plist
RestoreKernelCache_kernelcache.release.img4
RestoreRamDisk_058-27707-457.img4
amai
version.plist

ls /Library/Updates/PreflightContainers/guid.preflightContainer/personalized/amai
apimg4ticket.der
debug
receipt.plist

ls /Library/Updates/PreflightContainers/guid.preflightContainer/personalized/amai/debug
tss-request.plist
tss-response.plist

ls /Library/Updates/PreflightContainers/guid.preflightContainer/personalized/Firmware
all_flash
dfu

ls /Library/Updates/PreflightContainers/guid.preflightContainer/personalized/Firmware/all_flash
all_flash.x619ap.production

ls /Library/Updates/PreflightContainers/guid.preflightContainer/personalized/Firmware/all_flash/all_flash.x619ap.production/
DeviceTree_DeviceTree.x619ap.img4
LLB_LLB.x619.RELEASE.img4
RestoreDeviceTree_DeviceTree.x619ap.img4
RestoreSEP_sep-firmware.x619.RELEASE.img4
SEP_sep-firmware.x619.RELEASE.img4
iBoot_iBoot.x619.RELEASE.img4
manifest

ls /Library/Updates/PreflightContainers/guid.preflightContainer/personalized/Firmware/dfu
iBEC_iBEC.x619.RELEASE.img4
iBSS_iBSS.x619.RELEASE.img4
```

A few interesting pieces:

* There appears to be a tss-request, tss-response and receipt, which seem to be signing data from Apple. One could assume this is for production activation of the OS.
* There are img4 files, all related to booting, restoring and DFU modes. These are more than likely signed files extracted from `/usr/standalone/firmware/iBridge1_1Customer.bundle`
* From the Receipt.plist, the TouchBar appears to be denoted as Watch2,5 running watchOS 3.0-14Y363.
* Many of these plist's contain keys, more than likely pointing to certificate based authentication/identities.
* There appears to be logic to detect whether the TBP has a fuse set. We might also be able to send specific variants of the OS. `No build variant specified and device is prod-fused, choosing customer variant.`

## Fun bugs
Given that iOS has had difficulty in the past with time, I hopped in my DeLorean and went back to 01-01-1970. Sure enough, the TouchBar failed to load, Touch ID was broken and the machine took a significant amount of time to boot.

While there were no logging events with EmbeddedOSInstall, the user experience was terrible. This is what the user sees for 2+ minutes.

![1970 TouchBar](https://github.com/erikng/blogposts/blob/master/SierraTBP/01-01-1970_TBP.png?raw=true "1970 TouchBar")

One can imagine that the OS is no longer validated, but why doesn't Apple attempt to detect a network, and then run `ntpdate` if the time if incorrect? While I have not submitted a radar for this, I plan very soon. Why Apple continues to not test time sync situations is beyond me.

## The wonderful future of hybrid hardware
It's quite clear - Welcome to the future of Apple's hybrid ARM/x86 platform. It's also quite clear that destroying entire disks is going to lead to some pain points for people still imaging. I have some concerns though. For several years, Apple has moved firmware/EFI updates into the delta/combo updaters and imaging has not been able to solve this issue.

- What happens when we build a 10.12.2 image and the EFI is out of date?
- Does EmbeddedOSInstallService also check signing windows?
- If it does, what happens when we deploy an image that doesn't contain the new firmware?
- Will there come a time that much like iOS, a MacBook Pro cannot be restored to an older OS?
- Will Apple consider wiping the primary OS volume only a security vulnerability, and cause this message to occur during any re-image of the volume?

I think we will have our answers soon, but it will be up to the community to figure this out.

---

## As a macadmin, does this impact me?
- Are deploying a thin, modular or thick image?
- Are you doing some kind of first boot scripting / boot process, ie LoginLog or DeployStudio finalize scripts?
- Are you bootstrapping munki?

If so, the key to not encountering this issue is by targeting _only_ the current Macintosh HD volume of the machine.

### Imagr users
Imagr targets the first available volume by default. For FileVault enabled disks, you typically deleted the entire drive or just the encrypted volume via Disk Utility.

If you are deleting the entire drive, stop! Delete the current volume and then run your imagr workflow. This will allow your automation workflows/bootstraps to continue to work.

### DeployStudio users
DeployStudio should be okay, but I recommend changing your restore workflow to:

Target Volume: Enter Value - Macintosh HD

While this option may not work for everyone (and may fail if people rename the default Macintosh HD naming convention), it will ensure that the volume itself is targeted. `First Disk available` is more than likely an option you want to stay away from, but I have not tested this theory. Please report your findings and if you run into any issues, post on the DeployStudio forums. Or better yet, move to Imagr! :)

### Internet Recovery users
Unfortunately, it seems if you are using Internet Recovery and wipe the entire disk, the critical update component will still be needed to complete, even though Internet Recovery has an internet component.

This is problematic if you wipe your devices prior to re-allocation and using DEP. This may also need a radar.

## Radars submitted to Apple
* [SetupAssistant does not detect non-wireless network to repair EmbeddedOS on Touch Bar MacBook Pros](https://openradar.appspot.com/radar?id=6115045738020864)
* [Internet Recovery does not activate Embedded OS on Touch Bar MacBook Pros](https://openradar.appspot.com/radar?id=6167317905932288)
* [Embedded OS/TouchBar MacBook Pro causes significant boot delays and malfunctions when the time isn't functioning.](https://openradar.appspot.com/radar?id=5520832180781056)

## Apple are you listening?

Apple if you are reading this, can you please outline this process for us? A simple knowledge base will not be enough. We need a *up-to-date* portal with information regarding the future of mac management. Documentation should not be put on the backs of the companies that use your products.

We need answers and we need answers soon. Leaving us in the dark about future processes is bad for everyone. It's bad for the community, bad for the companies using your products and eventually it will become bad for those millions of iOS/macOS developers you cherish.

Bring back the portion of WWDC for macadmins - invite us! We would love to talk! :)

Thanks to [Michael Lynn](https://twitter.com/mikeymikey) and [Pepijn Bruienne](https://twitter.com/bruienne) for working with me late Wednesday night. As we continue to dissect this, I hope to see more in-depth discoveries.
