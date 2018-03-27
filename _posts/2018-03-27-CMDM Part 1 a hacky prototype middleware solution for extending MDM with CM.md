---
layout: post
author: Erik Gomez
title: "C-MDM Part 1 - a hacky, prototype middleware solution for extending MDM with CM"
description: "This is going to be a crazy journey"
tags: [AirWatch, API, Configuration Management, Chef, DEP, Mobile Device Management, Munki, Puppet]
published: true
date: 2018-03-27 13:00:00
comments: true
---

A few days ago I tweeted a very vague picture from System Preferences, showing an unsigned, MDM installed profile. At the time, no one really picked up on the importance of it, but today I would like to introduce you to the concept of C-MDM. My vision for C-MDM is a middleware tool, that can aggregate data locally on a device, analyze what settings it needs to manage and then ship that over to your MDM of choice for installation and/or removal.

But before we get to that I have to tell you a few stories...

## Origin Story
In April of 2017, I gave a [presentation](/2017/04/27/Custom-DEP-Part-6-Vendor-Announcement-and-Presentation/) around Custom DEP. During that presentation I discussed something that AirWatch did that didn't get a lot of coverage: an api where you could send arbitrary MDM commands to a device. At the time I open sourced a practical python example of how you could use this API to [deliver any package](https://github.com/erikng/mdmscripts/blob/master/airwatch/api/installapplication/aw_api_installapplication.py) through the MDM command `InstallApplication` (not to be confused with my tool). My hope was maybe a clever admin would write some kind of MDM PlanB, where if a device is no longer communicating to their tools (say munki), MDM could just re-push the installer.

Unfortunately no one, including myself ever had time to use this API for anything other than a demo.

### This API is powerful, but why did AirWatch build it in the first place?
Before the Custom DEP partnership announcement and even before the joint meetings, AirWatch wanted to create a new API, to extend their MDM beyond the typical UI usage.

By creating this "Bare-metal MDM API", AirWatch could solve the following:
1. They could prioritize new MDM commands in their current roadmap and write full UI/UX as they built them.
2. _Customers_ could test new, beta MDM commands on their production instances without a secondary beta/QA instance as soon as Apple released the beta macOS versions.
3. They would always have "0-day" support for _all_ current/future MDM commands through this API.

AirWatch launched this new API with AirWatch 9.1, but made one interesting design choice that would later have ramifications...

### Configuration Management .mobileconfig installs vs MDM .mobileconfig installs

#### Cons of MDM .mobileconfig installs
During this same presentation, I outlined some of the main issues I had with the way all MDM vendors handled .mobileconfig installations.

1. They copied Profile Manager's terrible UI
2. Because of issue 1, they mixed several `PayloadType` configurations inside one UI/profile payload. (Example: Restrictions)
3. Because of issue 1, they also added payload keys that an admin may not realize they are managing (Example: Unchecking an item sets the value to `False`, not removing the key from management)
4. Because of issue 1, 2 and 3, if an admin deployed two profiles with conflicting settings, the client device could get in an [undefined state](https://help.apple.com/serverapp/mac/5.0/#/apdE3493-C50A-4E9E-DDDD-CBCBC8C73507), where settings are loaded at random.
5. Most MDM's lack variable driven payload keys or only have these for very specific configurations (Example: 802.1x profiles)
6. MDM's lack the ability to understand the profile's installation _content_. In other words, they can only know the profile is installed, not what settings were used.

#### Pros of MDM .mobileconfig installs
While there are several issues with the way MDM's handle profiles (making them untenable for most of my use cases), there are a few pro's, some of them which we are now only beginning to see with the release of 10.13.4.

1. MDM's can sign/encrypt the profile, prior to installation
2. MDM's can mark the profile as non-removable
3. **Apple is beginning to limit what locally installed profiles can configure** (Example: User Approved Kernel Extensions)

#### Pros of Configuration Management .mobileconfig installs
Configuration management tools like chef, solved all of the major issues I had with MDM profile installations:

- I have complete control of all profile settings.

The `cpe_profiles` cookbook created by Facebook and the various `cpe_X` cookbooks that install profiles were all written with best practices in mind. Only the keys needed to manage the settings are injected and each profile contains only the PayloadType(s) required to manage that feature.

- I can drive profiles with variables, override preferences with conditions and check the profile's installation context.

If I wanted to dynamically manage a SetupAssistant value, I could do something like this:

```ruby
node.default['cpe_setupassistant']['once']['LastSeenCloudProductVersion'] =
  node['platform_version']

# This feature is only available in 10.13.4 and higher.
if node.os_greater_than?('10.13.4')
  node.default['cpe_setupassistant']['managed']['SkipPrivacySetup'] = true
end
```

As the device installs/updates the macOS version (`node['platform_version']`), chef compares the current settings installed and if it detects a mismatch between what should be installed and what is installed, it will update the profile's configuration and re-install the profile. While MDM's can get the macOS version, this is just a rudimentary example of the flexibility and power you get with device level context. An admin could create _any_ arbitrary condition and is not limited to what `mdmclient` ships to the MDM.

#### Cons of Configuration Management .mobileconfig installs
But of course there are cons, and guess what? The cons are exactly the **Pros** of MDM .mobileconfig installs!

1. Chef cannot sign the profile itself
2. Chef cannot install signed profiles without experiencing a fatal crash
3. All locally installed profiles cannot be marked as non-removable. You could in theory add a `PayloadPasscode` key to your profile, but that password would be in your cookbook recipe and a user with administrator access can actually install a profile on top of your profile that doesn't have a `PayloadPasscode` key and then remove the entire profile payload.
4. You can't manage Kernel Extensions and you probably won't be able to manage other new features when 10.14 comes out.

## Present Day
Last Friday I had a few questions:

### Question 1 - Can you use the AirWatch bare-metal MDM API to install and remove profiles?
While reading the [MDM Protocol Reference Guide](https://developer.apple.com/library/content/documentation/Miscellaneous/Reference/MobileDeviceManagementProtocolRef/3-MDM_Protocol/MDM_Protocol.html), I found the two payloads for installing and removing profiles.

#### Removing an MDM installed profile
When MDM sends a command to the client for removing a profile it has installed, the payload looks something like this (snipped for clarity).

```xml
<key>Command</key>
<dict>
  <key>RequestType</key>
  <string>RemoveProfile</string>
  <key>Identifier</key>
  <string>com.github.profile.chef.setupassistant</string>
</dict>
```

The Identifier key is the `PayloadIdentifier` of an installed profile. You can find these by running `/usr/bin/profiles -L` on your machine.

#### Installing a profile via MDM
Installing a profile is a bit more complex, but in practice not too difficult.

```xml
<key>Command</key>
<dict>
  <key>RequestType</key>
  <string>InstallProfile</string>
  <key>Payload</key>
  <data>SWYgeW91IGFjdHVhbGx5IGRlY29kZWQgdGhpcyBtZXNzYWdlIHlvdSBhcmUgYXdlc29tZSBhbmQgd2Ugc2hvdWxkIHdvcmsgdG9nZXRoZXIuIDop</data>
</dict>
```

The Payload key is the contents of a .mobileconfig profile, base64 encoded.

You can do something like this with the following python code:

```python
import base64
profilepath = '/path/to/your.mobileconfig'
profilepayload = open(profilepath, 'rb').read()
b64profile = base64.b64encode(profilepayload)
print '<data>' + base64.b64encode(b64profile) + '</data>'
```

You should end up with something like `<data>SWYgeW91IGFjdHVhbGx5IGRlY29kZWQgdGhpcyBtZXNzYWdlIHlvdSBhcmUgYXdlc29tZSBhbmQgd2Ugc2hvdWxkIHdvcmsgdG9nZXRoZXIuIDop</data>`.

#### Trying this with the AirWatch API.
With this information, I modified my [InstallApplication API script](https://github.com/erikng/mdmscripts/blob/master/airwatch/api/installapplication/aw_api_installapplication.py) and tried to first remove a profile I had installed with MDM. Within a second of running it, my profile vanished!

Unfortunately, when attempting to install a profile, nothing happened. The server responded with a `422` message rather than a `402`. I reached out to [Victor](https://github.com/groob) to see if perhaps I was doing something incorrectly, but he validated my approach.

With that I finally contacted AirWatch and consulted with them on the issue. They reminded me that this feature was also available through the UI in the `Device List` view (wtf is a UI?). When attempting to send the command, I got a very interesting error - AirWatch refused to display the `Send command` button because my command was over 2,000 characters!

With a few changes to my script, I returned the error message and sure enough:

```json
{
  "errorCode": 1012,
  "message": "Element: customCommandModel.CommandXml Message: CommandXml length cannot be greater than 2000.",
  "activityId": "28785557-e731-4e49-b714-87acf92dba5f"
}
```

With this new error, I set out to try and create the most minimalistic profile I could install and also create some logic in my script to handle this.

```python
if len(command) > 2000:
  print 'Currently, AirWatch limits the payload portion to 2000 characters. '\
    'This profile is not compatible for installation via the api. This will '\
    'be fixed soon. Your length: %s' % str(len(command))
  exit(1)
else:
  continue
```

With this new case written and a profile under 2,000 characters, I tried it again and... it worked!

So my question was finally answered. Yes, you can _absolutely_ install and remove profiles directly with Airwatch's bare metal API. There are some limitations, but this is a great first step.

Why the 2,000 character limitation? To prevent this API from being abused. Oh well... :smile:

### Question 2 - Can I somehow inject this concept directly into my configuration management tool?
With my first question answered, I set forth to see if I could inject this idea into chef.

I had crazy theories about monkey-patching chef, but then I realized something: The [osx_profile provider/resource](https://github.com/chef/chef/blob/master/lib/chef/provider/osx_profile.rb) was originally written by my good friend [Nate Walck](https://github.com/natewalck) and he opted to use **relative** paths to the profile binary. This was because he followed Chef best practices - binaries on unix machines can have several different paths and rather than use cases/absolute paths per OS, you simply use relative paths and let the default search paths take over.

The [cpe_profiles](https://github.com/facebook/IT-CPE/blob/master/chef/cookbooks/cpe_profiles/resources/cpe_profiles.rb) cookbook written by Nate Walck and Mike Dodge also used relative paths.

This meant that when chef ran the following would occur:
1. To obtain the info on all of the currently installed profiles, `profiles -P -o stdout-xml` would be invoked.
2. If a profile needed to be installed/upgraded, `profiles -I -F '#{profile_path}'` would be invoked.
3. If a profile needed to be removed, `profiles -R -p '#{@new_profile_identifier}'` would be invoked.

By abusing the default search paths and the fact that both the osx_profile provider and cpe_profile cookbook used relative paths, I could create my middleware tool at `/usr/local/bin/profiles` and override the native binary.

#### This is an evil hack, but a brilliant one.

In order to do this, I would need to do the following:

1. Subprocess out to the real profiles binary (`/usr/bin/profiles -P -o stdout-xml`) to get back the currently installed profile information and return that to the cpe_profiles cookbook so chef wouldn't freak out and fail to run.
2. Have my middleware profiles binary accept `-I -F /path/to/chef.mobileconfig` and `-R -p profileidentifier` as arguments.
3. If chef passes the installation arguments, take that mobileconfig, check the total length of the payload and it it's under 2,000 characters, send that to the MDM with the bare-metal API. If it's over 2,000 characters, subprocess the installation to the real profiles binary. After that appropriately validate the install status.
4. If removing a profile, determine the install type and send the appropriate command either to the real profiles binary or the bare-metal API. After that, appropriately validate the removal status.

After creating my logic and testing it out with local mobileconfigs, it was time to yolo run this on my machine.

```ruby
sudo chef-client
Starting Chef Client, version 13.8.5

Recipe: cpe_profiles::default
  * cpe_profiles[Managing all of Configuration Profiles] action run
  Recipe: <Dynamically Defined Resource>
    * osx_profile[com.pinterest.profile.chef.browsers.safari] action install
      - install profile com.pinterest.profile.chef.browsers.safari
```

![MDM API - Profile Install](/images/2018/03/mdm_api_profile_install.jpg)

And so the tweet from last Friday was my first successful chef-run with my fake profiles binary! I now had a MDM installed profile, powered via chef.

But if I can do this, can I get other benefits as well?

### Question 3 - Can I also install a _signed_ profile with Chef and/or AirWatch's bare-metal API?
Now that I knew I could abuse the entire profile system for MDM purposes, I wondered if I could also gain the other benefit of signing profiles.

Using [Nick McSpadden's Keychain blog post](https://osxdominion.wordpress.com/2015/04/21/signing-mobileconfig-profiles-with-keychain-certificates/) as a start, I wrote a few poc python functions to get this information:

```python
def find_signing_cert():
    try:
        proc = subprocess.Popen(['/usr/bin/security', 'find-identity', '-p',
                                 'codesigning', '-v',
                                 '/Library/Keychains/System.keychain'],
                                stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE)
        output, _ = proc.communicate()
        # For now just return the first cert.
        firstcert = output.split('\n')[0].split('"')[1]
        return firstcert
    except (IOError, OSError, TypeError):
        return False


def sign_profile(profilepath, signingcert, signedprofilepath):
    try:
        cmd = ['/usr/bin/security', 'cms', '-S', '-N', signingcert, '-i',
               profilepath, '-o', signedprofilepath, '-k',
               '/Library/Keychains/System.keychain']
        proc = subprocess.Popen(cmd, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE)
        output, _ = proc.communicate()
        return output
    except (IOError, OSError, TypeError):
        return False

some other code that needed to be written
```

After this, I simply added a code signing public/private key to my System Keychain and gave the `security` binary read access.

![Security - Access Control](/images/2018/03/security_access_control.png)

I deleted my profiles and re-ran chef-client and viola! I had signed profiles on my machine!

![Chef - Signed Profiles](/images/2018/03/chef_signed_profiles.png)

Unfortunately, the MDM icon was gone. After doing some debugging, I discovered that signing a profile added around **4,000** characters to the payload, which as we now know is too large for AirWatch's bare-metal API.

With that bit of information I rewrote my logic to do the following:
- If I have a signing certificate, create a signed version of the profile in question.
  - If the signed profile is over 2,000 characters (which we know it will probably always be), analyze the original, unsigned profile.
  - If the unsigned profile is under 2,000 characters, send that to the MDM so we can get the Non-Removable flag.

- If both the unsigned profile and the signed profile are over 2,000 characters, install the signed profile locally with /usr/bin/profiles.
- If there is no signing certificate, use the original logic and install via MDM if under 2,000 characters or locally if over.

One step forward and one step back, but at least another thing that bothers most macadmins using chef can now be resolved as well.

But what if I could do something that Apple never thought of?

### Question 4 - Can I use this API to install a profile via Chef that requires installation from the MDM?
Formally USKEL, UAKEL is one of those features that has really pissed off macadmins and the companies they work for because of how it was introduced, deployed, delayed and now ultimately coming into production with the advent of UAMDM on 10.13.4.

Not only can you _not_ install a UAKEL profile with Chef, but even if you have MDM installed on your machine, the payload _must_ come from MDM.

But what would happen if you managed it with chef and shipped that profile up to MDM?

I decided to write `cpe_kernelextensions` and see if I could control what is now thought of as the first MDM-only profile.

I set my node overrides in chef:

```ruby
node.default['cpe_kernelextensions']['AllowUserOverrides'] = true
node.default['cpe_kernelextensions']['AllowedTeamIdentifiers'] = [
  'EQHXZ8M8AV',
]
```

Then I ran chef:

```ruby
sudo chef-client
Starting Chef Client, version 13.8.5

Recipe: cpe_profiles::default
  * cpe_profiles[Managing all of Configuration Profiles] action run
  Recipe: <Dynamically Defined Resource>
    * osx_profile[com.pinterest.profile.chef.kernelextensions] action install
      - install profile com.pinterest.profile.chef.kernelextensions
```

And sure enough...

![Chef MDM - Kernel Extensions](/images/2018/03/chef_mdm_kernel_extensions.png)

So now, I can dynamically control my kernel extensions profile with chef and actually have it install!


## Final Thoughts (for now) on C-MDM
Obviously this entire hack is around abusing systems that were never designed for this. This is purely a POC to inspire others. A lot of thought will need to be given to securely deploy a model like this, but my hope is in the coming days or weeks, I can outline my vision for how this middleware system could work.

Configuration-Mobile Device Management will more than likely be the future of MDM.

By having other MDM's create an API like this (MicroMDM, Jamf Pro, etc), we could create a a multi-configuration management, multi-mdm, open source middleware that could extend MDM far beyond anything even Apple envisions. MDM could truly become "Desired State" and not just "Well I hope this is the state I desire".

If you are interested in this model and would like to help me create this tool, please join me on the macadmin's slack at #cmdm

I hope to clean up the code a bit and post it on Github for others to look at, judge harshly and then work with me on making this into a real tool.


## Table Of Contents
* Do not remove this line (it will not be displayed)
{:toc}
