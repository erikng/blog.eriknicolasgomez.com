---
layout: post
title: "Managing (or setting) the Mini TouchBar Control Strip"
description: "A simple way to configure the touchbar for your users."
tags: [Touch Bar, MacBook Pro, macOS, Sierra]
comments: true
---
![MiniBar Hero](/images/2016/11/Customized_Touch_Bar.png "MiniBar Hero")

---

While Apple [documented](https://support.apple.com/en-us/HT207055) how to customize the TouchBar, a macadmin or intrepid user may want to configure it via CLI tools.

The following is a brief overview on how to quickly set these defaults.

## The Control Strip
The Control Strip is the persistant, right area of the Touch Bar. You can customize four quick use actions.

![Control Strip](/images/2016/11/macbook-pro-touch-bar-control-strip-tech-spec.jpg "Control Strip")

You can customize it through System Preferences -> Keyboard -> Customize Touch Bar

Once there, a GUI overlay will be displayed, allowing you to drag the desired customization directly to the Touch Bar.

![Control Strip Customization](/images/2016/11/ControlStripUI.jpg "Control Strip Customization")


## How to configure the Control Strip

### The values
As of 10.12.1, these are the following values you can configure:

* com.apple.system.brightness
* com.apple.system.dashboard
* com.apple.system.dictation
* com.apple.system.do-not-disturb
* com.apple.system.input-menu
* com.apple.system.launchpad
* com.apple.system.media-play-pause
* com.apple.system.mission-control
* com.apple.system.mute
* com.apple.system.notification-center
* com.apple.system.screen-lock
* com.apple.system.screen-saver
* com.apple.system.screencapture
* com.apple.system.search
* com.apple.system.show-desktop
* com.apple.system.siri
* com.apple.system.sleep
* com.apple.system.volume

I think they are fairly easy to comprehend, so I will not be detailing each value. You can customize up to four buttons here and even deploy *zero* button.

The preference file is located at `~/Library/Preferences/com.apple.controlstrip.plist`

``` xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>MiniCustomized</key>
	<array>
		<string>com.apple.system.do-not-disturb</string>
		<string>com.apple.system.media-play-pause</string>
		<string>com.apple.system.sleep</string>
		<string>com.apple.system.volume</string>
	</array>
	<key>last-messagetrace-stamp</key>
</dict>
</plist>
```

The order of the strings are important as they correspond to each of the four items. If you want to change the right icon, change the bottom string.

If you want to deploy a single item, just deploy a single string inside the array.

### Option 1 - Yucky UNIX command

Use this method to quickly _set_ the default values for your users. This could be a `login-once` script via [outset](https://github.com/chilcote/outset) or something similar.

Just know that by using this truly terrible method, a California macadmin loses their wings.

In the userspace:

``` bash
defaults write ~/Library/Preferences/com.apple.controlstrip MiniCustomized '(com.apple.system.do-not-disturb, com.apple.system.media-play-pause, com.apple.system.sleep, com.apple.system.screen-lock )'
```

followed by:

``` bash
killall ControlStrip
```

### Option 2 - Apple Approved Profile
By installing a profile on your devices, you can force a configuration for all users of the TouchBar.

While this might be an "Apple approved" management process, it is clunky for the following reasons:

* The GUI does not inform the user that their TouchBar is being managed.
* The user can customize their TouchBar on top of the management, but after a reboot or logout/login, it will be re-configured per the profile.
* If you attempt to only manage one item in the Control Strip, it will still manage the entire `key` and the user will be limited to one single item.

If you would like a profile example, you can find one [here](https://github.com/erikng/osxprofiles/blob/master/apple/com.apple.controlstrip.mobileconfig). This example configures the ControlStrip in the exact way as the yucky UNIX command.

Note:

While your mileage may vary, you could configure the profile to use a `Set-Once` value versus a `Forced` value. This will be similar to a `defaults write` however it is not gauranteed to work.

For an example profile, see [here](https://github.com/erikng/osxprofiles/blob/master/apple/com.apple.controlstrip-setonce.mobileconfig).

### Option 3 - Chef dynamic profiles.

This is my preferred option as you can manage the configuration of the profile, while also extending the attributes to your userbase.

A user could configure _all_ of their machines with the following chef code:

``` ruby
# Configure MiniBar for DND, Play/Pause, Sleep, & Screen Lock
node.default['cpe_controlstrip']['MiniCustomized'] => [
  'com.apple.system.do-not-disturb',
  'com.apple.system.media-play-pause',
  'com.apple.system.sleep',
  'com.apple.system.screen-lock'
]
```

Please note that this requires the cpe_controlstrip cookbook, which you can find [here](https://github.com/erikng/cookbooks/tree/master/macOS/cpe_controlstrip)

## Example of a single item
In this example we would want to remove all current Control Strip items and replace them with just a single item - the screen lock.

``` bash
defaults write ~/Library/Preferences/com.apple.controlstrip MiniCustomized '(com.apple.system.screen-lock)'

killall ControlStrip
```

Your users would then be left with the following:

![Customized Control Strip](/images/2016/11/Customized_Touch_Bar.png "Customized Control Strip")

## Final Notes
While some macadmins hate over-managing configurations, there is some benefits to this approach:

1. You can now configure a shortcut key to instantly lock your devices. Your security team may love this.
2. Some users may never know or care to customize their Control Strip. This at least allows you to be consistent.
3. More than likely you know what's best for your company, not Apple.

## Table Of Contents
* Do not remove this line (it will not be displayed)
{:toc}