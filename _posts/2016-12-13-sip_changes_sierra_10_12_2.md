---
layout: post
title: "System Integrity Protection (SIP) changes in macOS Sierra 10.12.2"
description: "Welcome changes to SIP in 10.12.2."
tags: [SIP, System Integrity Protection, macOS, Sierra]
comments: true
---

With the release of macOS Sierra 10.12.2, Apple has made one welcome change to System Integrity Protection (SIP): you can now re-enable the feature without being booted into the Recovery partition!
## How To
To re-enable SIP, you run the following command:

```bash
/usr/bin/csrutil clear
```

Please note that you will need to run this as _root_. To see if the command was successful, run `nvram -p` and look for `csr-active-config`. If the key does not exist, then SIP has been re-enabled.

Example:

```bash
csrutil status
System Integrity Protection status: disabled.

nvram -p
csr-active-config   w%00%00%00

sudo csrutil clear
Password:
Successfully cleared System Integrity Protection. Please restart the machine for the changes to take effect.

csrutil status
System Integrity Protection status: disabled.

nvram -p
```

## Enhancement
I have asked for an enhancement to mimic the behavior of `fdesetup status`

Hopefully Apple can have `csrutil status` show something like this:

System Integrity Protection is Off, but will be enabled after the next restart.