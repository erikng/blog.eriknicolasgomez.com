---
layout: post
author: Erik Gomez
title: "Advanced munki sharding"
description: "Or perhaps cautiously deploying High Sierra"
tags: [macOS, Munki, shard, sharding, High Sierra]
published: true
date: 2017-12-19 10:00:00
comments: true
---

For various reasons, my company has decided to standardize on macOS High Sierra 10.13.2. But given all of the latest issues we and others have seen with High Sierra, we wanted to take a somewhat conservative deployment strategy:

- Ability to target specific percentages of our fleet at an exact date and time
- Ability to target these specific percantages with _different_ force install dates
- Have the least amount of duplicated pkginfo/catalogs files
- No munki warnings
- Ability to pull the plug at any time (either force install date or deployment altogether)

While it sounds simple, I ultimately designed three different strategies before ultimately figuring out the best course of action.

## Shard outline

![shard outline](/images/2017/12/shard_example.png)

The above is an example deployment for January, where each shard percentage would be given **eight** days to install the update.

## Duplicating the pkginfo file for multiple force_install_after_date
Let's look at a normal 10.13.2 startosinstall upgrade directly imported from munki

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>RestartAction</key>
	<string>RequireRestart</string>
	<key>_metadata</key>
	<key>apple_item</key>
	<true/>
	<key>autoremove</key>
	<false/>
	<key>catalogs</key>
	<array>
		<string>production</string>
	</array>
	<key>category</key>
	<string>Upgrades</string>
	<key>description</key>
	<string>This package upgrades your computer from your current operating system to macOS High Sierra.</string>
	<key>developer</key>
	<string>Apple</string>
	<key>display_name</key>
	<string>macOS High Sierra</string>
	<key>installed_size</key>
	<integer>9227469</integer>
	<key>installer_item_hash</key>
	<string>90cc87e58e609939c13429857f3201270466e499c8f2f73b8aab0e172f1fcfc6</string>
	<key>installer_item_location</key>
	<string>Install macOS High Sierra-10.13.2.dmg</string>
	<key>installer_item_size</key>
	<integer>5078285</integer>
	<key>installer_type</key>
	<string>startosinstall</string>
	<key>minimum_munki_version</key>
	<string>3.0.0.3211</string>
	<key>minimum_os_version</key>
	<string>10.8</string>
	<key>name</key>
	<string>macOSHighSierra</string>
	<key>unattended_install</key>
	<false/>
	<key>unattended_uninstall</key>
	<false/>
	<key>uninstallable</key>
	<false/>
	<key>version</key>
	<string>10.13.2</string>
</dict>
</plist>
```

In order for us to have multiple `force_install_after_date` munki packages, we _have_ to duplicate the pkginfo files. Ultimately we just need to change one key and add our specific date.

```xml
<key>name</key>
<string>macOSHighSierra_shard1</string>
<key>force_install_after_date</key>
<date>2018-01-08T00:00:00Z</date>
```

```xml
<key>name</key>
<string>macOSHighSierra_shard2</string>
<key>force_install_after_date</key>
<date>2018-01-10T00:00:00Z</date>
```

```xml
<key>name</key>
<string>macOSHighSierra_shard3</string>
<key>force_install_after_date</key>
<date>2018-01-15T00:00:00Z</date>
```

```xml
<key>name</key>
<string>macOSHighSierra_shard4</string>
<key>force_install_after_date</key>
<date>2018-01-17T00:00:00Z</date>
```

```xml
<key>name</key>
<string>macOSHighSierra_shard5</string>
<key>force_install_after_date</key>
<date>2018-01-22T00:00:00Z</date>
```

So now that we have five different pkginfo files for each shard, we can move onto the final step.

## Conditional manifests
[Munki Conditional Items](https://github.com/munki/munki/wiki/Conditional-Items) are extremely powerful and when used in manifest, they allow us to only make items available if all conditions are met.

While you can use conditional items in pkginfo files (or installcheck scripts), you must be careful to not create logic that will create munki warnings/errors. While [others](https://grahamgilbert.com/blog/2015/11/23/releasing-changes-with-sharding/) have good ideas for how to solve this, I think using it in a manifest is better approach for major upgrades.

In order for us to use sharding with munki, we need to deploy a conditional item. While I won't explicitly document how to do this in this post, my suggestion is to use the [munki-facts](https://github.com/munki/munki-facts).

Deploying [munki-facts](https://github.com/munki/munki-facts) in conjunction with this [shard fact](https://github.com/chilcote/unearth/blob/master/artifacts/shard.py) will give you everything you need.

## Creating the conditional manifest with a start date and shard.
Now that you have your shard munki condition and pkginfo files, you are halfway there - we just need a way to target these shards and define a time.

Munki has a built in condition already for casting a date, so let's use this as a starting point.

```xml
<key>conditional_items</key>
<array>
  <dict>
    <key>condition</key>
    <string>date &gt; CAST("2018-01-01T00:00:00Z", "NSDate")</string>
  </dict>
</array>
```

Since we have already deployed our shard condition, we can also use this as well, and provide a less than/greater than range.

```xml
<key>conditional_items</key>
<array>
  <dict>
    <key>condition</key>
    <string>shard &gt;= 1 AND shard &lt;= 20</string>
  </dict>
</array>
```

Notice that we are using an `AND` operator to combine conditions. This allows us to provide a shard range.

As munki allows an unlimited number of nested conditionals, we can use the two (technically three) conditions together.

```xml
<key>conditional_items</key>
<array>
  <dict>
    <key>condition</key>
    <string>date &gt; CAST("2018-01-01T00:00:00Z", "NSDate")</string>
    <key>conditional_items</key>
    <array>
      <dict>
        <key>condition</key>
        <string>shard &gt;= 1 AND shard &lt;= 20</string>
        <key>managed_installs</key>
        <array>
          <string>macOSHighSierra_shard1</string>
        </array>
      </dict>
    </array>
  </dict>
</array>
```

While we technically could use another `AND` operator above and combine it, I ultimately found that harder to read.

## Putting it all together

And with that, we can now do the following:
- Five shards containing 20% of the total deployment
- Each shard starts at a specific date, allowing us to not put our network in danger, or in the event of a massive upgrade failure, delay/remove the deployment altogether
- Each shard has it's own force_install_after_date, giving our users enough time to get all notifications
- A limited amount of pkginfo files (five), and a single manifest, reducing munki complexity

Below is the full example. Hope you enjoy.

```xml
<key>conditional_items</key>
<array>
  <dict>
    <key>condition</key>
    <string>date &gt; CAST("2018-01-01T00:00:00Z", "NSDate")</string>
    <key>conditional_items</key>
    <array>
      <dict>
        <key>condition</key>
        <string>shard &gt;= 1 AND shard &lt;= 20</string>
        <key>managed_installs</key>
        <array>
          <string>macOSHighSierra_shard1</string>
        </array>
      </dict>
    </array>
  </dict>
  <dict>
    <key>condition</key>
    <string>date &gt; CAST("2018-01-03T00:00:00Z", "NSDate")</string>
    <key>conditional_items</key>
    <array>
      <dict>
        <key>condition</key>
        <string>shard &gt;= 21 AND shard &lt;= 40</string>
        <key>managed_installs</key>
        <array>
          <string>macOSHighSierra_shard2</string>
        </array>
      </dict>
    </array>
  </dict>
  <dict>
    <key>condition</key>
    <string>date &gt; CAST("2018-01-08T00:00:00Z", "NSDate")</string>
    <key>conditional_items</key>
    <array>
      <dict>
        <key>condition</key>
        <string>shard &gt;= 41 AND shard &lt;= 60</string>
        <key>managed_installs</key>
        <array>
          <string>macOSHighSierra_shard3</string>
        </array>
      </dict>
    </array>
  </dict>
  <dict>
    <key>condition</key>
    <string>date &gt; CAST("2018-01-10T00:00:00Z", "NSDate")</string>
    <key>conditional_items</key>
    <array>
      <dict>
        <key>condition</key>
        <string>shard &gt;= 81 AND shard &lt;= 80</string>
        <key>managed_installs</key>
        <array>
          <string>macOSHighSierra_shard4</string>
        </array>
      </dict>
    </array>
  </dict>
  <dict>
    <key>condition</key>
    <string>date &gt; CAST("2018-01-15T00:00:00Z", "NSDate")</string>
    <key>conditional_items</key>
    <array>
      <dict>
        <key>condition</key>
        <string>shard &gt;= 81</string>
        <key>managed_installs</key>
        <array>
          <string>macOSHighSierra_shard5</string>
        </array>
      </dict>
    </array>
  </dict>
</array>
```
## Table Of Contents
* Do not remove this line (it will not be displayed)
{:toc}
