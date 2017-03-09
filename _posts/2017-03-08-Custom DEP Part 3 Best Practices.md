---
layout: post
author: Erik Gomez
title: "Custom DEP - Part 3: Best Practices"
description: "Don't make your fellow employees hate you."
tags: [macOS, DEP, MDM, EMM, AirWatch, Best Practices]
published: true
date: 2017-03-08 17:40:00
comments: true
image: /images/2017/03/dep_installapplication_Custom.png
---

In part [2](/2017/03/09/Custom-DEP-Part-2-Creating-a-custom-package-and-deploying-Munki/), I showed you how to build a standard munki package and then how you could extend this concept and create a completely custom package. But with great power, comes great responsibility. Here are some best practices for using a custom DEP configuration, some ideas to try and things to watch out for.

## Do's

#### User Experience
- Give the user some kind of notification that their machine is being enrolled into a management framework. Optionally send them another notification when their machine is ready to be used.
- Try to keep the bootstrapping under 3-5 minutes. Anything over this will become annoying.


#### Signed Package
- Try to keep it as modular/light as you can.
- Attempt to download external resources (if needed) outside of the package or in a way that the package itself does not have to be continually maintained. (monolithic vs dynamic packaging)
- Log **everything**. Should an error occur during the bootstrapping process, you need the user to be able to articulate what happened. Unlike imaging, you cannot just start the process over again.
- Create a fail-safe in case of install failures.


#### Munki
- Make as much software as you can self-service. If you can, make _all_ software self-service.
- Delay any potential Apple software updates until after your dep bootstrap is finished.
- Don't force any reboots during your dep bootstrapping.


#### Profiles
- Profiles signed/encrypted by the MDM are **non-removable** if flagged correctly. Profiles installed by Chef/Puppet/Munki can be removed via the `profiles` command. If you want to ensure a setting is 100% managed (Ex: munki's primary URL), use the MDM's tooling. Chances are they support custom profiles.

## Dont's

#### User Experience
- Don't take over the [user's active session](https://github.com/ftiff/CasperSplash) to inform the user that the bootstrapping process is running. This will only annoy your customers.


#### Munki
- Don't deploy large applications like Xcode or Microsoft Office during your DEP bootstrap. This will only annoy your customers and lengthen the time to finish.

## Clever things to try:
- Caffeinate your machines during DEP bootstrapping to ensure they don't go to sleep: `/usr/bin/caffeinate`
- Utilize [Yo](https://github.com/sheagcraig/yo) for your bootstrap status. You can use persistant notifications.
- Utilize [Outset](https://github.com/chilcote/outset) to run scripts in the user context.
- Create a munki `dep` manifest that installs only the absolute minimum amount of tooling you need. Instead of using munki's [bootstrapping](https://github.com/munki/munki/wiki/Bootstrapping-With-Munki) method, call munki with the --id flag. `/usr/local/munki/managedsoftwareupdate --id dep`. If utlizing this approach, don't [bother](https://github.com/munki/munki/issues/695) pre-installing the munki icons.
- Managed Software Center.app will not automatically looks for updates when a munki run has recently ran. You can force this to happen by removing the `LastCheckDate` value from /Library/Preferences/Managed Installs.plist.
- You can speed up the next munki run by triggering a quiet run `/usr/local/munki/managedsoftwareupdate --checkonly --quiet`.

## Things to keep in mind:
- A distribution package with multiple flat packages will perform all operations in order. _All_ preinstall scripts will run **first**, followed by the files being installed, and finally **_all_** postinstall scripts will run. If you have any dependencies between the packages, they may fail or you will have unintended side effects. If you need to utilize pre/postinstall scripts, be cautious and test often.
- If you use [chef](https://github.com/facebook/IT-CPE/tree/master/chef/cookbooks/cpe_launchd) to manage your launch agents/launch daemons, make sure that you do this after munki has finished running or before, but _never_ during. Killing these daemons will break a munki run.
- If you need to enforce FileVault encryption, you will more than likely need to have your users reboot 1-2 times. Handle this **outside** of your dep bootstrapping process to lower the chances of race conditions.

- Have fun. This is new territory and there won't be much documentation until more people start using this methodology.


## Table Of Contents
* Do not remove this line (it will not be displayed)
{:toc}
