---
layout: post
author: Erik Gomez
title: "Configuring LogClientIdentity for Caching Server"
description: "Not an integer, not a string, but a boolean."
tags: [macOS, Caching, Server]
published: true
date: 2017-02-18 16:30:00
comments: true
image: /images/2017/02/cachingsettings.png
---

[In my last post](/2017/01/07/Cacher-3-0/) I talked about Cacher 3.0. In the past month and a half I have been extraordinarily busy and unfortunately had some outstanding issues on my GitHub. After working on the issues, I realized that documentation on LogClientIdentity is very poor.

Throughout the internet we have documentation that is either incorrect or out-of-date:

- [jamf-nation](https://www.jamf.com/jamf-nation/discussions/17335/os-x-caching-server#responseChild137839)
- [Sashay Issues](https://github.com/macadmins/sashay/issues/1)
- [Sashay Master](https://github.com/macadmins/sashay)
- [Apple Discussions](https://discussions.apple.com/thread/7266083?start=0&tstart=0)
- [HCS](https://www.hcsonline.com/PDF/HCS_Caching_Services.pdf)
- [Reddit](https://www.reddit.com/r/apple/comments/3trx2s/if_you_work_somewhere_that_has_a_lot_of_apple)
- [My own blog!](/2015/05/19/re-introducing-cacher/)

## The proper command
According to [Apple's official Server documentation](https://help.apple.com/serverapp/mac/5.2/#/apd5E1AD52E-012B-4A41-8F21-8E9EDA56583A), LogClientIdentity is a **BOOLEAN** value.

> **LogClientIdentity** - false - Determines whether or not the server should log the IP address and port number of the client requesting each asset.

Let's look at the differences and compare our results from `/Library/Server/Caching/Config/Config.plist`

```xml
/Applications/Server.app/Contents/ServerRoot/usr/sbin/serveradmin settings caching:LogClientIdentity = 1

<key>LogClientIdentity</key>
<integer>1</integer>
```

In this case it is sending a value of **1** send an integer value and _not_ a boolean.

```xml
/Applications/Server.app/Contents/ServerRoot/usr/sbin/serveradmin settings caching:LogClientIdentity = true

<key>LogClientIdentity</key>
<string>true</string>
```

In this case it is sending a value of **true** however it is a string and _not_ a boolean.

```xml
/Applications/Server.app/Contents/ServerRoot/usr/sbin/serveradmin settings caching:LogClientIdentity = True

<key>LogClientIdentity</key>
<string>True</string>
```

In this case it is sending a value of **True** however it is a string and _not_ a boolean.

## /Applications/Server.app/Contents/ServerRoot/usr/sbin/serveradmin settings caching:LogClientIdentity = yes
```xml
/Applications/Server.app/Contents/ServerRoot/usr/sbin/serveradmin settings caching:LogClientIdentity = yes

<key>LogClientIdentity</key>
<true/>
```

This value returns a **boolean**.

If we compare this result with another key that comes on _all_ default Caching Server installations (LocalSubnetsOnly), it is clear that, yes, is the correct syntax.

```xml
<key>LocalSubnetsOnly</key>
<true/>
```

We can run `/Applications/Server.app/Contents/ServerRoot/usr/sbin/serveradmin settings caching` and also validate the configuration.

```
/Applications/Server.app/Contents/ServerRoot/usr/sbin/serveradmin settings caching
caching:ServerRoot = "/Library/Server"
caching:LogClientIdentity = yes
caching:LocalSubnetsOnly = yes
```

![LogClientIdentity Hero](/images/2017/02/cachingsettings.png "LogClientIdentity")

## Cacher plug

As of [Cacher 3.0.3](https://github.com/erikng/Cacher/releases/tag/3.0.3), Cacher will now detect your LogClientIdentity settings and warn if they are incorrectly configured. Whether the value is missing or incorrectly set, you can correct this by running `sudo cacher.py --configureserver`

Also, if you attempt to run Cacher on logs without LogClientIdentity, it will now warn you:
> WARNING: Found %s logs that did not contain the client identity. These logs have been dropped and are not counted in the statistics. More than likely, LogClientIdentity was incorrectly set or not configured on this date.

Example Cacher runs:
```
./cacher.py
LogClientIdentity is not set

/Applications/Server.app/Contents/ServerRoot/usr/sbin/serveradmin settings caching:LogClientIdentity = true
./cacher.py
LogClientIdentity is incorrectly set to: true - Type: str

/Applications/Server.app/Contents/ServerRoot/usr/sbin/serveradmin settings caching:LogClientIdentity = True
./cacher.py
LogClientIdentity is incorrectly set to: True - Type: str

/Applications/Server.app/Contents/ServerRoot/usr/sbin/serveradmin settings caching:LogClientIdentity = 1
./cacher.py
LogClientIdentity is incorrectly set to: 1 - Type: int

/Applications/Server.app/Contents/ServerRoot/usr/sbin/serveradmin settings caching:LogClientIdentity = yes
./cacher.py
Cacher has retrieved the following stats for 2017-02-18:
```

## Table Of Contents
* Do not remove this line (it will not be displayed)
{:toc}
