---
layout: post
author: Erik Gomez
title: "macOS testing tricks - Reusing base images and obtaining a root shell prior to SetupAssistant with LanguageChooser"
description: "Since Apple cannot supply installer apps"
tags: [AutoDMG, DEP, SetupAssistant, vfuse]
published: true
date: 2018-03-26 13:00:00
comments: true
---

Recently, [Chris Collins](https://chris-collins.io/2018/03/15/Using-Terminal-At-macOS-Setup-Assistant/) wrote an awesome blog post around some shortcut keys to get a Terminal window during the SetupAssistant. In the comments, Matthew Lavine wrote something that caught my attention:

> Just an FYI, if the Mac comes up with the Language Chooser before the Setup Assistant then you can use the Terminal shortcut to get a root terminal.

See below for a few tricks I use and how I ultimately obtained a root terminal.

## macOS testing trick 1 - Reusing base images with AutoDMG.
Years ago, [Per Olofsson](https://github.com/MagerValp) blew my mind when he told me you could drag and drop an AutoDMG and use that as a source file. Since then, my process for rapidly testing images (whether for DEP testing or otherwise) has been the following:

1. Drag and drop the base installer app.
2. Uncheck the `Apply updates` option.
3. In the AutoDMG menu, go to `Window` -> `Advanced Options` and increase the `Volume Size`. I personally use 100GB.
4. Create the DMG.

![AutoDMG - Base Image](/images/2018/03/base_image.png)
![AutoDMG - Base Image - Advanced Options](/images/2018/03/base_image_advanced_options.png)
![AutoDMG - Base Image - Save](/images/2018/03/base_image_save.png)

Once you have your base image, use this as your base:

1. Drag and drop the resulting dmg.
2. Check the `Apple updates` option.
3. In the AutoDMG menu, go to `Window` -> `Advanced Options` and increase the `Volume Size`. I personally use 100GB.
4. Add any custom pkgs you wish to install.
5. Create the DMG.

![AutoDMG - Custom Image](/images/2018/03/custom_image.png)
![AutoDMG - Custom Image - Save](/images/2018/03/custom_image_save.png)

## macOS testing trick 2 - Enabling LanguageChooser prior to SetupAssistant with AutoDMG and munki-pkg
So after seeing Matthew's comment I began googling and ultimately found a dotfile that would launch LanguageChooser. By simply touching `/private/var/db/.RunLanguageChooserToo`, the LanguageChooser would open up _prior_ to SetupAssistant.

I made an installation package with [a custom munki-pkg configuration](https://github.com/munki/munki-pkg/pull/30) and then added this to my custom AutoDMG image.

![AutoDMG - Custom Image](/images/2018/03/custom_image.png)


## macOS testing trick 3 - Using vfuse templates to create a DEP capable VM with a pre-allocated snapshot
Now that I had a custom image, I needed to pass that onto one of my favorite tools, [vfuse](https://github.com/chilcote/vfuse).

While most people work with vfuse through it's main arguments, I prefer to only use vfuse's template argument.

`vfuse -t /path/to/template`

By creating a template, you can easily create new virtual machines as quickly update your templates when a new OS version comes out.

This is my `DEP-MBA-10.13.3.json` template that I use to test a DEP capable MacBook Air. By creating a "preboot" snapshot I can also quickly get back to a never-booted state in seconds. This is extremely useful when you are working on your DEP workflow and run into an issue that you need to fix and re-test.

```json
{
    "source_dmg": "/dmgs/osx_updated_180125-10.13.3-17D47.apfs.dmg",
    "output_dir": "/Virtual Machines",
    "output_name": "DEP-MBA-10.13.3",
    "hw_version": 14,
    "mem_size": 4096,
    "bridged": false,
    "hw_model": "MacBookAir7,2",
    "snapshot": true,
    "snapshot_name": "preboot",
    "serial_number": "SERIALNUMBER"
}
```

## macOS testing trick 4 - Using LanguageChooser to get a root shell and create an updated, quasi-never-booted virtual machine.
Now that we have our custom DMG and a virtual machine configured with the LanguageChooser package, let's see what we get.

![Virtual Machine - LanguageChooser](/images/2018/03/virtual_machine_language_chooser.png)

If we use the keyboard shortcut `CTL + OPTION + CMD + T`, we can now get a _root_ shell. This allows us to do other things, like updating to the latest beta Operating System. This could be useful if Apple provides a beta Operating System application, but doesn't update it for future beta builds...

Of course they would _never_ do that...

![Virtual Machine - Root Shell SoftwareUpdate](/images/2018/03/virtual_machine_root_shell_softwareupdate.png)

So once you have a root shell, you can enroll into the beta channel with `seedutil`.

`/System/Library/PrivateFrameworks/Seeding.framework/Versions/A/Resources/seedutil enroll DeveloperSeed`

Immediately run `softwareupdate` to download any available updates.

`softwareupdate -i -a --restart`

If your machine doesn't reboot after triggering the initial installation, run `reboot`.

You should see this.

![Virtual Machine - Installing Updates](/images/2018/03/virtual_machine_installing_updates.png)

Once the installation is finished, you can validate that it has been successfully updated by running `sw_vers`.

![Virtual Machine - Validating Update](/images/2018/03/virtual_machine_validating_update.png)

From here, issue a `shutdown` command and immediately create a new shapshot. By utilizing this method, you can now create a fully up-to-date, quasi-never-booted virtual machine for testing things like DEP. It's about as close as you can get without a full application installer.

## Final Thoughts
While this method isn't perfect and cannot be reliably automated, it is a great way to test beta macOS versions without application installers. Thanks to Chris and Matthew for originally documenting the pieces needed to do this.

## TL/DR
1. Create a custom AutoDMG image and use the [custom munki-pkg](https://github.com/munki/munki-pkg/pull/30)
2. Convert the dmg to a virtual machine with vfuse
3. Boot into virtual machine and once you see the LanguageChooser, use the `CTL + OPTION + CMD + T` keyboard shortcut.
4. With a root shell, you can now run any root command you would like.
5. If you need to, enroll into one of the beta seeds by using seedutil: `/System/Library/PrivateFrameworks/Seeding.framework/Versions/A/Resources/seedutil enroll DeveloperSeed`
6. Update the Operating System with softwareupdate: `softwareupdate -i -a --restart`
7. The virtual machine should reboot, but if it doesn't, use `reboot` to initiate a reboot.
8. Once the Operating System is back at LanguageChooser, initiate a shutdown with `shutdown`.
9. Create a snapshot and use this as your base.
10. Get to testing :)

## Table Of Contents
* Do not remove this line (it will not be displayed)
{:toc}
