---
layout: post
title: "Advanced Logging for Apple Configurator 2"
description: "A short post on enabling debug logging with Apple Configurator 2."
tags: [Apple Configurator 2, logging, macOS, OS X]
comments: true
---

While I don't have much time to write a thorough post on how I found this information, while playing with Hopper I found out that you can have some incredibly verbose logs for Apple Configurator 2.

```bash
defaults write ~/Library/Containers/com.apple.configurator.ui/Data/Library/Preferences/com.apple.configurator.ui.plist ACULogLevel -string ALL
```

While I still enjoy iOS Logger, these logs contain advanced logging information outside of the device itself.

If you find the logs too verbose run the following command.

```bash
defaults delete ~/Library/Containers/com.apple.configurator.ui/Data/Library/Preferences/com.apple.configurator.ui.plist ACULogLevel
```

Enjoy.