---
layout: post
author: Erik Gomez
title: "Custom DEP - Part 1: An Introduction"
description: "The future is bright - very bright."
tags: [macOS, DEP, MDM, EMM, AirWatch, jamf Pro, MobileIron]
published: true
date: 2017-03-08 17:30:00
comments: true
image: /images/2017/03/dep_overview.png
---

For the better part of six months, macadmins across the world have been worried about the future of macOS. Whether it's the rumblings people have heard about [imaging being killed](https://twitter.com/deploystudio/status/818182860544835584) or that [DEP/MDM](http://michaellynn.github.io/2016/10/04/mDMacOS/) could possibly be the only way to manage macOS devices moving forward, it has definitely made for an interesting time.

What if DEP was the **only** light touch/no touch method for installing your company required assets? What if this requirement comes with APFS/10.13?

These are the questions I have had for months. In this time, some macadmins have have threatened to retire/leave the ecyosystem entirely, while others have raised concerns that their companies may not be able to continue managing Apple products if their toolsets are rendered useless. While both of those thoughts are unsettling, today's post is about positivity.

## This usually bitter macadmin is actually excited.

Why? Well, for a few months now, I've been busy - [V](https://github.com/munki/munki/pull/691) [E](https://github.com/munki/munki/pull/703) [R](https://github.com/chef/ohai/pull/941) [Y](https://github.com/ox-it/munki-rebrand/issues/11) [busy](https://github.com/ox-it/munki-rebrand/pull/13). While some people have started to read between the lines, it's time for me to open up on why I'm excited and how I think many of you will also be eager to join me on this wonderful new adventure.

But first, let's discuss how DEP on macOS works...

## DEP Design and Example of vendor recommended configuration

The following is a typical DEP Scenario for Apple macOS devices:
1. User opens device for the first time
2. SetupAssistant loads and asks the user to connect to a network
3. After connecting to a network, the macOS device is activated
4. If device's serial number is assigned to a DEP-capable MDM server, the device is informed to register with the server and wait for issued commands.
5. Depending on the MDM's configuration, the device will go through "AccountConfigured", "InstallProfile", "InstallApplication" and eventually "DeviceConfigured".
 - User may or may not already be in their console session at this time.

A visual representation:

![DEP_Overview](/images/2017/03/dep_overview.png)

You may have noticed that "InstallApplication" was highlighted. What most people do not realize is that to-date, "InstallApplication" has been **primarily used by MDM vendors to install their own, custom binary**.

A visual representation:

![DEP_InstallApplication_Vendor](/images/2017/03/dep_installapplication_vendor.png)

### A jamf Pro DEP configuration:
A typical jamf Pro DEP design may look like the following:
1. "InstallApplication" installs the jamf Pro binary
2. jamf Pro binary looks for admin configured policies, static groups, smart groups. Otherwise known as "jamf recon"
3. Upon completion of "jamf recon", the jamf binary begins to install packages, run scripts. Otherwise known as "jamf policy -event"

You may have to do something, like the [following](https://github.com/ftiff/CasperSplash/wiki/Setting-up-jamf), due to [vendor design](https://www.jamf.com/jamf-nation/discussions/14638/does-the-package-index-determine-order-of-policies-as-well).:

```
Setting up jamf | Pro

On jamf, policies are run in alphabetical order.

An idea for the setup is:

Create an _Enrollment category (to group policies at top and better see how they flow)
Prefix enrollment policies with two digits incremented by 10 (eg. "00 CasperSplash", "10 Microsoft Office")
Assign packages with name [NAME]-[VERSION].pkg (eg. "Microsoft Office-15.28.pkg")
```

As successful as this has been for some companies, I did not feel like it was adequate enough for my current employer. Worse yet, you have a limited set of tools to diagnose, should an error occur during DEP enrollment.

Let's be clear about something - jamf isn't the only company doing this.

**All** of the major macOS MDM companies are doing this.
- AirWatch
- FileWave
- HEAT LANRev
- jamf
- MaaS360
- MobileIron

## Open Source MDM
After being a bit disappointed with multiple vendor's DEP configurations, I looked at Victor's [MicroMDM](https://github.com/micromdm/micromdm). It is easily the most feature rich open source MDM for macOS and supports "InstallApplication"... but there are some major roadblocks that I couldn't get over.

### 1. MDM is a (constantly changing) beast
MDM has and always will be in flux. The API changes, new features are rolled out and it takes a lot of work just to maintain the management of _profiles_. jamf has over 500 employees and AirWatch has over 2,000. It's amazing how much Victor (and mosen!) have done in such short time. I must commend him.

### 2. We needed more than basic macOS features
A typical company (even a startup) is more than likely going to have a mixture of macOS, Windows, iOS and Android devices. While I don't believe in "single panes of glass", I needed something that at least supported iOS and VPP Managed Distribution. While MicroMDM has some support for iOS, it's target is macOS.

### 3. I have zero background in Go

Go is a rich, powerful language, but I have essentially zero knowledge apart from who built it (Google). I would not feel comfortable deploying open source software that I couldn't help maintain. Most macadmins do not know Go.

### 4. I need to focus on the tools - not the underlying MDM frameworks.
Some may disagree here, but hear me out - As the the only mac IT (and Android/iOS/Windows) engineer at my company, my time is already squeezed to the max. I need to focus on keeping up with the tools and states of my fleet more than the underlying MDM frameworks. It may be a bit ironic stating this, but I would much rather focus my time on python driven tools that I already know and help maintain.

## So wait - you're unhappy with closed source tools and open source tools?
Yep, but rather than sit around and complain on Twitter like I usually do, I decided to do something about it.

Here is my major news: **I am working with one of the largest MDM vendors in the world on adapting InstallApplication for use with custom frameworks**.

This major MDM vendor will allow us (you!) to supply your own, **company signed** distribution package to them and they will install it during a DEP workflow. This means that your "binary" will drive your **own, custom deployment strategy!**

- Using munki? You can deploy munki!
- Using Chef? You can deploy Chef!
- Using Puppet? You can deploy Puppet!
- Using an in-house, custom bootstrapping agent? You can deploy it!
- Using your current vendor's binary? You could deploy that too! (But seriously, don't do that.)

Here is a visual reference on how this will work:

![DEP_InstallApplication_Custom](/images/2017/03/dep_installapplication_custom.png)

### Coming soon to a MDM near you...
Expect this feature soon. How soon? Very soon.

While I cannot announce the vendor at this time, I can say this: I truly feel like this is the best time to be a macadmin. While we are at the cusp of major changes to how we deploy/manage macOS, I truly believe this feature is going to help adoption of DEP/MDM grow, while also allowing macadmins to continue to use their preferred management frameworks.

Use the best tools for the job. Use an industry leading MDM vendor for the MDM part __and__ use industry leading open source stacks.

There is no more _OR_. :pray:

## **Get excited... I know I am.**

Expect more posts soon.

---
For more information on how MDM and DEP works, you can now view the [Apple MDM Protocol Reference](https://developer.apple.com/library/content/documentation/Miscellaneous/Reference/MobileDeviceManagementProtocolRef/1-Introduction/Introduction.html#//apple_ref/doc/uid/TP40017387-CH1-SW1). THANK YOU, Apple, for opening this up last year.

Also, congratulations to [SimpleMDM](https://simplemdm.com/2017/03/07/deploy-munki-apple-dep-mdm/) for beating me to the punch.

## Table Of Contents
* Do not remove this line (it will not be displayed)
{:toc}
