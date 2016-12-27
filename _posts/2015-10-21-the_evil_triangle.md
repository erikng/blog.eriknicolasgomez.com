---
layout: post
title: "The Evil Triangle: El Capitan, SUS and Caching"
description: "What happens when engineers code in a bubble."
tags: [El Capitan, SUS, Caching, Server, macOS, OS X]
comments: true
---

Update: As of December 8th, 2015, this issue is now resolved.
In order to have this fully corrected you must have:

- El Capitan 10.11.2 for clients
- Server 5.0.15 for Caching Server

Since the [El Capitan betas](https://forums.developer.apple.com/thread/16231), there has been a significant issue with software updates. Unfortunately as of 10.11.1, this issue is still not resolved and as I no longer have a resolution in sight, I figured it would be best to publicly document the issue.

In order to see this issue, you must have the following configuration:

- Apple SUS or Reposado
- Caching Server
- El Capitan client pointing to your SUS server.

## Technical Overview
During the betas, it was quite clear that Apple was adding more client features to the Caching Service. Apple announced [Personal iCloud Data](https://assetcache.io/blog/caching-server-local-icloud.html) and Apple Configurator 2, which _finally_ had support for Caching Servers. One unannounced feature though was a change to `softwareupdated`.

Let's look at how everything falls apart

### El Capitan 10.11.0

10.11.0 Client Machine Terminal

```ruby
softwareupdate -d -v -a
Software Update Tool
Copyright 2002-2015 Apple Inc.

Finding available software

Downloading Example Package
```

10.11.0 Client Machine install.log

```ruby
softwareupdated: softwareupdated: Catalog URL changed (from "https://swscan.apple.com/content/catalogs/others/index-10.11-10.11-10.10-10.9-mountainlion-lion-snowleopard-leopard.merged-1.sucatalog.gz" to "http://example.sus.com/index.sucatalog"). Resetting state.
softwareupdated: SUScan: Using catalog http://example.sus.com/index.sucatalog
softwareupdated: 1 update found:
zzzzexample | Example Package
softwareupdated: ContentLocator: Modified URL is: http://example.caching.server:port/example.pkg?source=example.sus.com
softwareupdated: Finished downloading package example.pkg to file:///var/folders/zz/zzyx/C/com.apple.SoftwareUpdate/CFNetworkDownload.tmp (error (null)) from peer: example.caching.server
softwareupdated: zzzzexample: Failed post-download size check for package "example.pkg": expected 101010101, got 0
```

As you can see, the following takes place:

1. softwareupdate is ran and noticed that either `com.apple.SoftwareUpdate.plist` has been modified or a `profile` has been applied to re-configure the Software Update Catalog.
2. A sub process SUScan begins to look for updates and finds 1 available update.
3. A sub process called `ContentLocator` (client name for Caching Service, not to be confused with ContentLocatorService) finds an available caching server and redirects softwareupdate to use it.
4. softwareupdate attempts to download the package, but for some undetermined reason it fails (more on this soon) and downloads an invalid .pkg file with a 0kb file size.
5. At this point, softwareupdate is completely confused and hangs indefinitely until its process is killed.

### Caching Server 5.0.4 and below

Caching Server Debug.log

```ruby
Request from example.client:port [Software Update (unknown version) CFNetwork/760.1.2 Darwin/15.0.0 (x86_64)] 
for http://example.caching.server:port/example.pkg?source=example.sus.com denied because the source is not 
whitelisted.
```

From the looks of it, Apple has a hardcoded list of domains that are whitelisted and all other domains simply fail to register. As the internal SUS is not on this list, it does not trust it.

### Apple's Bandaid fix for 10.11.1 and Server 5.0.15
Today Apple released 10.11.1 and Server 5.0.15. I immediately updated and began testing. While _some_ work has been done, the overall issue still remains.

10.11.1 Client Machine Terminal

```ruby
softwareupdate -d -v -a
Software Update Tool
Copyright 2002-2015 Apple Inc.

Finding available software

Downloading Example Package
Error downloading Example Package Update: The network connection was lost.
Done.

Error downloading updates.
```

10.11.1 Client Machine install.log

```ruby
softwareupdated: softwareupdated: Catalog URL changed (from "https://swscan.apple.com/content/catalogs/others/index-10.11-10.11-10.10-10.9-mountainlion-lion-snowleopard-leopard.merged-1.sucatalog.gz" to "http://example.sus.com/index.sucatalog"). Resetting state.
softwareupdated: SUScan: Using catalog http://example.sus.com/index.sucatalog
softwareupdated: 1 update found:
zzzzexample | Example Package
softwareupdated: ContentLocator: Modified URL is: http://example.caching.server:port/example.pkg?source=example.sus.com
softwareupdated: No more tasks - invalidating session now
softwareupdated: SoftwareUpdate: error download of zzzzexmaple: Error Domain=NSURLErrorDomain Code=-1005 "The network connection was lost." UserInfo={NSUnderlyingError=0x7fe12f0ade10 {Error Domain=kCFErrorDomainCFNetwork Code=-1005 "(null)" UserInfo={_kCFStreamErrorCodeKey=-4, _kCFStreamErrorDomainKey=4}}, NSErrorFailingURLStringKey=http://example.caching.server:port/example.pkg?source=example.sus.com, NSErrorFailingURLKey=http://example.caching.server:port/example.pkg?source=example.sus.com, _kCFStreamErrorDomainKey=4, _kCFStreamErrorCodeKey=-4, NSLocalizedDescription=The network connection was lost.}
softwareupdated: Stopping transaction with ID [0x3]
softwareupdated: SoftwareUpdate: Removed foreground transaction [0x3]
```

So what's changed?

Well it looks like Apple is simply severing the connection and preventing the hang. While it fixes some issues, the major issue still remains: Clients cannot receive updates.

### Caching Server 5.0.15

Caching Server Debug.log

```ruby
Request from example.client:port [Software Update (unknown version) CFNetwork/760.1.2 Darwin/15.0.0 (x86_64)] 
for http://example.caching.server:port/example.pkg?source=example.sus.com aborted because the source is not 
whitelisted.
```

As you can see, while the domain is still not whitelisted, it sends an abort rather than a deny and the client has been updated to understand the difference.

Awesome fix Apple!

On top of this, I discovered the Darwin version was not updated for the second year a row. At least they are consistent at being inconsistent.

## Houston, we have a lot of problems
Below is a running list of items that fail to work and the configurations that cause them.

JAMF Casper customers may also be impacted by this issue, but to date I have not worked with another administrator that is using this combination.

### El Capitan 10.11.0 Client / Caching Server 5.0.4 and lower / Apple SUS or Reposado
- Mac App Store Updates
  - Examples:
    - iTunes
    - Document Camera Raw Compatibility
    - 10.11.1 Delta Update
    - 10.11.2 Combo Update
    - Printer Driver Installations
    - Legacy Java Installations
- Xcode Command Line Tools installations
  - Example: typing `git clone` in Terminal
- Munki
  - Bootstrapping and attempting to download Apple updates such as iTunes. Munki will indefinitely hang until the bootstrapping process is terminated.
  - If Munki is ran via `--auto` mode (Launch Daemon or manual) and discovers an Apple update, Munki will indefinitely hang. The user will be unable to use Managed Software Center and all subsequent attempts to run `--auto` will also fail until all hung processes are killed or the machine is rebooted.

### El Capitan 10.11.1 Client / Caching Server 5.0.4 and lower / Apple SUS or Reposado
Sadly, with this configuration there are 0 issues resolved.

**_All_** 10.11.0 client issues remain.

### El Capitan 10.11.1 / Caching Server 5.0.15 / Apple SUS or Reposado
- Mac App Store Updates
  - Examples:
    - iTunes
    - Document Camera Raw Compatibility
    - 10.11.2 Delta Update
    - Printer Driver Installations
    - Legacy Java Installations
- Xcode Command Line Tools installations
  - Example: typing `git clone` in Terminal
- Munki
  - Bootstrapping and attempting to download Apple updates such as iTunes. Munki will indefinitely loop until the bootstrapping process is terminated.

## Workarounds
While there are several workarounds available, I don't find any of them particularly ideal. Each organization should weigh the pros/cons and make a determination as to the best course of action.

All of these workarounds will work instantly for the Mac App Store and softwareupdated, however if Munki is hung, all munki processes will need to be killed or the machine will need to be rebooted.

### Disable Caching Server
- Pros
  - Easiest solution as it requires no reconfiguration of client machines
  - Resolves _all_ documented issues
- Cons
  - Increased bandwidth for iOS/OS X devices

### Point El Capitan clients to Apple's Software Update Servers
- Pros
  - Resolves _all_ documented issues
- Cons
  - Loss of apple software update scheduling
  - Increased bandwidth for OS X devices
  - In some cases, this may not work
    - Example of Apple's own server being blocked: `http://example.caching.server:port/example.pkg?source=osxapps.itunes.apple.com denied because the source is not whitelisted.`

### Do not approve El Capitan Software Updates
- Pros
  - Fixes Munki Bootstrap issues
  - Easy with Reposado
- Cons
  - Apple SUS users may lose updates for other Operating Systems
  - Items such as Java, Xcode CLI and Printer Drivers will fail to install for users.

### Downgrade to Yosemite
- Pros
  - Resolves _all_ documented issues
  - Does not require disabling other enterprise products
- Cons
  - Cannot downgrade October 2015 iMac refresh
  - Somewhat less secure than El Capitan (SIP, Kernel protections)

Thankfully, Apple has also issued `Security Update 2015-007` which should resolve some (but not all) of the security issues with Yosemite.

## So now what?
Unfortunately, I no longer have an ETA for when this will be resolved. All signs point to 10.11.2, but without a current beta to test, I cannot confirm that the behavior is resolved.

If you are running into this issue and have a Sales Engineer, please reach out to them with impact data. The more pressure we can place on Apple, the sooner this issue can be put to rest.