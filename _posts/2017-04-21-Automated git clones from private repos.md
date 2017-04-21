---
layout: post
author: Erik Gomez
title: "Automated git clones from private repos"
description: "Fun with Partition ACLs on Sierra."
tags: [macOS, partitions, Sierra, git, automation]
published: true
date: 2017-04-21 16:00:00
comments: true
---

[My company](https://medium.com/@Pinterest_Engineering/introducing-texture-a-new-home-for-asyncdisplaykit-e7c003308f50) has recently taken over an open source project originally written by Facebook.

As part of this process, we wanted to also ensure that we had an automated virtual machine process that could quickly clone both private and public repositories from GitHub and setup our build process.

# Caching your git username/password
There are several ways to cache your git credentials, but most of them involved writing the username and password to an unencrypted file on disk. This was simply out of the question.

[GitHub](https://help.github.com/articles/caching-your-github-password-in-git/) has a document on how to use `osxkeychain helper` which is bundled with Xcode (`/Applications/Xcode.app/Contents/Developer/usr/libexec/git-core/git-credential-osxkeychain`)

While this is helpful, this requires you to initially run `git clone` and type your username and password. This approach cannot be automated.

## Reverse Engineering the process
If you follow the GitHub document, you will find out that in the end it creates an `Internet Password` item in the login keychain and it has an ACL pointing to the `osxkeychain helper` tool.

### Security command
After playing around with the helper tool, I finally settled on the following:

```bash
# Add Github account
/usr/bin/security add-internet-password \
-a "USERNAME" \
-s "github.com" \
-w "PASSWORD" \
-T /Applications/Xcode.app/Contents/Developer/usr/libexec/git-core/git-credential-osxkeychain \
-r "htps" \
login.keychain
```

#### Bugs
When originally testing this, I kept getting stuck on `http` when using the -r flag.

```bash
-r protocol     Specify protocol (optional four-character SecProtocolType, e.g. "http", "ftp ")
```

According to [Apple](https://developer.apple.com/reference/security/secprotocoltype) `https` was a valid protocol type, but when trying this, I received the following error:

`Error: four-character types must be exactly 4 characters long.`

My co-worker joked and said to type `htps` and sure enough... it worked.

#### Snags with Sierra
Unfortunately, while the keychain item looked exactly like the one made with `osxkeychain helper`, I kept receiving a popup when using git clone. After dumping the keychains I saw the issue:

```bash
credential-osxkeychain (OK)
    entry 3:
        authorizations (1): partition_id
        dont-require-password
        description: apple-tool:
        applications: <null>
```

As of Sierra, Apple added a new partition_id scheme that is honestly still undocumented after a year. You can find people complaining about it [on jamfnation](https://www.jamf.com/jamf-nation/discussions/22304/yet-another-keychain-security-command-line-tool-question), [apple discussions](https://discussions.apple.com/thread/7816301?start=0&tstart=0), [stackoverflow](http://stackoverflow.com/questions/39868578/security-codesign-in-sierra-keychain-ignores-access-control-settings-and-ui-p), [stackoverflow 2](http://stackoverflow.com/questions/41244635/codesign-in-sierra-security-set-key-partition-list-not-working), [openradar](https://openradar.appspot.com/28524119), [github](https://github.com/fastlane/fastlane/issues/6866), and [github2](https://github.com/lionheart/openradar-mirror/issues/16303)

Essentially, the partition_id needs to contain `apple-tool:, apple:` in the description.

After playing around with it for a while, this is what I found worked

```bash
/usr/bin/security set-internet-password-partition-list \
-l "github.com" \
-S "apple-tool:,apple:" \
-k "PASSWORD" \
login.keychain
```


# Putting it altogether

### Requirements
- Xcode
- Xcode Command Line tools
- Username and Password of the account (preferably in an encrypted data format)

### Example Code

```bash
# Add Github account credentials
/usr/bin/security add-internet-password \
-a "USERNAME" \
-s "github.com" \
-w "PASSWORD" \
-T /Applications/Xcode.app/Contents/Developer/usr/libexec/git-core/git-credential-osxkeychain \
-r "htps" \
login.keychain

# Set partition_id to prevent Keychain popups
/usr/bin/security set-internet-password-partition-list \
-l "github.com" \
-S "apple-tool:,apple:" \
-k "PASSWORD" \
login.keychain

# Set git to use the login keychain for credentials
/usr/bin/git config \
--global credential.helper osxkeychain

# git clone private repo requiring auth

git clone http://github.com/username/privaterepo.git

```




## Table Of Contents
* Do not remove this line (it will not be displayed)
{:toc}
