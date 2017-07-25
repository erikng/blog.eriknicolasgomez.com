---
layout: post
author: Erik Gomez
title: "Kextpocalypse - High Sierra and kexts in the Enterprise"
description: "Imaging 1, DEP 0"
tags: [Enterprise, High Sierra, Kexts, macOS]
published: true
date: 2017-07-25 01:00:00
comments: true
---

On June 19th, Apple released a document describing how loading secure kernel extensions (.kext) would change with High Sierra and how this would impact enterprise customers.

# No one is breaking NDA by talking about this

You can find Apple's public documentation [here](https://developer.apple.com/library/content/technotes/tn2459/_index.html)

# Quick overview

When you install an application on High Sierra that includes a kext, when that kext attempts to load (during the installation or during application launch), you will receive the following UI message:

![System Extension Blocked](https://developer.apple.com/library/content/technotes/tn2459/Art/tn2459_blocked.png)

From this point, the user has only **30 minutes** to approve the kernel extension by doing the following:
1. Open **System Preferences**
2. Go to the **Security & Privacy** section
3. In the **General** tab, press on the **allow** button

Here is an example of what the UI will look like:

![Allow System Extension](https://developer.apple.com/library/content/technotes/tn2459/Art/tn2459_approval.png)

What this does is add the **Team ID** taken from the kext's signature and adds it to the list of approved Team IDs. From this point on, _all_ kexts signed by the same Team ID will be approved.

# How does this impact me as a Enterprise admin/user?
If you deploy the following types of software, you may be impacted:
- Antivirus products (Ex: [Carbon Black](https://www.carbonblack.com/))
- Audio production
- Code creation tools (Ex: [Android Studio](https://developer.android.com/studio/index.html))
- Compliance software (Ex: Google's [Santa](https://github.com/google/santa))
- Communication software (Ex: [RingCentral](https://www.ringcentral.com/) or [Zoom](https://zoom.us/download))
- Drivers (Ex: [HP Printer Drivers](https://support.hp.com/us-en/drivers) or [Logitech Options](http://support.logitech.com/en_us/product/mx-master/downloads))
- File Syncing tools (Ex: [Dropbox](https://www.dropbox.com/install) or [Google Drive](https://www.google.com/drive/))
- Video production
- Virtualization tools (Ex: [VMware Fusion](https://www.vmware.com/products/fusion.html))

## Discovering kexts
There are a couple of easy ways to find the majority of kexts on your system.

`/usr/bin/mdfind 'kMDItemFSName=*.kext'`

On my system alone, this found the following third part kexts:
```
/Library/Extensions/LogiMgrDriver.kext
/Library/Extensions/hp_io_enabler_compound.kext
/System/Library/Extensions/ConferSensor.kext
/Library/Extensions/SoftRAID.kext
/Library/Extensions/PromiseSTEX.kext
/Library/Extensions/HighPointRR.kext
/Library/Extensions/HighPointIOP.kext
/Library/Extensions/CalDigitHDProDrv.kext
/Library/Extensions/ArcMSR.kext
/Library/Extensions/ATTOExpressSASRAID2.kext
/Library/Extensions/ATTOExpressSASHBA2.kext
/Library/Extensions/ATTOCelerityFC8.kext
/Library/Extensions/ACS6x.kext
/Library/Application Support/VirtualBox/VBoxUSB.kext
/Library/Application Support/VirtualBox/VBoxNetFlt.kext
/Library/Application Support/VirtualBox/VBoxNetAdp.kext
/Library/Application Support/VirtualBox/VBoxDrv.kext
```

If I run `kextstat -l`, this shows me what kext's are currently running.

```
com.vmware.kext.vmci (90.8.1)
com.vmware.kext.vmnet (0582.40.40)
com.vmware.kext.vmx86 (0582.40.40)
com.vmware.kext.vmioplug.15.2.1 (15.2.1)
```

### Why are there loaded kexts that mdfind didn't discover?
mdfind (Spotlight) only indexes common folders. In this case, vmware has bundled their kext's inside of their application bundle (.app) and mdfind by default will not index this. Due to limitations with these tools and others, I have written a python script that will attempt to find all kexts, loaded or on disk and collect them.

You can find my script [here](https://gist.github.com/erikng/d85b17e6e13fd8dcad7cf51d1c6b3a1c)

As you can see below, the tool was able to find kexts that mdfind didn't see, but kextstat showed as running.

```json
"IdentifiedKexts": [
    {
        "Identifier": "com.vmware.kext.vmioplug.15.2.1",
        "KextPath": "/Applications/VMware Fusion.app/Contents/Library/kexts/vmioplug.kext",
        "Version": "15.2.1"
    },
    {
        "Identifier": "com.vmware.kext.vmx86",
        "KextPath": "/Applications/VMware Fusion.app/Contents/Library/kexts/vmmon.kext",
        "Version": "0582.40.40"
    },
    {
        "Identifier": "com.vmware.kext.vmnet",
        "KextPath": "/Applications/VMware Fusion.app/Contents/Library/kexts/vmnet.kext",
        "Version": "0582.40.40"
    },
    {
        "Identifier": "com.vmware.kext.vmci",
        "KextPath": "/Applications/VMware Fusion.app/Contents/Library/kexts/VMwareVMCI.kext",
        "Version": "90.8.1"
    },
    {
        "Identifier": "zoom.us.ZoomAudioDevice",
        "KextPath": "/Applications/zoom.us.app/Contents/Plugins/ZoomAudioDevice.kext",
        "Version": "1.1"
    },
    {
        "Identifier": "com.confer.sensor.kext",
        "KextPath": "/System/Library/Extensions/ConferSensor.kext",
        "Version": "1.2.1fc10"
    },
    {
        "Identifier": "org.virtualbox.kext.VBoxDrv",
        "KextPath": "/Library/Application Support/VirtualBox/VBoxDrv.kext",
        "Version": "5.0.24"
    }
]
```

## Legal compliance and security
Once you have identified which products your company uses that may be impacted by this change, you should communicate with your security team (if you have one). You may find out that some of the tools your company uses are directly needed for **compliancy and/or security** reasons.

## What if our company needs product X for compliance/security reasons?
If this is the case, you may need to re-think your strategy around macOS. If you cannot adequately stay in compliance, these devices may no longer suite your business needs. Regardless, **these decisions should not be taken lightly and should not be decided by your IT organization**. You should consult with your company's senior leadership before making any actions.

## Interim communication with your helpdesk
The `spctl kext-consent` command is similar to the `csrutil` command as it stores it’s values in **NVRAM**, and in that the machine must be booted from Recovery or Netboot to correctly set the values. This means that if the [PRAM is reset](https://support.apple.com/en-us/HT204063), the kext-consent values are now reset to the _default_ values.

- If you have completely disabled kext-consent, it is now active.
- If you had trusted Team ID's via the spctl command, they are no longer trusted.

Put simply, PRAM resets should **not be used for basic troubleshooting** and should only be used as a last resort. If your technicians do this, you may want to have some documentation on how to re-add the Team ID's in the recovery OS.

Note: Team ID's trusted via the GUI will still be trusted.

## What if my users are not admins?
As the `Security & Privacy` section in _System Preferences_ requires admin rights to unlock, standard users are not allowed to authorize kext consent. You may have to modify the [authorization database](https://developer.apple.com/library/content/technotes/tn2095/_index.html) to allow this, which may not be an acceptable workaround for your company.

# Provisioning

## What if I still image?
Hey you're in luck! On July 12th, Apple updated the document for High Sierra beta 3 -You can now use NetBoot as it is not a SIP protected operating system to run the `spctl kext-consent` command.

## What if I use DEP and MDM?
As currently architected, enterprise customers using DEP **do not** have the ability to automatically approve Team IDs or completely disable this feature.

# What should we do as Enterprise customers?
1. Find your impacted software and contact the companies that developer the software immediately
2. Begin internal company discussions about macOS High Sierra and machine compliance.
3. File radars, AppleSeed tickets and AppleCare Enterprise tickets. Give impact data with the amount of machines that will be negatively impacted and the software you use.
4. If you use DEP/MDM only - file additional tickets asking how you are supposed to use `spctl kext-consent`.

# Final Thoughts
On July 20th, [Felix Schwarz](https://twitter.com/felix_schwarz/status/887945239977242624) on Twitter posted an email from Apple Developer Relations:

![Kextpocalypse](https://pbs.twimg.com/media/DFKbICyXgAAyC-u?format=jpg)

I was hopeful that Apple may change their mind here when realizing this wasn't ready as it's quite clear that either Apple engineering didn't consult with the Apple enterprise engineering team, but it looks like Kextpocalypse is here and it's not going away.

What is most aggravating is the clear dissonance in Apple enterprise and the businesses that purchase macOS products.

If DEP is the future, then why are "features" like this coming out for recovery/NetBoot only?

**Apple, if this feature isn't ready for Enterprise customers, it isn't ready for production. Fix DEP and then implement this.**


## Table Of Contents
* Do not remove this line (it will not be displayed)
{:toc}
