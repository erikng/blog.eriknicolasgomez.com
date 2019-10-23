---
layout: post
author: Erik Gomez
title: "C-MDM Part 2 - managing workspace one profiles with chef using the new v1910 hubcli agent"
description: "This is going to be a crazy journey"
tags: [ABM, AirWatch, API, CM, Configuration Management, Chef, DEP, MDM, Mobile Device Management, Munki]
published: true
date: 2019-10-30 00:00:00
comments: true
---

It's been a while...

I've been pretty busy [at my current company](https://eng.uber.com/scaling-mobile-device-management-at-uber/). Whether it was refactoring the chef code with my co-workers [Nate](https://github.com/natewalck), [Austin](https://github.com/chefaustin) and my former co-worker [Art](https://www.linkedin.com/in/art-hagopian-19619458) or scaling MDM with my co-worker [Danielle](https://twitter.com/techincolor) or standardizing our macOS versions at Uber, it's been a long, sometimes exhausting challenge.

While I never officially discussed the work that came from that, here's a link to all the tools that made all of these things a success.
- [Uber CPE Chef Cookbooks](https://github.com/uber/cpe-chef-cookbooks)
- [UMAD](https://github.com/erikng/umad)
- [Nudge](https://github.com/erikng/nudge)

With that out of the way...

## There's doom around the corner
With macOS Catalina, there's now a pretty explicit warning about the potential future of locally installed profiles.

```
profiles help
    WARNING: In the future, some features in this tool may be removed in favor of using user approved,
        high level UI to install configuration profiles.  Clients should instead use the Profiles System
        Preferences pane to install configuration profiles.
```

A **significant** amount of the chef open source cookbooks rely on the built in `profiles` resource and also use Facebook's `cpe_profiles` to dynamically enforce both the installation and removal of locally installed profiles. Puppet also not immune to this.

Munki also utilizes the `profiles` binary to install and remove profiles.

For some organizations, losing the ability to manage locally installed profiles could be even worse than UAMDM, KernelExtension profiles or even the past two years of TCC changes.

The community needs to embrace the fact that we might be losing this and come up with some kind of plan. So what do we do?

## Remember part one?
In March of 2018, I wrote about a [hack](https://github.com/erikng/cmdm_poc) I built abusing [chef's built in resources](/2018/03/27/CMDM-Part-1-a-hacky-prototype-middleware-solution-for-extending-MDM-with-CM/). While it was a super interesting project to work on, realistically it could never be put in production use just because of the sheer security issues that would come with shipping such a high level API key on every client device. It was simply too powerful.

But people were _very_ intrigued with the idea and it spurred lots of great discussions.

Recently, [Graham Gilbert](https://grahamgilbert.com/) released a much better idea around this concept called [MDM Director](https://github.com/mdmdirector/mdmdirector). It's actually quite incredible, but unfortunately it requires MicroMDM and a hell of a lot of deep knowledge around the MDM protocol, MDM APIs, and Go.

Utilizing MicroMDM and MDMDirector together certainly reduces if not completely removes the need for locally installed profiles (and much much more), but it may not be for everyone - certainly not if you pay a MDM vendor.

## The partnership with Workspace One has continued
I've had a pretty great partnership with Workspace One. We co-authored and released the [custom bootstrap methodology](https://docs.vmware.com/en/VMware-Workspace-ONE-UEM/1811/VMware-Workspace-ONE-UEM-macOS-Device-Management/GUID-AWT-BOOTSTRAP-C.html) and I wrote an open sourced [InstallApplications](https://github.com/erikng/installapplications) which continues to be used worldwide to provision macOS devices through MDM enrollment.

After joining my current employer, we too realized that some kind of middleware tool would be a highly valuable to have in our arsenal. While Nate and I wanted (want) to build something as robust as MDMDirector for Workspace One, we decided to again partner with the Workspace One macOS team to create a secure, device level binary that could send commands directly to the MDM server.

## Workspace One v1910 - hubcli
With the October 2019 release of Workspace One Agent (requires Workspace One Console v1910 as well), there is a new binary called `hubcli`.

We actually have a reason to install the agent! :smile:

### A quick primer on hubcli
The `hubcli` binary utilizes the MDM certificate installed onto the device (at time of enrollment) to communicate to enhanced Workspace One APIs. This ensures the device can **only obtain and send commands on behalf of itself** and no other devices enrolled into your console.

### Getting information from hubcli
The Workspace One agent installs a symlink to `/usr/local/bin/hubcli` which currently points to `/Applications/Workspace ONE Intelligent Hub.app/Contents/Resources/IntelligentHubAgent.app/Contents/Resources/cli/hubcli`.

```
hubcli
Description:
  VMware Workspace ONE Intelligent Hub Command Line Interface.
Usage:
  hubcli <COMMAND> [flags]
Commands:
  config    Get or set Hub settings. Changing configurations will override the UEM Console.
  notify    Display a custom notification to the current user.
  sync    Trigger a Hub sync with Workspace ONE UEM.
  logs    Collect Hub diagnostics and send to the UEM Console.
  profiles    Request installation of an assigned profile from the Workspace ONE UEM.
Examples:
  View help for a Command
    hubcli <COMMAND> --help
```

Of interest to us is the `hubcli profiles` command
```
hubcli profiles --help
Description:
  Request installation of an assigned profile from the Workspace ONE UEM.
Usage:
  hubcli profiles <--install ProfileID> | <--list [--json]>
Commands:
  --install    Request installation of an assigned profile from the Workspace ONE UEM.
  list    Request list of all assigned profiles from Workspace ONE UEM.
  json    List all assigned profiles in json format.
Examples:
  Request installation of an assigned profile from the Workspace ONE UEM.
    hubcli profiles --install <ProfileID>
  Request list of all assigned profiles from Workspace ONE UEM.
    hubcli profiles --list
  Request list of all assigned profiles from Workspace ONE UEM in json format.
    hubcli profiles --list --json
```

If we run `hubcli profiles --list --json` we get nice json list of all profiles currently scoped to the device.
```
{
  "DeviceProfiles" : [
    {
      "Id" : 12345,
      "Description" : "",
      "AssignmentType" : "Optional",
      "Name" : "Example User Profile",
      "InstalledProfileVersion" : 1,
      "Status" : "ConfirmedInstall",
      "CurrentVersion" : 1
    },
    {
      "Status" : "ConfirmedInstall",
      "CurrentVersion" : 2,
      "AssignmentType" : "Optional",
      "Name" : "Example Device Profile",
      "Id" : 54321,
      "InstalledProfileVersion" : 2,
      "Description" : ""
    }
  ],
  "Total" : 2,
  "DeviceId" : {
    "Id" : {
      "Value" : 9999
    }
  }
}
```

One drawback here is that this API currently returns the key `DeviceProfiles` for _all_ profiles, regardless if the profile is a User level profile or a Device level profile. More information on that later, but if you don't like this behavior like I do [send some feedback to VMware End-User Computing](https://www.vmware.com/go/eucideas/).

With this information though, we can now craft an installation command, by specifying the profile ID. If it's successful, we will get a status from hubcli.

```
hubcli profiles --install 12345
Profile install successfully triggered.
```

So now that we have a pretty powerful tool, let's put this to use with chef.

## cpe_workspaceone
[cpe_workspaceone](https://github.com/uber/cpe-chef-cookbooks/tree/master/cpe_workspaceone) is a wrapper around hubcli that enables some pretty cool functionality.

- Installs the agent and manages its preferences so you can do things like hide the menubar. This is useful if you don't need the agent for anything other than the `hubcli`
- Runs `hubcli profiles --list --json` and caches this JSON to disk so we don't melt our MDM server with thousands of calls per hour
- Gets the current OS at the time of caching the JSON and injects it into the JSON payload
- Allows the admin to enforce and install a list of user level profiles and device level profiles and then compares them to the list of currently available profiles.

By utilizing the cache, we also can invalidate it in specific cases.
- By default, invalidates it after 7200 seconds (2 hours)
- invalidates the cache if the installed operating system is higher than the cached os version.

By invalidating the cache, this allows us to do clever things like deploy new profiles at the time of reboot when a machine upgrades their macOS version.

### Real world examples
So how does this work in practice with chef. Well it's actually pretty simple.

Assuming you already have the agent installed on your machine and want to just manage profiles, you could do something as simple as this:

```
node.default['cpe_workspaceone']['mdm_profiles']['enforce'] = true
node.default['cpe_workspaceone']['mdm_profiles']['profiles']['device'] = [
  'Example Device Profile',
]
node.default['cpe_workspaceone']['mdm_profiles']['profiles']['user'] = [
  'Example User Profile',
]
```

If you wanted to do something more advanced and scope a specific profile behind an OS version, you could do something like this:

```
node.default['cpe_workspaceone']['mdm_profiles']['enforce'] = true
node.default['cpe_workspaceone']['mdm_profiles']['profiles']['device'] = [
  'Example Device Profile',
]
node.default['cpe_workspaceone']['mdm_profiles']['profiles']['user'] = [
  'Example User Profile',
]

if node.catalina?
  [
    'Example Catalina Device Profile',
  ].each do |item|
    node.default['cpe_workspaceone']['mdm_profiles']['profiles']['device'] << item
  end
end
```

When you run chef, it would look like this:
```
Recipe: cpe_workspaceone::default
    * execute[Sending Example Device Profile for device installation to Workspace One console] action run[] INFO: Processing execute[Sending Example Device Profile for device installation to Workspace One console] action run (/var/chef/cache/cookbooks/cpe_workspaceone/resources/cpe_workspaceone.rb line 72)

      [execute] Profile install successfully triggered.
[] INFO: execute[Sending Example Device Profile for device installation to Workspace One console] ran successfully
      - execute /Applications/Workspace\ ONE\ Intelligent\ Hub.app/Contents/Resources/IntelligentHubAgent.app/Contents/Resources/cli/hubcli profiles --install 12345
    * execute[Sending Example User Profile for user installation to Workspace One console] action run[] INFO: Processing execute[Sending Example User Profile for user installation to Workspace One console] action run (/var/chef/cache/cookbooks/cpe_workspaceone/resources/cpe_workspaceone.rb line 94)

      [execute] Profile install successfully triggered.
[] INFO: execute[Sending Example User Profile for user installation to Workspace One console] ran successfully
      - execute /Applications/Workspace\ ONE\ Intelligent\ Hub.app/Contents/Resources/IntelligentHubAgent.app/Contents/Resources/cli/hubcli profiles --install 54321
```

Workspace One will then send the commands to the device and the profiles will install. If you run chef again, it won't try to re-install the profiles:

```
Recipe: cpe_workspaceone::default
    * execute[Sending Example Device Profile for device installation to Workspace One console] action run[] INFO: Processing execute[Sending Example Device Profile for device installation to Workspace One console] action run (/var/chef/cache/cookbooks/cpe_workspaceone/resources/cpe_workspaceone.rb line 72)
 (skipped due to not_if)
    * execute[Sending Example User Profile for user installation to Workspace One console] action run[] INFO: Processing execute[Sending Example User Profile for user installation to Workspace One console] action run (/var/chef/cache/cookbooks/cpe_workspaceone/resources/cpe_workspaceone.rb line 94)
 (skipped due to not_if)
     (up to date)
```

This is because we use the following commands to understand if the profile is installed:
- `/usr/bin/profiles show -output stdout-xml` for Device profiles on 10.13 +
- `/usr/bin/profiles -Co stdout-xml` for Device profiles on 10.12 and lower
- `/usr/bin/profiles show -output stdout-xml -user CONSOLEUSER` for User profiles on 10.13 +
- `/usr/bin/profiles -Lo stdout-xml -U CONSOLEUSER` for User profiles on 10.12 and lower

We than take that content and loop through the resulting plist, and compare each item's `ProfileDisplayName`. If the DisplayName matches the enforced profile, we know it's been installed.

One thing to be mindful of is that Workspace One takes the name of your profile and adds special information to the profile. For instance if you name a profile `Example Device Profile` in the MDM console, it will deploy to your device `Example Device Profile/V_1` and update the "version" each time you make a change in the console.

`cpe_workspaceone` doesn't care about this abstraction detail and simplifies it by concatenating the string and logic automatically for you. All _you_ need to care about is the profile name.

## Final Thoughts
If you are a Chef shop that also uses Workspace One and want to start utilizing this with chef, download the `cpe_workspaceone` cookbook [here](https://github.com/uber/cpe-chef-cookbooks/tree/master/cpe_workspaceone). Remember you need to be on version 1910 of the console and agent for this to work.

But there's no reasons why any of these concepts have to be limited to chef. It could be a simple bash script or some advanced munki middleware logic. It's only limited by your imagination around the tools you build and deploy.

I look forward to seeing what crazy stuff the community comes up with and remember, if you have any ideas on how to make `hubcli` better, please [send some feedback to VMware End-User Computing](https://www.vmware.com/go/eucideas/). Ping me too so I can vote on it!

But next time...we are going to remove profiles...

## Table Of Contents
* Do not remove this line (it will not be displayed)
{:toc}
