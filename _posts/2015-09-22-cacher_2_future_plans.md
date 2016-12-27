---
layout: post
title: "Cacher 2 – Dropping Server 4 Support and Future Plans"
description: "Why didn't I write this in python?"
tags: [Cacher, Server, macOS, OS X]
comments: true
---

## Current State

If you're reading this, chances are you know about [Cacher](https://github.com/erikng/Cacher). If you haven't, please read my previous article detailing Cacher and how to set it up. You can find it [here](https://onemoreadmin.wordpress.com/2015/05/19/re-introducing-cacher/)

With the release of Apple's Server 5, iOS 9 and El Capitan, Cacher has been receiving some increased attention. To add to that, a few of my buddies have been tweeting about it (Thanks [Ben](https://macmule.com/) and [Arek](http://arekdreyer.com))

Today I'd like to announce Cacher "2.0"

Here are some of the changes:

- Support for Server 5
- Support for large caching servers who transfer terabytes of content
- Add logic for cases where Cacher does not understand and request relevant logs
- Removed support for Server 4.x
- Better mathematical equations for calculating bandwidth statistics

## The Future

When I first started writing this, it was only for internal use. It has gone from ~160 lines of bash to over 750 lines of terrible bashisms and comments. All of my new scripts are currently being written in Python and while bash is comfortable for me, Cacher is a perfect example of why I should be using Python.

Add to that, there are still a few [issues](https://github.com/erikng/Cacher/issues) I haven't resolved with Cacher 1 or 2.

[Allister Banks](http://aru-b.com) began work on [Sashay](https://github.com/macadmins/sashay) a few months ago and has been slowly adding features to it. Our current plans are (time permitting) to merge projects and ensure that people using either tool are not impacted. 

Enjoy Cacher 2 and be on the lookout for Cacher stats inside of Sashay.

