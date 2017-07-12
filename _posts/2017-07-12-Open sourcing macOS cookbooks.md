---
layout: post
author: Erik Gomez
title: "Open sourcing macOS cookbooks"
description: "Making chef better for everyone."
tags: [CPE, chef, cookbooks, OSS, Open Source]
published: true
date: 2017-07-12 01:00:00
comments: true
---

At my current employer, we have been moving from a traditional MDM to a hybrid approach, with a focus on dynamic configuration management and desired state using Chef as the primary mechanism.

While companies like Facebook have open sourced many core pieces for managing macOS devices at scale, there have been some components that still needed to be generalized. There is a tremendous amount of excitement around Chef and I am happy to see more and more companies and macadmins interest in Chef.

I am proud to announce that as of today, you will now find an additional set of chef cookbooks that you can use to manage your macOS devices.

# IT-CPE-Cookbooks
You can find the new cookbook repo I have open sourced [here](https://github.com/pinterest/it-cpe-cookbooks).

# Notes
Given that we modeled our management components around Facebook's design principals, most of these cookbooks will require some of their cookbooks.

Here are a few you should definitely look at:
- cpe_init
- cpe_profiles
- cpe_launchd
- cpe_utls

You can find Facebook's repo [here](https://github.com/facebook/IT-CPE/tree/master/chef)

## You can also find another blog post that I wrote at my current employer [here](https://medium.com/@Pinterest_Engineering/chef-new-open-source-it-cookbooks-for-macos-2fb2a23f9f7c)

## Table Of Contents
* Do not remove this line (it will not be displayed)
{:toc}
