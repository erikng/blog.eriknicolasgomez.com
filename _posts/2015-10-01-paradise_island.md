---
layout: post
title: "Paradise Island - Hiding El Capitan's Free Upgrade Banner"
description: "Upgrade now. Please?"
tags: [El Capitan, Upgrade, macOS, OS X]
---

Yesterday, El Capitan came out and with it came great fanfare...except if you aren't ready to deploy it.

Maybe there is a [Microsoft bug](https://support.microsoft.com/en-us/kb/3098396) holding you back or perhaps it's even an [Apple One](https://forums.developer.apple.com/message/47409#47409). Regardless,  when your users now open the App Store update tab, they will see this.

![Lovely](https://onemoreadmin.files.wordpress.com/2015/10/screen-shot-2015-10-01-at-6-54-34-am.png)

Lovely.

Let's dive a little deeper...

## WebKit

The App Store itself uses WebKit/HTML to display most of its content. Looking at the source file of the Update tab, you will see a div inserted specifically for El Capitan.

```xml
<div id="utd-os-updates" class="lockup-container installations utd-updates updates hidden">
	<table class="no-header">
		<tr class="'installation'">
		  <td>
			<div class="artwork"></div>
		  </td>
		  <td class="description">
			<h2>OS X El Capitan</h2>
			<p class="tagline">A refined experience and improved performance for your Mac.</p>
			<p class="blurb">The next big release of the world's most advanced desktop operating system. Now available as a free upgrade.</p>
			<a href='https://itunes.apple.com/us/app/id1018109117?mt=12' class="learn-more">Learn More</a>
		  </td>
		  <td>
			  <span class="update">
				<span class="status"></span>
				<button class="install-button hidden"></button>
			  </span>
			  <div class="multi-button install-button update-button">

<span class="price">Free Upgrade</span>
<span class="left-cap"></span>
<div class="inner"><span>Free Upgrade</span></div>
<span class="right-cap"></span>
</button>

</div>
		  </td>
		</tr>
	</table>
</div>
```

If you notice, there is a `context-menu` class that contains the phrase `hideosupdate`. This class is what allows you to disable the screen via the first method.

### Method 1 - Right Click - Hide Update
Any user can simply right click on the banner and select `Hide Update`

![Hide Update](https://onemoreadmin.files.wordpress.com/2015/10/screen-shot-2015-10-01-at-7-29-28-am.png)

Simple enough right? But what actually happens when you press this button?

#### The Island

When a user disables the banner, a SQLite database is created at the following location: `~/Library/Containers/com.apple.appstore/Data/Library/WebKit/LocalStorage/https_su.itunes.apple.com_0.localstorage`

Upon opening this database, you will find a key called `didHideUTDIsland`. Apple refers to this banner as the Island and if you pay close attention, the original div also had a mention of "utd". What exactly this means, I'm not 100% sure, but I would assume it simply stands for "update"

To test this, you can easily hide and unhide the banner by moving this database out it's location and then moving it back in. Each time you will need to close out of the App Store or refresh the window.

### Method 2 - Deploying file.
So now that we have the file, we must ensure that this database file is installed onto every user's library. I'm a huge fan of [Outset](https://github.com/chilcote/outset) and more recently [Munki-Pkg](https://github.com/munki/munki-pkg) (you don't need to be a munki user to use munki-pkg!), so this will be my preferred method of deployment.

Personally, when a script calls for a file, I place it in `/usr/local/outset/custom`. This folder does not exist in the default Outset installation, so my munki-pkg creates contains the logic to support this. With that said, it is still pretty straight forward.

The following Outset login-once script should be sufficient:

```bash
#!/bin/sh

if [ -e ~/Library/Containers/com.apple.appstore/Data/Library/WebKit/LocalStorage/https_su.itunes.apple.com_0.localstorage ]
    then
        rm -rf ~/Library/Containers/com.apple.appstore/Data/Library/WebKit/LocalStorage/https_su.itunes.apple.com_0.localstorage
        cp -R /usr/local/outset/custom/https_su.itunes.apple.com_0.localstorage ~/Library/Containers/com.apple.appstore/Data/Library/WebKit/LocalStorage/
    else
        mkdir -p ~/Library/Containers/com.apple.appstore/Data/Library/WebKit/LocalStorage
        cp -R /usr/local/outset/custom/https_su.itunes.apple.com_0.localstorage ~/Library/Containers/com.apple.appstore/Data/Library/WebKit/LocalStorage/
fi
```

By simply dropping a script into `/usr/local/outset/login-once`, Outset will cause _every_ user that logs in to run it, in their own context.

You will find my the script I am using, as well as the munki-pkg files at my [Github](https://github.com/erikng/munki-pkg-projects/tree/master/Outset_OL_HideUTDIsland)

## Caveat Emptor
Since we are removing this file if it exists, there is a chance that users may lose other updates that they have hidden. Some may find this an added bonus, while others will shake their heads in disapproval. 

If either of these items concern you, you may want to rewrite the script to not remove the file and simply check if it exists first.

## Notes
If you have never used munki-pkg before, it is a very straight forward approach to building packages. There is no UI and it is fast and easy to learn. Hopefully this is reason enough to test it out.

## Sorry Apple!

![Jack](https://media2.giphy.com/media/wxYgRoM7xDHP2/200_s.gif)
