---
layout: post
title: "Apple’s EFI logonui – managing macOS Sierra’s wallpaper"
description: "Reverse engineering Sierra's new loginwindow."
tags: [loginwindow, macOS, Sierra, efi, wallpaper, macadmin]
---

Update 1: Now with fix (Thanks [Owen](https://github.com/opragel) for inspiration!)

Update 2: Now with safer methodology (Thanks [Michael Lynn/Frogor](https://github.com/pudquick))

Update 3: Now with further management tools/discoveries.

Update 4: Note about non-blurred wallpapers and extra data

A few days ago there was a post on [MacEnterprise](https://groups.google.com/forum/m/#!topic/macenterprise/fU3KWrbNfg8) about issues setting Sierra's login wallpaper. I immediately posted as I had not seen the issues that were described, but after doing a deep dive last night, it is true - there are some changes to this functionality.

### El Capitan Notes
In El Capitan, one could simply do the following:
* Copy your selected wallpaper in .png format to /Library/Caches (Example: `cp -R ~/Desktop/mysuperawesomewallpaper.png /Library/Caches/com.apple.desktop.admin.png`)
* ensure root was the owner (Example: `chown root:wheel /Library/Caches/com.apple.desktop.admin.png` )
* ensure it was world readable (Example: `chmod 755 /Library/Caches/com.apple.desktop.admin.png`
* set idempotent flag, so it cannot be overwritten (Example: `chflags uchg /Library/Caches/com.apple.desktop.admin.png`)

These four steps could be automated with a package/script/etc and were pretty simple to configure.

### Sierra Notes
With Sierra, while this methodology still works, it is incomplete. You will notice the following:
* Loginwindow not get updated
* FileVault pre-boot window not updated
* User lock screen not updated

Unfortunately for the 3rd item, this cannot be modified, as Apple automatically overlays a blur on top of the user's wallpaper. With that said, the other two items can be corrected, albeit with some unfortunate requirements.

### Down the rabbit hole we go...
If you go to System Preferences -> Desktop & Screen Saver and change your wallpaper you will notice that immediately com.apple.desktop.admin.png is changed, the loginwindow is updated and if you reboot, the FileVault pre-boot is also updated.

![loginwindow](https://raw.githubusercontent.com/erikng/blogposts/master/SierraDesktop/loginwindow.png)

Let's do a quick inspection into what could be happening:

```css
<snippedforclarity>
fs_usage | grep desktop
/Users/User/Desktop/test.png
/Users/User/Library/Application Support/Dock/desktoppicture.db
/private/var/folders/zr/57b51nwn08ddmvzlc5fplk1r0000gn/C/com.apple.desktoppicture/83D89DB4E2232FC43CE0DB6E06AFD223-2880.png
/private/var/folders/zr/57b51nwn08ddmvzlc5fplk1r0000gn/T//.6EB3C2D5-43C8-4464-980D-76782C758FEB-com.apple.desktop.admin.png-kmyp
/private/var/folders/zr/57b51nwn08ddmvzlc5fplk1r0000gn/T//6EB3C2D5-43C8-4464-980D-76782C758FEB-com.apple.desktop.admin.png
/Library/Caches/com.apple.desktop.admin.png
```

This is pretty clear as to what is happening. Apple is taking our png, writing it's value to the desktoppicture.db, creating a temporary folder and generating a resolution specific png, then transferring it to /Library/Caches.

So if that's all it does, why is it when we recreate this scenario through a package/script, only some of the elements are updated? Perhaps our grep left out some important pieces...

#### Unleash the Kraken
To give you an idea on why one would grep, fs_usage is _extremely_ verbose. The prior example's output was around 400 event lines, whereas without grep, we are at 281,000 event lines.

With that said, we need to get to the bottom of what is happening.

```css
<snippedforclarity>
fs_usage
/Users/User/Desktop/test.png
/Users/User/Library/Application Support/Dock/desktoppicture.db
/private/var/folders/zr/57b51nwn08ddmvzlc5fplk1r0000gn/C/com.apple.desktoppicture/83D89DB4E2232FC43CE0DB6E06AFD223-2880.png
/private/var/folders/zr/57b51nwn08ddmvzlc5fplk1r0000gn/T//.6EB3C2D5-43C8-4464-980D-76782C758FEB-com.apple.desktop.admin.png-kmyp
/private/var/folders/zr/57b51nwn08ddmvzlc5fplk1r0000gn/T//6EB3C2D5-43C8-4464-980D-76782C758FEB-com.apple.desktop.admin.png
/Library/Caches/.com.apple.updateEFIResources
/usr/standalone/bootcaches.plist
/System/Library/PrivateFrameworks/EFILogin.framework/Versions/A/Resources/efilogin-helper
/System/Library/PrivateFrameworks/EFILogin.framework/Versions/A/Resources/EFIResourceBuilder.bundle
/System/Library/Caches/com.apple.corestorage/EFILoginLocalizations
/Library/Preferences/SystemConfiguration/com.Apple.Boot.plist
/Library/Caches/com.apple.desktop.admin.png
```

What a difference!

A couple of things immediately stick out:
* Two preference files
* Many references to EFI Resources
* A dotfile that seems to trigger an update to the EFI
* A SIP Private Framework with a helper and rebuild tool
* Another cache (!) that is SIP protected

All signs point to EFI resources, but we need to prove this theory.

##### Plists
First, let's take a look at these plist files.
```bash
defaults read /usr/standalone/bootcaches.plist
PostBootPaths =     {
    BootConfig = "/Library/Preferences/SystemConfiguration/com.apple.Boot.plist";
    EncryptedRoot =         {
        BackgroundImage = "/Library/Caches/com.apple.desktop.admin.png";
        DefaultResourcesDir = "/usr/standalone/i386/EfiLoginUI/";
        LocalizationSource = "/System/Library/PrivateFrameworks/EFILogin.framework/Resources/EFIResourceBuilder.bundle/Contents/Resources";
        LocalizedResourcesCache = "/System/Library/Caches/com.apple.corestorage/EFILoginLocalizations";
    };
```
This is fairly interesting. We now know the bootcache BackgroundImage is set (which is why if you simply deploy the admin.png and reboot it works), there is a default EFI boot cache and a subsequent localization EFI boot cache.

```bash
defaults read /Library/Preferences/SystemConfiguration/com.Apple.Boot.plist
{
    "Kernel Flags" = "";
}
```
This preference file is a little less interesting, however this is an older preference file that is becoming less relevant. Older macadmins may remember this was used prior to Mavericks to set a custom boot image.

##### EFI boot caches
```python
ls -lO /usr/standalone/i386/EfiLoginUI/
-rw-r--r--  1 root  wheel  restricted 1069412 Jul 30 15:41 Lucida13.efires
-rw-r--r--  1 root  wheel  restricted 1067888 Jul 30 15:41 Lucida13White.efires
-rw-r--r--  1 root  wheel  restricted   17468 Jul 30 15:41 appleLogo.efires
-rw-r--r--  1 root  wheel  restricted 1060947 Jul 30 15:41 battery.efires
-rw-r--r--  1 root  wheel  restricted  437314 Jul 30 15:41 disk_passwordUI.efires
-rw-r--r--  1 root  wheel  restricted 2656877 Jul 30 15:41 flag_picker.efires
-rw-r--r--  1 root  wheel  restricted  212250 Jul 30 15:41 guest_userUI.efires
-rw-r--r--  1 root  wheel  restricted 2013232 Jul 30 15:41 loginui.efires
-rw-r--r--  1 root  wheel  restricted   56468 Jul 30 15:41 recoveryUI.efires
-rw-r--r--  1 root  wheel  restricted    9882 Jul 30 15:41 recovery_user.efires
-rw-r--r--  1 root  wheel  restricted  170570 Jul 30 15:41 sound.efires
-rw-r--r--  1 root  wheel  restricted  250828 Jul 30 15:41 unknown_userUI.efires
```

So this cache seems to be SIP protected and dated in between Sierra Developer Beta 1 & 2. As we saw in `/usr/standalone/bootcaches.plist`, this is the default cache and probably only used for first-time boots of Sierra.

```python
ls -lO /System/Library/Caches/com.apple.corestorage/EFILoginLocalizations
-rw-r--r--  1 root  wheel  -  1069412 Sep 24 22:03 Lucida13.efires
-rw-r--r--  1 root  wheel  -  1067888 Sep 24 22:03 Lucida13White.efires
-rw-r--r--  1 root  wheel  -    13258 Sep 24 22:03 appleLogo.efires
-rw-r--r--  1 root  wheel  -  1043933 Sep 24 22:03 battery.efires
-rw-r--r--  1 root  wheel  -   443692 Sep 24 22:03 disk_passwordUI.efires
-rw-r--r--  1 root  wheel  -  2832469 Sep 24 22:03 flag_picker.efires
-rw-r--r--  1 root  wheel  -   214346 Sep 24 22:03 guest_userUI.efires
-rw-r--r--  1 root  wheel  - 10392791 Sep 24 22:03 loginui.efires
-rw-r--r--  1 root  wheel  -    25939 Sep 24 22:03 preferences.efires
-rw-r--r--  1 root  wheel  -   171012 Sep 24 22:03 sound.efires
-rw-r--r--  1 root  wheel  -   252398 Sep 24 22:03 unknown_userUI.efires
```
Now we're getting somewhere. These files were modified at the same time we changed the Desktop wallpaper. There's also conveniently a `logonui.efires`, which might be the file we are looking for.

All signs are pointing to this EFI resource location, but we still don't definitely know if this is where the issue is.

### What the hell is an efires file?
If you've never kept up with Hackintosh community, you probably have never heard about these files. [Piker-Alpha](https://pikeralpha.wordpress.com) and his sister (RIP) are largely the ones who first started doing deep dives into these files.

.efires files are EFI Resource files. They are LZVN compressed files, that contain various images that Apple uses during the boot process.

##### Backstory and shameless plug
Last year, with the help [Michael Lynn/Frogor](http://michaellynn.github.io/), I released [BootPicker](https://github.com/erikng/BootPicker), a PSD file for easily creating Apple boot documentation. We dumped the .efire files and [extracted](https://gist.github.com/pudquick/2800b39b68f5acb135b4) the boot files, giving us the exact images for Apple's boot process. It's better than [Apple's own documentation, with fake assets!](https://support.apple.com/en-us/HT204156). Piker/Sam's original work with [LZVN](https://github.com/Piker-Alpha/LZVN) and [efires-extract](https://dl.dropboxusercontent.com/u/126585663/efires-xtract) were instrumental in our success.

I never did a post on BootPicker, but check it out - I think you'll love it!

##### Back to Sierra
Unfortunately, Piker-Alpha's efires-extract does not take into account Sierra's new folder structure, however I have modified it to now work. You can find a copy [here](https://gist.github.com/erikng/b4e2d35253b2e224f019cbc02213872d).

Let's spin it up.
```python
./efires-extract
<snipped>
Filename: loginui.efires
EFI revision: 2
Number of packed images: 119
Header length: 8644
<snipped>
Image(1): loginui_background.png (offset: 15320/0x3bd8, size: 9805757/0x959fbd) Read: 9805757
<snipped>
```

Well look at that. `loginui_background.png` :tada:

So what exactly is that file?

![loginui_background](https://raw.githubusercontent.com/erikng/blogposts/master/SierraDesktop/loginui_background.png)

Oh look, it's the same file as `com.apple.desktop.admin.png`!

So we have definitely confirmed our initial suspicions:

* One simply can't deploy `com.apple.desktop.admin.png` and be done.
* `/System/Library/PrivateFrameworks/EFILogin.framework/Versions/A/Resources/EFIResourceBuilder.bundle` is the key to rebuilding the EFI cache.
* There may be a trigger at `/Library/Caches/.com.apple.updateEFIResources`

### GUI Triggers and CLI SIP Brick Wall
You may already know where this is going.

The following GUI actions, cause EFIResourceBuilder to trigger:
* Right Click, settings Wallpaper
* System Preferences -> Desktop & Screensaver -> Selecting new wallpaper
* System Preferences -> Security & Privacy -> Set Lock Message

In my further investigation using Hopper, I attempted to find out how to use the dot file to trigger updating the EFI. Unfortunately I could not figure it out. I also attempted to configure `/Library/Preferences/com.apple.loginwindow.plist LoginwindowText` which is what the Security & Privacy Lock Message does, but unfortunately that alone did not trigger an EFI rebuild.

Interestingly enough, when googling about the EFILogin framework, I found [this link](https://jamfnation.jamfsoftware.com/discussion.html?id=7531#responseChild40288) on JAMF Nation that outlined a method to trigger the EFI rebuild process.

Let's try it:
```ruby
touch /System/Library/PrivateFrameworks/EFILogin.framework/Resources/EFIResourceBuilder.bundle/Contents/Resources
touch: /System/Library/PrivateFrameworks/EFILogin.framework/Resources/EFIResourceBuilder.bundle/Contents/Resources: Permission denied
```
:unamused:
```python
ls -lO /System/Library/PrivateFrameworks/EFILogin.framework/Resources/EFIResourceBuilder.bundle/Contents/
-rw-r--r--    1 root  wheel  restricted,compressed 1264 Jul 30 18:47 Info.plist
drwxr-xr-x    3 root  wheel  restricted             102 Sep 13 17:57 MacOS
drwxr-xr-x  131 root  wheel  restricted            4454 Sep 24 11:53 Resources
drwxr-xr-x    3 root  wheel  restricted             102 Jul 30 18:48 _CodeSignature
-rw-r--r--    1 root  wheel  restricted,compressed  523 Jul 30 18:48 version.plist
```
:cry:

##### Disabling SIP
I just want to get this out of the way...

**DO NOT DISABLE SIP TO DEPLOY A CUSTOM WALLPAPER!**

We are going to disable SIP, **temporarily**, to test if touching this file still works. You know the drill: reboot, disable, reboot.

```ruby
touch /System/Library/PrivateFrameworks/EFILogin.framework/Resources/EFIResourceBuilder.bundle/Contents/Resources
```

Okay so no more `operation not permitted` errors, but did it work?

```python
ls -lO /System/Library/Caches/com.apple.corestorage/EFILoginLocalizations
-rw-r--r--  1 root  wheel  - 10392791 Sep 24 22:38 loginui.efires
```

Yep! The .efires timestamp are reflecting the current time. So while we had to disable SIP, this method still works and was probably an oversight on Apple's part. Shame on all of _us_ for not noticing this until now.

### Closing Thoughts (OpenRadar)
It's quite apparent that Apple will continue to use the .efires files for their boot process and while they allow an alternative cache to exist, if you want your loginwindow to be updated, you _must_ update the EFI cache.

While I do wish Apple would have more documentation related to Enterprise Management, Apple has historically been cagey on this process. SIP bug withstanding, we now definitely know what the process is:
* Add custom com.apple.desktop.admin.png to /Library/Caches
* Take ownership of the png and mark it as idempotent to ensure no one else can modify it accidentally
* Rebuild EFI cache for loginwinow and FileVault screens

For admins that want to duplicate my issue or reach out to their System Engineer, here is the link.

[rdar://28462923](https://openradar.appspot.com/radar?id=4982909354115072)

### Updated with fix
Thanks to some detective work by my buddies, we have found an alternative method to triggering the event.

```bash
defaults read /System/Library/PreferencePanes/DesktopScreenEffectsPref.prefPane/Contents/Resources/DesktopPictures.prefPane/Contents/Resources/com.apple.updateEFIDesktopPicture.plist
{
Label = "com.apple.updateEFIDesktopPicture";
ProgramArguments = (
"/usr/sbin/kextcache",
"-u",
"/"
);
```

From the manpage of kextcache:
```
-u os_volume, -update-volume os_volume

Rebuild out-of-date caches and update any helper partitions associated with os_volume.
os_volume/System/Library/Caches/com.apple.bootstamps/ is used to track whether any helper partitions
are up to date. See -caches-only and -force.

Which caches are rebuilt depends on the Mac OS X release installed on os_volume. If kextcache
cannot find or make sense of os_volume/usr/standalone/bootcaches.plist the volume is treated
as if no caches need updating: success is returned.
```

By invoking kextcache, we can update the caches! We just need to force it, since once has previously been created.

Here are the exact steps to have a working/admin deployed LoginUI.
* Copy your selected wallpaper in .png format to /Library/Caches (Example: `cp -R ~/Desktop/mysuperawesomewallpaper.png /Library/Caches/com.apple.desktop.admin.png`)
* ensure root was the owner (Example: `chown root:wheel /Library/Caches/com.apple.desktop.admin.png` )
* ensure it was world readable (Example: `chmod 755 /Library/Caches/com.apple.desktop.admin.png`
* set idempotent flag, so it cannot be overwritten (Example: `chflags uchg /Library/Caches/com.apple.desktop.admin.png`)
<del>* delete the unprotected EFI caches (Exmaple: `rm -rf /System/Library/Caches/com.apple.corestorage/EFILoginLocalizations/*.*`)</del>
<del> * force a rebuild of the cache (Example: `/usr/sbin/kextcache -fu /`)</del>

### Update 2

Instead of deleting the unprotected EFI caches and using kextcache, you can do the following:

* touch `/System/Library/Caches/com.apple.corestorage/EFILoginLocalizations`
* force a rebuild of the cache (Example: `/usr/sbin/kextcache -fu /`)

Much love to the `-fu` flag Apple. :)

### Update 3
Earlier someone reached out to me and informed me that the login screen was not being truly forced. After looking at things again, I discovered `/System/Library/PrivateFrameworks/LoginUIKit.framework/Versions/A/LoginUIKit`. In this binary are some interesting leads.

This tool automatically creates a gaussian blur each time the loginwindow is displayed to the end user. By default it will look at `/System/Library/CoreServices/DefaultDesktop.jpg` which is actually a SIP protected symbolic link that in Sierra points to `/Library/Desktop Pictures/Sierra.jpg`. Pay close attentions here. While the symbolic link is protected, the default Sierra wallpaper is not.

If an admin wants have a default wallpaper upon login for their users _and_ a default loginwindow for their users, replacing this jpg with a custom one would be sufficient.

But what if an admin wants to control this at all times? Interestingly enough, while not documented anywhere online, Apple created a special preference for just this thing! There is a key `ForceDefaultDesktop`, a boolean type that can be enabled on `com.apple.loginwindow`.

To finalize - If an admin wants to fully control the FileVault EFI loginwindow _and_ the user loginwindow, one must do everything from Update 2 and the following:

* Replace /Library/Desktop Pictures/Sierra.jpg with a custom picture (Example: `cp -R ~/Desktop/mysuperawesomewallpaper.jpg /Library/Desktop Pictures/Sierra.jpg`
* Optionally make the new Sierra.jpg idempotent to prevent changes. (Example: `chflags uchg /Library/Desktop Pictures/Sierra.jpg`)
* Configure com.apple.loginwindow (Example: `defaults write /Library/Preferences/com.apple.loginwindow ForceDefaultDesktop -bool true`)

To be clear, this method will use a gaussian blur at the loginwindow, but allow you to force a specific wallpaper.

### Update 4
In further testing, if your non-blurred wallpaper is not working, there are chances that you have extra `EXIF` data added to your png, which will cause the loginwindow to bail and use the default Sierra wallpaper.

I recommend opening up your wallpaper in `Preview.app` and then saving it. This should remove the extra data and your wallpaper should then load at the loginwindow.


*This post proudly brought to you by, 3.5mm jack headphones.
