---
layout: post
author: Erik Gomez
title: "Custom DEP - Part 5: Dynamic InstallApplication"
description: "Working around mdmclient's limitations."
tags: [macOS, DEP, MDM, EMM, InstallApplication, mdmclient]
published: true
date: 2017-04-05 18:55:00
comments: true
image: /images/2017/03/dep_installapplication_Custom.png
---

Last month I outlined an upcoming feature for a major MDM vendor. In this time, I have received a lot of amazing feedback, but there have also been some questions that have come up.

While I still can't name the mdm vendor (but I will be able to at the end of this month!), people have been trying out [SimpleMDM's](https://simplemdm.com/) strategy around this same feature. Victor and Jesse have also been really working on making [MicroMDM](https://github.com/micromdm) a production ready tool.

People are excited and beginning to test this, but it seems that some people have hit a couple of roadblocks.

* How do you create a package to deploy munki _and_ install a profile?
* How do you quickly change your package?
* How do you install tool x _and_ tool y at the same time?
* Can `InstallApplication` only be used with DEP? (Nope!)

But before we get to the point of this blog post let's address something that has really bothered me lately...

## mdmclient is brittle AF (aka :pray: it works)
`mdmclient` is the Apple created binary that is used for various MDM functions, but the key one we have targeted lately is `InstallApplication`. While making several iterative changes on my primary package, I accidentally deployed the wrong AppManifest.plist to my test machine - this resulted in the deployed package checksum not matching the expected one from mdmclient.

No big deal right? **WRONG**

#### What followed next was mdmclient being completely broken.
Subsequent pushes/attempts to use InstallApplication resulted absolutely _nothing_ happening on the client device. In testing this, I found that _sometimes_ killing `storedownloadd` resulted in partial functionality of InstallApplication, but to truly fix this required a reboot of the machine. I found that also including the incorrect URL to the package also broke mdmclient.

To be frank, this is absolutely horrifying. Imagine accidentally deploying the wrong package or the wrong AppManifest.plist into production and all of your brand new macs failing to finish their DEP enrollment. Your users would have **zero** insight to the problem and you may not catch it until it's too late.

## So what can we do about it?
If you're reading this and testing SimpleMDM, please deliberately try to break mdmclient. If SimpleMDM does not support custom AppManifest.plist files, please ask them to add support for this feature so you can actively test/interact with mdmclient.

If you're reading this and use MicroMDM, you have the ability right now to use custom AppManifest.plist files. Please try this, break it and report issues in the #micromdm channel on Slack.

Once we have more visibility onto this issue, we can file/dupe radars with Apple and really get them to fix these issues.

## Working around InstallApplication
As I was breaking mdmclient and iterating on my design around chef/crypt/munki/sal/UX I realized I needed a tremendous amount of packages to be deployed on my machines and in a specific order. My package list continued to grow and the size of the package ballooned in size. I started down the path of what I like to call **monolithic packaging**. By this I mean that I was creating a single, signed distribution package that contained a mixture of sub-packages. After writing my blog posts I was somewhat worried that this would be the initial future of custom DEP: a step back in automation and a step back in modularity.

What are the limitations with this approach?
1. Monolithic. One change to one of the meta packages means re-building/re-deploying the entire package chain to your MDM.
2. Sub packages are run uniformly per install stage. This means that _all_ preinstall scripts from _all_ packages run first, then _all_ files are deployed from _all_ packages, followed finally by _all_ postinstall scripts from _all_packages. These are ran in order of the distribution.plist. As your design grows in scope, you could easily run into a race condition or have unintended consequences.
3. Sub packages could not be distribution packages. I was extremely lucky with Chef in that while it was a distribution package, it had a sub package that contained all of the installation logic. Other tools may not work this way and would require a full re-packaging. This could be a significant amount of extra work.
4. Network latency/download speeds become an issue the larger your package.
5. UX (User Experience) is sluggish. If you are deploying a single, large package, you must wait for it to download and then install _all_ files before you can begin to inform the user that you are running things on their machine (if say you are using a postinstall to trigger it).
6. mdmclient uses md5 for it's hash validation.
7. Screwing things up and breaking DEP world-wide for your company. :fire: :fire: :fire:

With these issues in mind, I decided to write a "Munki-lite" tool that would solve _all_ of these issues.

## InstallApplications
[InstallApplications](https://github.com/erikng/installapplications) is a LaunchDaemon, and python script that can be wrapped in a signed package (quite easily using munki-pkg). This allows you to _dynamically_ have a set of packages installed in the order of your choosing.

Here is the workflow I envision being used:
1. Create the packages you need for your custom DEP workflow.
2. Get all of their SHA256 hashes (`/usr/bin/shasum -a 256 /path/to/pkg`)
3. Upload these files to a **https** repository. This could be Amazon, Google or even hosted on your own domain.
4. Create a JSON file that looks like the below example.
```json
{
  "prestage": [
    {
      "file": "/private/tmp/installapplications/prestage.pkg",
      "url": "https://domain.tld/prestage.pkg",
      "hash": "sha256 hash"
    }
  ],
  "stage1": [
    {
      "file": "/private/tmp/installapplications/stage1.pkg",
      "url": "https://domain.tld/stage1.pkg",
      "hash": "sha256 hash"
    }
  ],
  "stage2": [
    {
      "file": "/private/tmp/installapplications/stage2.pkg",
      "url": "https://domain.tld/stage2.pkg",
      "hash": "sha256 hash"
    }
  ]
}
```
5. Upload the json file to either the same https repository or another one if needed.
6. Modify the [jsonurl](https://github.com/erikng/installapplications/blob/master/payload/Library/LaunchDaemons/com.erikng.installapplications.plist#L12) in the LaunchDaemon to point to the uploaded JSON file.
7. Create your signed InstallApplications package and deploy this to your MDM vendor for DEP usage.

When a machine is enrolled in DEP and InstallApplications is installed it will securely download, validate and install all of the packages you need. If you ever need to make a change to your deployment, you just need to upload your new packages and json file. While the json file is hardcoded, your package url's could change (say for instance if a new munki version is out.)

Put simply, unless you need to update InstallApplications, you never need to touch your MDM again to deploy new packages. Of the seven issues above, InstallApplications solves six of them, but one could argue that InstallApplications is still initially downloaded/validated via md5. As for breaking DEP - well you could still break DEP, but you could certainly fix it faster.

#### A note about 10.12.4
macOS Sierra 10.12.4 brings a welcome change to InstallApplication in that MDM vendors can now begin to install applications **during** the SetupAssistant! While technically this was around prior to 10.12.4, there was a bug that prevented this from actually working.

## What is PreStage, Stage 1 and Stage2
While this tool was specifically written with 10.12.4 in mind, technically any of the stages can be skipped by simply not having an entry for them in the JSON file.

The `PreStage` section should be used for tools that either don't have a UI or can easily be installed during the SetupAssistant process. Such examples could be [Outset](https://github.com/chilcote/outset), [Yo](https://github.com/sheagcraig/yo) or even configuration management tools like [Chef](https://github.com/chef/chef).

The `Stage1` section should be used for bootstrapping UI tools that need to wait for the user. InstallApplications will download the first package and then wait until the user session has actually started. This might be a script that triggers your UI on behalf of the user.

The `Stage2` section should be used for any other tools that don't require UI or just tools that installer later in your provisioning process. Some of you may never even use Stage2.

#### A note on UX speed
Utilizing the combination of 10.12.4 and PreStage/Stage1 results in a **near instantaneous UI prompt for the user**. Many macadmins have had difficulty with the amount of time it takes for a user to be notified (I continually see this issue with jamf) that DEP is actively running/configuring their machine and I think this will be a huge breakthrough for the community surrounding this issue.


## Monolithic DEP packaging is dead - long live monolithic DEP packaging
I think it's safe to say that monolithic DEP packaging began and will end with me alone and this is a _good_ thing. If you are testing DEP, try this tool out. I think you'll be happy with the results.


## Table Of Contents
* Do not remove this line (it will not be displayed)
{:toc}
