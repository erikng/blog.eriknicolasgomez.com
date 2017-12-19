---
layout: post
author: Erik Gomez
title: "Custom DEP - Part 8: Things to look out for"
description: "There's a lot of dragons."
tags: [macOS, DEP, MDM, EMM, InstallApplication, InstallApplications, mdmclient]
published: true
date: 2017-12-18 12:00:00
comments: true
---

On November 27th, 2016, my current employer and AirWatch decided to go down the route of collaborating on custom DEP. Almost fourteen months later, I'm realizing just how important this decision was, both to my professional career and my company's worldwide macOS deployment. With the release of macOS 10.13.2/[User Approved MDM enrollment](https://support.apple.com/en-us/HT208019) and changes to how [SecureToken](https://support.apple.com/en-us/HT208171) operates in FileVault environments, many macadmins have felt the pressure to quickly implement some form of MDM. It's an ugly, reactionary situation.

While the custom DEP journey is ultimately a highly satisfying and rewarding process, your beginning steps feel like a Home Alone sequel - you'll be stepping on a lot of glass and you will get burned by some parent process (hey mdmclient!).

It's still worth it, and I'm here to help.

# The basic building blocks of a good, custom DEP enrollment
While every company has unique requirements, you can ultimately boil down a good, custom DEP enrollment to the following:

- MDM supporting custom packages using mdmclient (InstallApplication)
- User Experience (UX) tooling
- **Ordered** orchestration of some kind (more on this soon)
- Core administration/security tooling
- Core user applications
- Speed

While most macadmins would think the core tooling are the most important aspect of custom DEP, they would be wrong. Put simply, if your users are unboxing their own machines, the **user experience** is the absolute most important aspect to your deployment. This is the _first_ thing your employees will see and will define how they view your IT team. Give them a lasting impression.

## There's several flavors of DEP you may want to handle.
Depending on the complexity of your deployment, you may have to handle more types of DEP enrollments than you initially expected. Here's a few examples of enrollments I've had to write cases for:

- Out of the box DEP user enrollments
- "dep nag" upgrades
- Legacy deployments + "dep upgrades"

# Don't step on the glass and try not to get burned
Throughout the past fourteen months, I have refactored my company's process no less than _five_ times, which does not include small python refactors. Here are the things I think you should try to avoid at all costs.

## DEP issues
So let's get this out of the way first. There's some really shitty bugs that you'll have to contend with.

### [Sending multiple InstallApplication commands to a macOS device causes only one to download/install despite responding Acknowledged to each command](https://openradar.appspot.com/radar?id=4927456712589312) and [storedownloadd hangs and blocks install of other applications](https://openradar.appspot.com/26517261)

This is a big one. While MDM's like AirWatch, MicroMDM and SimpleMDM allow you to send _multiple_ signed packages through mdmclient, **don't do it**. What will happen is only a single package will be processed for installation and subsequent installations will fail, until the device is rebooted.

### [/usr/libexec/mdmclient dep nag does not nag if user has doNotDisturb enabled
](https://openradar.appspot.com/35571322)

This one isn't as huge (and some may not view this as a bug) but for us it was very disappointing to experience this. As several of our users set doNotDisturb often, users were never seeing nags. To get around this, I wrote a tool called [Naggy](https://github.com/erikng/mdmscripts/tree/master/dep/tools/naggy) that forcibly disables doNotDisturb, right before a dep nag is sent to the device. While this might be too "big brother", I felt it was necessary.

### [/usr/libexec/mdmclient should be able to enroll into DEP mdm](https://openradar.appspot.com/35295502)

While this one shouldn't surprise many, it is unfortunately a bitter pill to swallow with the upcoming Spring changes, UAKEL and UAMDM. This issue, in conjunction with the doNotDisturb, will impact your DEP deployments. You may have to figure out other carrots (or better yet sticks) to force your users to enroll into DEP.

## Don't stuff scripts into payload-free packages.
While payload-free packages are great tools that we inevitably need to use at times, these should not be used during DEP enrollments.

During DEP, the installer environment is invoked by mdmclient. This leads to spectacularly undefined behavior/traces with specific types of cli tools that may be invoked by your scripts (that you will see in the install.log).

Here are just some of the problems I have seen with this methodology:

- Scripts called by normal installer environment (installer -pkg ./package.pkg -target /) behaving differently during DEP
- Scripts calling user actions hanging installer indefinitely.
- Scripts calling munki hanging installer, which inevitably indefinitely hangs any munki run's that install .pkg/.mpkg files.
- Scripts not logging properly
- Scripts hanging entire DEP workflow until they finish
- Added build process complexity when doing rapid testing (test pkg, see failure, update script, update pkg, deploy pkg, re-test)

## Reduce complexity at all costs
While everyone's tool chains are different, you should ask yourself "Do I actually need this tool?".

At the very least you need the following:
- A daemonized process (running as root) for higher level orchestration
- An agent process (running as the user) for user level orchestration
- Some user experience GUI.

Tools that include launch daemons/agents for their own orchestration may not be needed _during_ DEP and should be excluded.

Try to deploy one LaunchAgent and one LaunchDaemon and write them in a way where they can serve multiple purposes. This will reduce the odds of failures when enabling them.

## Focus on efficiency
Any process that can be reduced in scope during your initial DEP run should be.

Reduction examples:
- VPN Software
- Software suites (Microsoft Office, Adobe tools)
- Apple software updates
- Anything that requires a reboot.

You can automate these processes immediately after your DEP enrollment has completed.

Beyond this, your process should invoke your user experience as quickly as possible. In other words, your deployment should look like this:

- Install core tooling
- Initiate user experience
- Run tooling
- Inform user of DEP process completion
- Silently continue on post-DEP process or reboot device.

## You're going to make a shitload of changes in the beginning
There's no way to sugar coat this. You're going to be spending a shitload of time making small changes here and there in your workflow.

Worse, if you do some of the things I suggest not to (like using payload-free packages), you're going to code big changes and then test them, rather than make small changes, one at a time.

**Don't make this mistake!** Refactor your code in small spurts and test often. Ensure your tooling allows you to do this with confidence and doesn't get in the way of you making a _better_ DEP enrollment for your users.

## Summarizing custom DEP common issues
In summary, most custom DEP environments will require the following:

1. Ability to install multiple packages that won't lock up mdmclient
2. macadmin tooling and user experience tooling
3. Root process that should be a dynamic LaunchDaemon vs using installer/payload-free packages.
4. User process that should be a dynamic LaunchAgent
5. Ability to specify when/how your tools should run.
6. Ability to run macOS tools that don't interfere/block other aspects of your DEP enrollment.
7. Ability to make rapid changes as easily as possible with as few roadblocks as possible.

# In my opinion, [InstallApplications](https://github.com/erikng/installapplications) is the clear answer for these issues.
Throughout my journey, I have hit all of these issues. That's why I wrote and continue to enhance [InstallApplications](https://github.com/erikng/installapplications).

In my opinion, InstallApplications is the **orchestrator** for your DEP enrollment. It's designed to install _all_ of the basic building blocks needed for enrollment and solves every common issue related to DEP.

In an upcoming blog post, I will show you exactly how you can use InstallApplications to get a working DEP enrollment.

---

Hey JAMF - how about you join this custom DEP thing?


## Table Of Contents
* Do not remove this line (it will not be displayed)
{:toc}
