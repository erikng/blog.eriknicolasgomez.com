---
layout: post
author: Erik Gomez
title: "Managing Sierra's Loginwindow - Redux"
description: "An easier approach to managing the loginwindow."
tags: [Loginwindow, macOS, Sierra, EFI, Wallpaper, Macadmin]
published: true
date: 2016-12-28 17:16:08
comments: true
---

[A few months ago](/2016/09/24/apples-efi-logonui-managing-macos-sierras-wallpaper) I wrote a post detailing how to manage the EFI lock screen, loginwindow and trigger the EFI cache. It was updated many times throughout the following days and inevitably caused some confusion.

It turns out, most admins only want to set the background image of the loginwindow and I decided to document an easier process.

#### TL;DR Version?
Read the [How To](#how-to-again) and if you're interested - use the [script](#example-script)

## The Wallpaper
As of 10.12 and higher, your wallpaper __must__ contain an Alpha channel. This part confused many admins who either had a black loginwindow or the default Sierra background. 

Unfortunately, one of my favorite tools, __Pixelmator__, does [not](http://support.pixelmator.com/viewtopic.php?f=4&t=12365) have support for this feature. It doesn't look like they have any [plans](http://support.pixelmator.com/viewtopic.php?f=4&t=9598) to either.

### Photoshop to the rescue
Pixelmator sadness aside, you can use Photoshop to ensure your PNG includes an Alpha channel.

Open your wallpaper file (.PSD, .JPG, .PNG, etc) in Photoshop and do the following:

* File -> Export -> Export As
* Select the `PNG` format
* Check ( :ballot_box_with_check: ) Transparency
* Begin Export

![Photoshop Export As Window](/images/2016/12/PS-ExportAs.png "Photoshop Export As Window")

Once the file has been exported, you can now validate the wallpaper.

Please note that while the loginwindow file sizes may be large, Photoshop is applying compression. You may be able to further compress your wallpaper, but it more than likely isn't worth it. Apple's internal tool renders wallpapers with the exact dimensions needed for the screen size, thereby reducing the file size.

## Validating Wallpaper
There are two easy ways to validate that your wallpaper has an Alpha Channel:

* Finder -> Get Info
* sips tool

### Finder
Right click on the wallpaper -> Get Info.

Under `More Info:` you will see an entry for Alpha channel

![Finder Alpha channel](/images/2016/12/Finder-Alphachannel.png "Finder Alpha channel")

### sips
To validate that your wallpaper has an Alpha channel, you can use the `sips` tool:

Example: `/usr/bin/sips --getProperty hasAlpha /path/to/png`.

```bash
/usr/bin/sips --getProperty hasAlpha /Library/Caches/com.apple.desktop.admin.png

/Library/Caches/com.apple.desktop.admin.png
  hasAlpha: yes
```

## How to (again)
In Sierra, do the following:

* Create your custom loginwindow desktop, ensuring that it contains an [Alpha channel](#the-wallpaper)
* Delete any wallpaper that may already exist (Example: `rm -rf /Library/Caches/com.apple.desktop.admin.png`)
* Copy your selected wallpaper in .png format to /Library/Caches (Example: `cp -R ~/Desktop/mysuperawesomewallpaper.png /Library/Caches/com.apple.desktop.admin.png`)
* Ensure root is the owner (Example: `chown root:wheel /Library/Caches/com.apple.desktop.admin.png`)
* Ensure it is world readable (Example: `chmod 644 /Library/Caches/com.apple.desktop.admin.png`)
* Set idempotent flag, so it cannot be overwritten (even by Apple :smile: ) (Example: `chflags uchg /Library/Caches/com.apple.desktop.admin.png`)

### Example Script
The following is a simple shell script written for this post. You could theoretically use this a `postinstall` script or part of your bootstrap process.

```bash
#!/bin/sh

osxversion=`/usr/bin/defaults read /System/Library/CoreServices/SystemVersion.plist ProductVersion`

# Sierra
if [[ "$osxversion" == *10.12* ]]
    then
        # Delete old admin loginwindow desktop.
        /bin/rm -rf /Library/Caches/com.apple.desktop.admin.png
        # Copy new admin loginwindow desktop.
        /bin/cp -R /path/to/your/png /Library/Caches/com.apple.desktop.admin.png
        # Ensure root is owner
        /usr/sbin/chown root:wheel /Library/Caches/com.apple.desktop.admin.png
        # Ensure only basic read permissions for all users.
        /bin/chmod 644 /Library/Caches/com.apple.desktop.admin.png
        # Set idempotent flag, so no process (including Apple's) can replace the loginwindow desktop.
        /usr/bin/chflags uchg /Library/Caches/com.apple.desktop.admin.png
fi
```

## Enjoy!
Hopefully this is a much easier process that will remove all confusion from the prior reverse engineering post.

## Table Of Contents
* Do not remove this line (it will not be displayed)
{:toc}
