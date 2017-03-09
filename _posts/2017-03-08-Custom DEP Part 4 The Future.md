---
layout: post
author: Erik Gomez
title: "Custom DEP - Part 4: The Future"
description: "We are living in exciting times."
tags: [macOS, DEP, MDM, EMM, AirWatch, SimpleMDM]
published: true
date: 2017-03-08 17:45:00
comments: true
image: /images/2017/03/dep_installapplication_Custom.png
---

For the past five months, I have been working tirelessly on this feature. I must commend this MDM vendor as they are legitimately excited for this new future. I cannot wait for others to try this out and I genuinely hope it will help with their future deployments of macOS.

Chef, Munki, Puppet, Simian, etc (and the companies using these tools) all stand to benefit from this feature. It is tremendously exciting.

## Uncertainty in certainty
As I stated in [Part I](/2017/03/08/Custom-DEP-Part-1-An-Introduction/) of this series, we are in a very unique time. With WWDC 2017 right around the corner, we still have very little idea on what Apple will announce and most importantly, deprecate. It definitely seems like the final nails on the coffin for the following:
- Software Update Server
- Imaging (RIP Imagr, DeployStudio, Casper Imaging, etc)

Where things get fuzzy is NetInstall/NetRestore. NetBoot has already been pushed to the "Advanced" section of the Server application, so Apple is definitely hinting that it's days might be numbered.

## What's being deprecated next year?

Could /Library/LaunchDaemons be next? Possibly, but I don't think that time is now. If and when that time comes, as Apple engineers, we will adapt and work on the next methodologies for managing Apple products.

Regardless, until that time comes we now have a **major** MDM vendor that will be announcing support for custom `InstallApplication` very soon. Will other MDM vendors join and help colloborate with open source tools?

## Yes

It's clear that the answer is a resounding yes. In the time I have been working on this feature/blog posts, [SimpleMDM](https://simplemdm.com/2017/03/07/deploy-munki-apple-dep-mdm/) announced a similar feature. While I do not have the details on their integration, it is clear that there is a clear desire, both from MDM vendors and macadmins to use this feature.

## A giant shout-out to the Apple open source community.
If it wasn't for the peers that I deeply respect and have documented (in great) detail, how to utilize InstallApplication, none of this would be possible. Here are a few of the people and posts that started this:
- [MDM-azing - setting up your own MDM server](http://enterprisemac.bruienne.com/2015/06/06/mdm-azing-setting-up-your-own-mdm-server/)
- [Installing OS X PKGs using an MDM service](http://enterprisemac.bruienne.com/2015/11/17/installing-os-x-pkgs-using-an-mdm-service/)
- [MDM from scratch](https://groob.io/posts/mdm-experiments/)
- [Munkiing around with DEP](https://groob.io/posts/dep-micromdm-munki/)
- [Jesse Petterson](https://www.youtube.com/watch?v=0rdQkP740Co)
- [Countless others](https://micromdm.io/community/)

## To all macadmins
As [Nick McSpadden](https://twitter.com/MrNickMcSpadden) would so eloquently say: **We have work to do!**

I hope you have enjoyed this series and if you have any questions, you can reach out to me on Slack.

#### There will be more blog posts soon - stay tuned.

## Table Of Contents
* Do not remove this line (it will not be displayed)
{:toc}
