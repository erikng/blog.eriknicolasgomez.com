---
layout: post
author: Erik Gomez
title: "Custom DEP - Part 9: A practical example of InstallApplications, Crypt, DEPNotify and Munki"
description: "Pulling the custom DEP strings."
tags: [macOS, DEP, MDM, EMM, InstallApplication, InstallApplications, mdmclient, Crypt, DEPNotify, Munki]
published: true
date: 2017-12-18 12:00:00
comments: true
---

In Part 8, I outlined my thoughts on why [InstallApplications](https://github.com/erikng/installapplications) was written and why it's my preferred way to orchestrate custom DEP enrollments.

So great, you want to use it, but where do you begin?

# Assumptions made in this example
1. You do not skip the SetupAssistant user creation
2. Your MDM processes mdmclient package installations _immediately_ once enrolled into DEP
3. User is presented their GUI session after DEP enrollment/SetupAssistant
4. You're going to use DEPNotify for your user experience

# A small explanation on InstallApplications
There are a few components that are the most important in setting up InstallApplications:

- bootstrap.json
- LaunchDaemon plist

## bootstrap.json
While `instapplications.py` is the orchestrator for your deployment, the `bootstrap.json` file is blueprint for how it should operate. If you are a munki user, think of the bootstrap.json as a single file that combines some concepts from catalogs, pkginfo files and manifests.

As InstallApplications is designed to be installed by mdmclient _during_ SetupAssistant, there are two "stages" where applications/scripts can be ran.
- setupassistant
- userland

Additionally, InstallApplications currently supports three types of components:
- package
- rootscript
- userscript

```json
{
  "setupassistant": [
    {
      "file": "/Library/Application Support/installapplications/DEPNotify-1.0.3.pkg",
      "hash": "527d74c85e1597a733da498674c047de7d293a6e455acaf88b33e325f1b7fb00",
      "name": "DEPNotify",
      "packageid": "com.installapplicationsdemo.depnotify",
      "type": "package",
      "url": "https://raw.githubusercontent.com/erikng/installapplicationsdemo/master/installapplications/pkgs/DEPNotify-1.0.3.pkg",
      "version": "1.0.3"
    }
  ],
  "userland": [
    {
      "donotwait": true,
      "file": "/Library/Application Support/installapplications/caffeinate.py",
      "hash": "92bb078979917a745febdfa10256831dfb4fb46ed0628af3b1e04bf5bbede910",
      "name": "Caffeinate Machine",
      "type": "rootscript",
      "url": "https://raw.githubusercontent.com/erikng/installapplicationsdemo/master/installapplications/scripts/root/caffeinate.py"
    }
  ]
}
```

In the example above, we are installing DEPNotify (as a package) while the user is still in SetupAssistant portion, and as soon as the user is in their session, DEPNotify is launched (more on this in a second) and the machine is caffeinated (with a root level script).

### donotwait
One key to pay attention to is `donotwait`. This is an optional key that InstallApplication uses to process scripts differently. When I open sourced the [caffeination script](https://github.com/erikng/mdmscripts/blob/master/dep/machinescripts/caffeinate.py#L3-L7) last week, I put a warning in the comments where this command line tool will wait until it's finished.

What this means is if you do not pass the `donotwait` key, you will wait for _entirety_ of the caffeination script to finish, thereby ruining the entire point of caffeination.

Obviously this key can be applied for other scripts, so if you find yourself running into this, you can easily handle it by following utilizing this key.

## LaunchDaemon
InstallApplications supports several arguments, all of which can be passed through the LaunchDaemon.

```xml
<key>ProgramArguments</key>
<array>
  <string>/usr/bin/python</string>
  <string>/Library/Application Support/installapplications/installapplications.py</string>
  <string>--jsonurl</string>
  <string>https://raw.githubusercontent.com/erikng/installapplicationsdemo/master/installapplications/demo.json</string>
  <string>--depnotify</string>
  <string>Command: WindowTitle: InstallApplicationsDemo</string>
  <string>Command: Image: /Applications/Launchpad.app/Contents/Resources/Launchpad.icns</string>
  <string>Status: Configuring Machine...</string>
  <string>DEPNotifyPath: /Applications/Utilities/DEPNotify.app</string>
  <string>DEPNotifyArguments: -munki</string>
</array>
```

### DEPNotify

Let's break down the flags above:
- `--jsonurl` is a URL to your blueprint
- `--depnotify` tells InstallApplications to open DEPNotify for the user
- `DEPNotifyPath: /path/to/DEPNotify` required path to DEPNotify
- `DEPNotifyArguments: -munki` to create a blank munki log which DEPNotify will tail it upon launch.
- `Command: Image: /Applications/Launchpad.app/Contents/Resources/Launchpad.icns` A custom image for DEPNotify to use, in this case LaunchPad.icns.

As you can see from above, InstallApplications is very modular.

By default, InstallApplications will automatically create a `determinate` number for DEPNotify to use, which allows the progress bar to automatically move as each DEP step is processed. If you need more advanced DEP status messages, my suggestion is to turn this off by adding `<string>DEPNotifySkipStatus</string>` to the LaunchDaemon, which will prevent InstallApplications from passing _any_ status messages to the DEPNotify log.

With the latest version of DEPNotify, you can also open it in fullscreen. To do this you could do either of the following, depending on your needs:
- `<string>DEPNotifyArguments: -munki -fullScreen</string>`
- `<string>DEPNotifyArguments: -fullScreen</string>`

## LaunchAgent
While the LaunchAgent isn't designed to be customized, it works similarly to outset's on-demand feature in that it utilizes a watch path. When you utilize a `userscript`, InstallApplications does the following:

Root InstallApplications process:
- Copies the script to a staging area
- Touches a hidden file (with 777 permissions) for the watch path
- Waits for the watch path to be removed

User InstallApplications process:
- Runs the script with the launchagent (which calls another process of InstallApplication with different flags)
- Once the script has finished running, the watch path is removed

Root InstallApplications process:
- Continues on as normal and processes the next item

# Putting all of this together
For our demo environment, we want to do the following:
- Setup installapplications and create a package
- Setup Munki

## InstallApplication bootstrap.json
During SetupAssistant:
- Install Munki's launchdaemons and agents (which will allow the agents to automatically load when the user logs in)
- Install Munki's core tooling
- Install DEPNotify

Given that we want to have these core tools processed as quickly as possible and will be using DEPNotify for our DEP UX, we don't need the other components of munki.

During userland:
- Caffeinate the machine and process it in a separate child process
- Bless the machine if it's running 10.13/APFS and on a virtual machine
- Bootstrap Munki with a core set of applications
- Load the LaunchDaemons for Munki
- Trigger a Munki auto run and process it in a separate child process
- Trigger a dockutil run on behalf of the user
- Send an exit command to DEPNotify to inform the user to logout and enable FileVault (through Crypt)

## Munki Bootstrap
We will run munki with a specific manifest that only installs the core tools we need:

- Managed Software Center
- Munki's app_usage components
- Crypt
- dockutil
- Munki profile to move to a "production" manifest
- Crypt profile to ensure Crypt is triggered after the reboot.

## So what does this look like?

bootstrap.json

```json
{
  "setupassistant": [
    {
      "file": "/Library/Application Support/installapplications/munkitools_launchd-3.0.3265.pkg",
      "hash": "66441eaba5aa717fd81d1a84ddfb309da90cff6bc5904dc0e94c1f6e216c2a89",
      "name": "Munki LaunchD",
      "packageid": "com.googlecode.munki.launchd",
      "type": "package",
      "url": "https://raw.githubusercontent.com/erikng/installapplicationsdemo/master/installapplications/pkgs/munkitools_launchd-3.0.3265.pkg",
      "version": "3.0.3265"
    },
    {
      "file": "/Library/Application Support/installapplications/munkitools_core-3.1.1.3447.pkg",
      "hash": "9fa295fccb24369f4d6296a170fca5ec26f4bae46138fb58579ac24fdfc5b5cb",
      "name": "Munki Core",
      "packageid": "com.googlecode.munki.core",
      "type": "package",
      "url": "https://raw.githubusercontent.com/erikng/installapplicationsdemo/master/installapplications/pkgs/munkitools_core-3.1.1.3447.pkg",
      "version": "3.1.1.3447"
    },
    {
      "file": "/Library/Application Support/installapplications/DEPNotify-1.0.3.pkg",
      "hash": "d09b878d32418d16d79c0ad4d89bb0d426c2914a6ce1f9238d7b4e98762f9c35",
      "name": "DEPNotify",
      "packageid": "menu.nomad.DEPNotify",
      "type": "package",
      "url": "https://raw.githubusercontent.com/erikng/installapplicationsdemo/master/installapplications/pkgs/DEPNotify-1.0.3.pkg",
      "version": "1.0.3"
    }
  ],
  "userland": [
    {
      "donotwait": true,
      "file": "/Library/Application Support/installapplications/caffeinate.py",
      "hash": "92bb078979917a745febdfa10256831dfb4fb46ed0628af3b1e04bf5bbede910",
      "name": "Caffeinate Machine",
      "type": "rootscript",
      "url": "https://raw.githubusercontent.com/erikng/installapplicationsdemo/master/installapplications/scripts/root/caffeinate.py"
    },
    {
      "file": "/Library/Application Support/installapplications/high_sierra_vm_bless.py",
      "hash": "52df572785e5b79806032049000450da463ecceeecc83671e1bc6bd61996248f",
      "name": "Bless VM",
      "type": "rootscript",
      "url": "https://raw.githubusercontent.com/erikng/installapplicationsdemo/master/installapplications/scripts/root/high_sierra_vm_bless.py"
    },
    {
      "file": "/Library/Application Support/installapplications/munki_bootstrap.py",
      "hash": "78d00124021f8c6d8fbaf5d35a249715be3ba1206a8227bf9b8f2213f128fcf8",
      "name": "Munki Bootstrap",
      "type": "rootscript",
      "url": "https://raw.githubusercontent.com/erikng/installapplicationsdemo/master/installapplications/scripts/root/munki_bootstrap.py"
    },
    {
      "file": "/Library/Application Support/installapplications/munki_launchd_loader.py",
      "hash": "954b7cec547dcc4e638991301ba600419e2b6aed15dc09ee412b1ba6218d31af",
      "name": "Munki LaunchD Loader",
      "type": "rootscript",
      "url": "https://raw.githubusercontent.com/erikng/installapplicationsdemo/master/installapplications/scripts/root/munki_launchd_loader.py"
    },
    {
      "donotwait": true,
      "file": "/Library/Application Support/installapplications/munki_auto_trigger.py",
      "hash": "0ac1bef0c51c3eb2da95418abc691eb1eb02f1096b1ca7d709ffd669f620c13d",
      "name": "Munki Auto Trigger",
      "type": "rootscript",
      "url": "https://raw.githubusercontent.com/erikng/installapplicationsdemo/master/installapplications/scripts/root/munki_auto_trigger.py"
    },
    {
      "file": "/Library/Application Support/installapplications/userscripts/dockutil.py",
      "hash": "1a8e8559e40c672ad63ecf136c31db4d2dc97a2bef8002a16497fa08bfbf6819",
      "name": "Dockutil User",
      "type": "userscript",
      "url": "https://raw.githubusercontent.com/erikng/installapplicationsdemo/master/installapplications/scripts/user/dockutil.py"
    },
    {
      "file": "/Library/Application Support/installapplications/depnotify_end.py",
      "hash": "8654428ada3b861e07ef46bbb160dc06be2ea62b3d961faccb6a8fe7539f6a65",
      "name": "DEPNotify End",
      "type": "rootscript",
      "url": "https://raw.githubusercontent.com/erikng/installapplicationsdemo/master/installapplications/scripts/root/depnotify_end.py"
    }
  ]
}
```

In the example above, I'd like to point out something and encourage you to _not_ do in production - I am using (abusing?) github raw files for the bootstrap.json file. This means you are dependent on the GitHub CDN up-time and caching rules. While making this blog post I had a few fun issues with caching that caused InstallApplications to fail because the hashes did not match. Waiting a few minutes fixed this.

## Debugging issues
InstallApplications logs as many events as it possibly can to help you troubleshoot issues you may experience.

Some things it can definitely help with:
- Python scripts you've created tracing
- Hash validation issues
- bad URL's

You can find logs for both the root process and agent process at the following locations:
- /var/log/installapplications.log
- /var/tmp/installapplications/installapplications.user.log

### I have a bad script, now what?
While writing this post, I too made some careless mistakes, that caused the DEP run to fail.

You can see a great example [right here](https://github.com/erikng/installapplicationsdemo/commit/ecfff292236b70380dc02f798886455080f50eab), but pay attention to how easy the fix was.

I made two changes and pushed the code:
- fix the script
- update the bootstrap.json with the new SHA256 hash

That's it! No recreation of packages, no changes to the MDM itself, just a simple git commit. This will really help you when you're doing rapid MDM testing or have a critical DEP bug you find in production.

### Notes about running InstallApplications in terminal

While you can technically run InstallApplications `sudo python /Library/Application Support/installapplications/installapplications.py --jsonurl https://somewhere.tld` to test, it is highly encouraged that you _don't_ do this. Your root scripts will run in a slightly different environment (non-daemonized), and in my testing, they may work in terminal runs but not during DEP.

## Example video

![Demo](/images/2017/12/iadepnotify_demo.gif)

# Final thoughts

I've create an [InstallApplications Demo repo](https://github.com/erikng/installapplicationsdemo) which contains everything I explained in this blog post. With a signing certificate, you can create the `InstallApplicationsDemo-1.0.pkg` file, uploaded it to your MDM and have a working demo.

I hope with this, you can see a real, working custom DEP demo and this can be used as a building block for your eventual production rollout.

---

Hey JAMF - how about you join this custom DEP thing?


## Table Of Contents
* Do not remove this line (it will not be displayed)
{:toc}
