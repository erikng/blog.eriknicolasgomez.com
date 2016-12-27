---
layout: post
title: "Using Munki Manifest Selector with Imagr"
description: "It works and it works well."
tags: [Munki Manifest Selector, Imagr]
comments: true
---

There is one tool that is integral to my technicians workflow and my sanity. With several hundred locations, I needed a way to properly set Munki's ClientIdentifier. At previous employers, I was able to define a machine naming convention that worked well, but with so many moving parts where I am at now, I needed something dynamic, consistent and stable: [Munki Manifest Selector](https://github.com/buffalo/Munki-Manifest-Selector)

If you have never used it, I highly recommend at least trying it out. It requires minimal work and although I use an internal fork, the functionality is for the most part identical. Joe has a great post [here](https://denisonmac.wordpress.com/2013/02/09/munki-manifest-selector/)

As I began to test and move my workflows to Imagr, I hit a road block. While both DeployStudio and Imagr have a **generic task**, they are radically different architecturally.

## DeployStudio vs Imagr Generic Task:
### DeployStudio
Since DeployStudio mounts a network volume, the Runtime has direct access to MMS. All an admin needs to do is place both Munki Manifest Selector.app and a corresponding script into the DeployStudio Scripts folder and then call it with a Generic Task. Here is an example script.

```bash
#!/bin/bash
BASE_DIR=`dirname "${0}"`
$BASE_DIR/Munki\ Manifest\ Selector.app/Contents/MacOS/Munki\ Manifest\ Selector\
    --targetVolume "${DS_LAST_SELECTED_TARGET}"\
```

### Imagr
Imagr's Generic Tasks are completely different. In many ways they mimic the behavior of Munki. Scripts are taken from imagr_config.plist and then ran.

```xml
<dict>
    <key>type</key>
    <string>script</string>
    <key>content</key>
    <string>#!/bin/bash
/usr/bin/touch "{{target_volume}}/some_file"</string>
    <key>first_boot</key>
    <false/>
</dict>
```

Unlike DeployStudio, all Imagr components are downloaded individually. What's an admin to do?

## Get Creative - Curl to the rescue!

To begin, let's download MMS [here](https://dl.dropbox.com/u/12228667/Linked%20Files/Munki%20Manifest%20Selector.dmg). For this example please rename the dmg to "Munki_Manifest_Selector.dmg"

If you've followed [Nick McSpadden's Imagr Guide](https://osxdominion.wordpress.com/2015/05/12/we-are-imagr-and-so-can-you/), in your recently made Imagr folder, create a new folder called "packages" and place the DMG there.

```bash
mkdir -p /yourmunkirepo/imagr/packages
```

After placing it there, we need to add a workflow to your imagr_config.plist but let's break this down first.

After pulling down the image and verifying a successful deployment, we are going to utilize Imagr's Generic Task with first_boot disabled. This task is going to do a few things:

- Curl the DMG (using the new deployment's curl binary)
- Mount the dmg using hdiutil from the NBI
- Run Munki Manifest Selector and wait for user input
- Unmount the DMG using hdiutil from the NBI
- Remove the DMG from the deployment

Currently, AutoNBI does not add the curl binary. Don't fret though - it is going to [happen](https://groups.google.com/forum/#!topic/imagr-dev/ssOPfUcb6BU). For now we will use this somewhat hacky method.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>workflows</key>
  <array>
    <dict>
      <key>name</key>
      <string>Munki Manifest Selector Test </string>
      <key>restart_action</key>
      <string>restart</string>
      <key>description</key>
      <string>This workflow deploys an AutoDMG base image with Munki Manifest Selector</string>
      <key>components</key>
      <array>
        <dict>
          <key>type</key>
          <string>image</string>
          <key>url</key>
          <string>http://10.10.10.10/imagr/masters/OS_X_10.10.3-14D136.hfs.dmg</string>
        </dict>
        <dict>
            <key>type</key>
            <string>script</string>
            <key>content</key>
            <string>#!/bin/bash

# Downloading MMS DMG
"/Volumes/Macintosh HD/usr/bin/curl" http://10.10.10.10/imagr/packages/Munki_Manifest_Selector.dmg -o "/Volumes/Macintosh HD/private/tmp/Munki_Manifest_Selector.dmg"
sleep 1

# Mount MMS DMG
hdiutil attach "/Volumes/Macintosh HD/private/tmp/Munki_Manifest_Selector.dmg"
sleep 1

# Run MMS
"/Volumes/Munki_Manifest_Selector/Munki Manifest Selector.app/Contents/MacOS/Munki Manifest Selector" --targetVolume "/Volumes/Macintosh HD"
sleep 2

# Unmount MMS DMG
hdiutil unmount "/Volumes/Munki Manifest Selector"
sleep 1

# Delete MMS DMG
rm -rf "/Volumes/Macintosh HD/private/tmp/Munki_Manifest_Selector.dmg"

exit 0
            </string>
            <key>first_boot</key>
            <false/>
        </dict>
  </array>
</dict>
</plist>
```

## Voila!

That's it. There's no need to re-architect MMS - just simply wrap it in a DMG. Obviously this is a first version and there isn't any download verification but with MMS being so small (~100k) for most deployments this should be sufficient.

Don't stop yourself from moving to Imagr. Get creative and you **will** be happy with the results.