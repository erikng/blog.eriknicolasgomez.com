---
layout: post
author: Erik Gomez
title: "Automated CloudFront invalidation rules"
description: "Defining rules for tools like imagr, munki and reposado"
tags: [amazon, aws, automation, CloudFront, Imagr, Munki, Reposado]
published: true
date: 2018-01-25 13:00:00
comments: true
---

With Apple releasing their [deprecation notice for macOS Server functionality](https://support.apple.com/en-us/HT208312), several macadmins have been asking what they can do to continue to manage services like Imagr, Munki and Reposado.

For some time, my recommendation has been [CloudFront](https://aws.amazon.com/cloudfront/) and while this post will not get into _how_ or _why_ to configure CloudFront, it will show you how to create automated invalidation rules to further refine your deployments.

## Why use invalidation rules?
Imagr, Munki and Reposado all deal with flat files and plists to define their behavior. Quite often you will change the content, but you will almost never change the _filenames_. With CloudFront this is problematic as your users will [continue to download cached objects](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/Invalidation.html) vs your newly updated ones.

While you can certainly script this, Amazon has specific rules with how many times you are allowed to invalidate using the API.

> Invalidation Limits
> If you're invalidating objects individually, you can have invalidation requests for up to 3,000 objects per distribution in progress at one time. This can be one invalidation request for up to 3,000 objects, up to 3,000 requests for one object each, or any other combination that doesn't exceed 3,000 objects. For example, you can submit 30 invalidation requests that invalidate 100 objects each. As long as all 30 invalidation requests are still in progress, you can't submit any more invalidation requests. If you exceed the limit, CloudFront returns an error message.

> If you're using the * wildcard, you can have requests for up to 15 invalidation paths in progress at one time. You can also have invalidation requests for up to 3,000 individual objects per distribution in progress at the same time; the limit on wildcard invalidation requests is independent of the limit on invalidating objects individually.

>Paying for Object Invalidation
> **The first 1,000 invalidation paths that you submit per month are free; you pay for each invalidation path over 1,000 in a month.** An invalidation path can be for a single object (such as /images/logo.jpg) or for multiple objects (such as /images/* ). A path that includes the * wildcard counts as one path even if it causes CloudFront to invalidate thousands of objects.

> This limit of 1000 invalidation paths per month applies to the total number of invalidation paths across all of the distributions that you create with one AWS account. For example, if you use the AWS account john@example.com to create three distributions, and you submit 600 invalidation paths for each distribution in a given month (for a total of 1,800 invalidation paths), AWS will charge you for 800 invalidation paths in that month. For specific information about invalidation pricing, see Amazon CloudFront Pricing. For more information about invalidation paths, see Invalidation paths.

While 1,000 invalidations does seem quite high, imagine each time you update your munki catalogs, manifests and pkginfo files. You could quickly eat up these invalidations in only a few days.

## How to define an invalidation rule.
Defining invalidation rules are incredibly simple.

In your AWS console, go to CloudFront Distributions -> your CloudFront instance -> Behaviors. You will more than likely see a default path pattern of * - leave this alone.

Go to `Create Behavior`. The most important settings are highlighted below and are as follows:

* Path pattern
* Viewer Protocol Policy
* Object Caching / Custom
* Minimum TTL
* Maximum TTL
* Default TTL

### Path pattern
The path pattern is fairly obvious but I will explain with an example munki repo. Bolded items are typically where the plists will reside.

* munki_repo
* **./catalogs**
* ./client_resources
* **./icons**
* **./manifests**
* ./pkgs
* **./pkgsinfo**

If you wanted to automatically invalidate your catalogs, manifests and pkginfo files, you would simply create three invalidation rules with the following path patterns:

* /catalogs/*
* /manifests/*
* /pkgsinfo/* (optional as this has no user impact)

With recent versions of munki, there is now a `_icon_hashes.plist` for all of your icons. When you run `makecatalogs` this file is updated if any new icons exist, so you will probably want to create a rule for this with the following pattern:

* /icons/_icon_hashes.plist

Finally, you may want to create an invalidation rule for your client resources files. While these don't change often, it could throw you for a loop when you make a change and don't see it on appear.

* /client_resources/*

### Viewer Protocol Policy
This one is simple - _HTTPS Only_. Don't allow http, ever, even for testing.

Just don't.

### Object Caching
Here is where you will want to use the Customize option. Depending on how aggressive you want to be, you will want to do the following:

* Set Minimum TTL to 0:
* Set Maximum/Default TTL to whatever value you want (value is in seconds)

### Example
In the following image, you will see a full invalidation rule for _all_ munki catalogs, with a highly aggressive invalidation of **two minutes (120 seconds)**. This will mean from the time you do a `s3 sync` to your CloudFront instance, in two minutes, your users will be able to see new packages in Managed Software Center.

![CloudFront create behavior](/images/2018/01/cloudfront_create_behavior.png)

### Ordering your rules
After you have created all of the rules you want, you want to make sure they are _above_ your default rule.

![CloudFront behaviors](/images/2018/01/cloudfront_behaviors.png)

## ...and you're done
No more manual invalidations, aws cli invalidations and no potential for paying Amazon more money. :)

## Table Of Contents
* Do not remove this line (it will not be displayed)
{:toc}
