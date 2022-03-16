---
layout: post
author: Erik Gomez
title: "Introducing gnes - Reverse engineering the NetworkExtension API"
description: "Apple giveth, Apple taketh away"
tags: [Open Source, Swift, Xcode, Objective-C, Reverse Engineering, Headers, Python, PyObjC]
published: true
date: 2022-03-16 00:00:00
comments: true
---

Part of my old job and new job is ensuring that various pieces of software are installed, configured and if tampered with, maliciously or not, to bring it back into a desired state.

As of Big Sur and higher, EDR vendors have begun to implement Content Filter Network Extensions that pass all network traffic through it. Many of these vendors highly recommend implementing it in enterprise environments and it comes on as default. These network extensions try to block malicious activity before it happens while also trying to be mindful of the user's traffic, as it could contain private data.

# A somewhat deep dive into extension code

Unfortunately, we all know that things can go wrong when adding complexity. Whether it's an Apple bug in the System Extension code or just an unwelcome performance penalty, these vendors typically allow you to configure end-user devices to enable or disable this functionality.

One vendor in particular, CrowdStrike, has a documented process for enabling and disabling the filter.

Enabling
```shell
sudo /Applications/Falcon.app/Contents/Resources/falconctl enable-filter
Falcon network filter is enabled
```
Disabling
```shell
sudo /Applications/Falcon.app/Contents/Resources/falconctl disable-filter
Falcon network filter is disabled
```

Tools like [Chef Infra](https://github.com/chef/chef) allow you to write desired state functionality, but very often for situations where you must run a `shell` command, you have to figure out a way to only do this if the state has changed. Failure to do this will result in a non-idempontent chef configuration and can break tools like [ChefSpec](https://docs.chef.io/workstation/chefspec/).

Macadmins on the CrowdStrike slack channel had found that the following could return the state of the network filter.

```shell
sudo /Applications/Falcon.app/Contents/Resources/falconctl disable-filter
Falcon network filter is disabled

sudo defaults read "/Library/Application Support/CrowdStrike/Falcon/simplestore.plist" networkFilterEnabled
0

sudo /Applications/Falcon.app/Contents/Resources/falconctl enable-filter
Falcon network filter is enabled

sudo defaults read "/Library/Application Support/CrowdStrike/Falcon/simplestore.plist" networkFilterEnabled
1
```

While this is an OK method, I had concerns about trusting CrowdStrike to return its own health state. When discussing this issue with CrowdStrike, one of their engineers recommended the following.

```shell
sudo /Applications/Falcon.app/Contents/Resources/falconctl disable-filter
Falcon network filter is disabled

plutil -p /Library/Preferences/com.apple.networkextension.plist | grep falcon -A5 | grep Enabled
      "Enabled" => 0

sudo /Applications/Falcon.app/Contents/Resources/falconctl enable-filter
Falcon network filter is enabled

plutil -p /Library/Preferences/com.apple.networkextension.plist | grep falcon -A5 | grep Enabled
      "Enabled" => 1
```

I much preferred this method as this information was sourced directly from Apple. What I didn't like though was the multi `grep` and using `plutil`. For years Apple has warned that what is on disk in /Library/Preferences may not be what is actually applied, due to [cfprefsd](https://iphonedev.wiki/index.php/Preferences). When playing around with this in [macadmins python](https://github.com/macadmins/python) I realized the plist was in a very strange format.

```xml
<string>com.crowdstrike.falcon.App</string>
<dict>snipped</dict>
<dict>snipped</dict>
<string>CrowdStrike</string>
<string>com.crowdstrike.falcon.App</string>
<string>identifier "com.crowdstrike.falcon.Agent" and anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] /* exists */ and certificate leaf[field.1.2.840.113635.100.6.1.13] /* exists */ and certificate leaf[subject.OU] = X9E956P446</string>
<string>com.crowdstrike.falcon.Agent</string>
<string>com.crowdstrike.falcon.Agent</string>
<string>Falcon</string>
<dict>snipped</dict>
```

I had never seen a plist with multiple `<string>` elements in back to back lines, unless it was within an `<array>` element. I was able to work around it in 5 lines of code, but I snarkily wrote 7 lines of documentation explaining the terrible assumptions I was making in this code.

```python
#!/usr/local/bin/managed_python3
from Foundation import CFPreferencesCopyAppValue
# Everything is in a key of "$objects"
network_extensions = CFPreferencesCopyAppValue('$objects', '/Library/Preferences/com.apple.networkextension.plist')
for index, value in enumerate(network_extensions):
    # The key format is stupid here. Apple uses an array of dictionaries but also puts a string or strings before some of
    # the dictionaries to denote what tool it's configuration is, rather than use something sane like <key>
    # This condition grabs the current index, substracts one and compares it to the previous item in the array.
    # It checks to see if the previous entry was crowdstrike's bundle ID and also that the value returned is not a string
    # As Apple also has multiple string entries over and over in the array, which is not the data we need.
    if network_extensions[index-1] == 'com.crowdstrike.falcon.App' and not isinstance(value, str):
        # The key we care about is "Enabled" to understand if the content filter is currently loaded or not
        print(value.get('Enabled'))
```

But having Chef, which is written in Ruby, depend on Python just felt like the wrong approach. Luckily as of Chef 17.7.22, Chef now has a built-in method for using a [Ruby to ObjC bridge for CoreFoundation](https://github.com/chef/chef/pull/11898). With that bridge available, I [ported the python code into ruby and made it a dynamic function](https://github.com/uber/client-platform-engineering/blob/main/chef/cookbooks/uber_helpers/libraries/node_utils.rb#L737-L760) so we could use it for other Network Extensions, should the time come.

We were then able to hook into this [function directly in our crowdstrike code](https://github.com/uber/client-platform-engineering/blob/main/chef/cookbooks/cpe_crowdstrike_falcon_sensor/resources/cpe_crowdstrike_falcon_sensor.rb#L318-L334).

Life was great! But then we started seeing failures on some of our devices. Further investigation showed that this function failed when there were multiple content filters - typically due to unapproved VPNs. CFPreferences, or at least the bridge that the Progress team had written was failing, causing Chef runs to fail.

With a bit of a hint, I _hopped_ back to python, but this time tried via PyObjc:

```python
#!/usr/local/bin/managed_python3
from Foundation import NSBundle
NetworkExtension = NSBundle.bundleWithPath_('/System/Library/Frameworks/NetworkExtension.framework')
NEConfigurationManager = NetworkExtension.classNamed_('NEConfigurationManager')
manager = NEConfigurationManager.sharedManager()
err = manager.reloadFromDisk()
configs = manager.loadedConfigurations()

for index, key in enumerate(configs):
    config = configs[key]
    if config.application() == 'com.crowdstrike.falcon.App':
        print(config.contentFilter().isEnabled())
```

This looks _much_ better, is much more stable, but one of my original requirements was back to being a problem (ruby depending on python). I decided to take a look at what the Progress team did with [CoreFoundation](https://github.com/chef/corefoundation) and immediately noped my way off that cliff.

I started thinking about using `JXA` as other [macadmins](https://scriptingosx.com/2021/11/the-unexpected-return-of-javascript-for-automation/) have been discussing using this option, but I'm not too fond (or good) with javascript and the idea of shelling out to _another_ non-compiled language bothered me. It also felt like it was going to get [very complex](https://github.com/JXA-Cookbook/JXA-Cookbook/wiki/Using-Objective-C-%28ObjC%29-with-JXA#jxa-objc-bridge---the-fundamentals) very quickly for implementing an JXA to Objective-C bridge.

As someone decently versed in Swift these days, I figured that porting my PyObjC code to Swift would be pretty painless, given that so much of my Nudge-Python code easily ported to Swift.

I was absolutely wrong.

# The real journey
So right off the bat, things didn't look so good. Even though Swift had the `NetworkExtension` module already available, you couldn't just grab the class `NEConfigurationManager` from it.

```swift
import NetworkExtension

let NEConfigurationManager = NetworkExtension.classNamed("NEConfigurationManager")

ERROR: Module 'NetworkExtension' has no member named 'classNamed'
```

Swift has something similar to the PyObjC method where you can load a [bundle via the framework path](https://stackoverflow.com/a/58124538) so I decided to try loading the bundle itself, rather than the module Xcode offered. This would be similar to the PyObjC method.

```swift
import Foundation

if let NetworkExtensionBundle = Bundle(path: "/System/Library/Frameworks/NetworkExtension.framework") {
    print(NetworkExtensionBundle.load())
    let NEConfigurationManager: AnyClass? = NetworkExtensionBundle.classNamed("NEConfigurationManager")
    print(NEConfigurationManager as Any)
}

true
Optional(NEConfigurationManager)
Program ended with exit code: 0
```

Progress, but then we hit the next road block.

```swift
import Foundation

if let NetworkExtensionBundle = Bundle(path: "/System/Library/Frameworks/NetworkExtension.framework") {
    print(NetworkExtensionBundle.load())
    let NEConfigurationManager: AnyClass? = NetworkExtensionBundle.classNamed("NEConfigurationManager")
    print(NEConfigurationManager as Any)
    let manager = NEConfigurationManager?.sharedManager() as AnyObject?
}


ERROR: Value of type 'AnyClass' (aka 'AnyObject.Type') has no member 'sharedManager'
```

Because the compiler didn't know what `NEConfigurationManager` is, we had to force cast it to `AnyClass?` and now, the compiler has no idea that there is a sub class called `sharedManager()`. Force casting can be dangerous and commonly introduces issues like this.

If we add back the original `NetworkExtension` module we get _another_ error.

```swift
import Foundation
import NetworkExtension

if let NetworkExtensionBundle = Bundle(path: "/System/Library/Frameworks/NetworkExtension.framework") {
    print(NetworkExtensionBundle.load())
    let NEConfigurationManager: AnyClass? = NetworkExtensionBundle.classNamed("NEConfigurationManager")
    print(NEConfigurationManager as Any)
    let manager = NEConfigurationManager?.sharedManager() as AnyObject?
}

ERROR: Ambiguous use of 'sharedManager()'
```

When googling this error, essentially the compiler doesn't know what `sharedManager()` to use, because multiple modules have the same class name. Going back to the issue in the previous iteration, we had to force cast it to `AnyClass?` so we've muddled the waters.

I kept wondering if there was another class name I could use and stumbled upon this [stackoverflow](https://stackoverflow.com/a/35305698) that pointed to a way to print all of the available classes.

```swift
if let NetworkExtensionBundle = Bundle(path: "/System/Library/Frameworks/NetworkExtension.framework") {
    let NEConfigurationManager: AnyClass? = NetworkExtensionBundle.classNamed("NEConfigurationManager")
    var methodCount: UInt32 = 0
    let methodList = class_copyMethodList(NEConfigurationManager, &methodCount)

    for i in 0..<Int(methodCount) {
        let selName = sel_getName(method_getName(methodList![i]))
        let methodName = String(cString: selName, encoding: String.Encoding.utf8)!
        print(methodName)
    }
}
```

This gave me a bunch of classes via Xcode's stdout window.

```
dealloc
description
init
...
loadedConfigurations
...
reloadFromDisk
...

Program ended with exit code: 0
```

So I knew the functions I needed existed in the framework bundle via Swift, but I couldn't find a way to call them. More googling [lead me to an idea of calling the functions by their pointer](https://developer.apple.com/documentation/objectivec/1418771-class_getmethodimplementation_st?language=objc).

```swift
if let NetworkExtensionBundle = Bundle(path: "/System/Library/Frameworks/NetworkExtension.framework") {
    let NEConfigurationManager: AnyClass? = NetworkExtensionBundle.classNamed("NEConfigurationManager")
    let reloadFromDiskPointer = class_getMethodImplementation_stret(NEConfigurationManager, Selector(("reloadFromDisk")))
    let loadedConfigurationsPointer = class_getMethodImplementation_stret(NEConfigurationManager, "loadedConfigurations")
    print(reloadFromDiskPointer)
    print(loadedConfigurationsPointer)
}
```

This showed me where the objects were.

```
Optional(0x00007ff8196cdfd4)
Optional(0x00007ff8196df6a1)
Program ended with exit code: 0
```

With this, I thought I could call [method invoke](https://developer.apple.com/documentation/objectivec/1456726-method_invoke) and finally move on to finishing the code.

```swift
if let NetworkExtensionBundle = Bundle(path: "/System/Library/Frameworks/NetworkExtension.framework") {
    let NEConfigurationManager: AnyClass? = NetworkExtensionBundle.classNamed("NEConfigurationManager")
    let reloadFromDiskPointer = class_getMethodImplementation_stret(NEConfigurationManager, Selector(("reloadFromDisk")))
    let loadedConfigurationsPointer = class_getMethodImplementation_stret(NEConfigurationManager, "loadedConfigurations")
    print(reloadFromDiskPointer)
    print(loadedConfigurationsPointer)
    _ = method_invoke(NEConfigurationManager, reloadFromDiskPointer!)
}

ERROR: 'method_invoke' is unavailable: Variadic function is unavailable
```

Googling this lead me to another issue. This ObjC function, can accept `AnyObject`, [so it's defined as a variadic function](https://akrabat.com/wrapping-variadic-functions-for-use-in-swift/). To date, Swift cannot support [variadic C functions](https://developer.apple.com/forums/thread/666479). At this point I was pretty frustrated as I had wasted hours upon hours at night on something that I thought would be a 5 minute port.

It was pretty obvious to me that Apple didn't think we needed access to this functionality (or want us to have it) and the only way was to follow [another person's lead](https://blog.timac.org/2018/0717-macos-vpn-architecture/) who built an [open source VPN](https://blog.timac.org/2018/0719-vpnstatus/) that exposed small elements of the [headers](https://github.com/Timac/VPNStatus/blob/97e6932cfab86c3ec1dfddd7fdd3a633044a47ea/Common/ACDefines.h#L101-L114). 

> With this knowledge, it is easy to build a replacement for macOS built-in VPN Status menu. This application can use the NEConfigurationManager class from the private part of the NetworkExtension.framework in order to retrieve the NEConfiguration configurations.

Unfortunately for me, while this was helpful, his application was Objective-C. It was now obvious to me though. I needed to dump the headers and get what I needed from them.

# Stop hitting yourself
Long ago when writing the Untouchables series ([pt1](/2016/11/27/the-untouchables-apples-new-os-activation-for-touch-bar-macbook-pros/) and [pt2](2016/11/30/the-untouchables-pt-2-offline-touchbar-activation-with-a-purged-disk/)), I had learned about [otool](https://www.manpagez.com/man/1/otool/) and that was my first attempt at trying to understand the framework file.

```shell
otool -vt /Users/Shared/output/System/Library/Frameworks/NetworkExtension.framework/Versions/A/NetworkExtension

...
-[NEConfigurationManager reloadFromDisk].cold.1:
00007ff80f0a43b0	pushq	%rbp
00007ff80f0a43b1	movq	%rsp, %rbp
00007ff80f0a43b4	subq	$0x20, %rsp
00007ff80f0a43b8	movq	0x33730519(%rip), %rax
00007ff80f0a43bf	movq	(%rax), %rax
00007ff80f0a43c2	movq	%rax, -0x8(%rbp)
00007ff80f0a43c6	leaq	-0x20(%rbp), %r8
00007ff80f0a43ca	movl	$0x8400102, (%r8)               ## imm = 0x8400102
00007ff80f0a43d1	movq	%rdi, 0x4(%r8)
00007ff80f0a43d5	leaq	-0x1ce3dc(%rip), %rdi
00007ff80f0a43dc	leaq	0x55f2d(%rip), %rcx
00007ff80f0a43e3	pushq	$0x10
00007ff80f0a43e5	popq	%rdx
00007ff80f0a43e6	pushq	$0xc
00007ff80f0a43e8	popq	%r9
00007ff80f0a43ea	callq	0x7ff80f0e3160
00007ff80f0a43ef	movq	0x337304e2(%rip), %rax
00007ff80f0a43f6	movq	(%rax), %rax
00007ff80f0a43f9	cmpq	-0x8(%rbp), %rax
00007ff80f0a43fd	jne	0x7ff80f0a4405
00007ff80f0a43ff	addq	$0x20, %rsp
00007ff80f0a4403	popq	%rbp
00007ff80f0a4404	retq
00007ff80f0a4405	callq	0x7ff80f0e3148
...
-[NEConfiguration contentFilter]:
00007ff80eee7beb	pushq	%rbp
00007ff80eee7bec	movq	%rsp, %rbp
00007ff80eee7bef	movl	$0x58, %edx
00007ff80eee7bf4	movl	$0x1, %ecx
00007ff80eee7bf9	popq	%rbp
00007ff80eee7bfa	jmp	0x7ff80f0e37ea
```

With this information I could again see the pointers of the functions, but it's not really useful for my purposes. I tried [another tool](https://github.com/nst/RuntimeBrowser) to no avail as the framework wasn't even available. My next thought was that Apple provides headers in the Xcode bundle itself. For macOS it is located at `/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk`

```shell
ls -1 /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/NetworkExtension.framework/Versions/A/Headers
NEAppProxyFlow.h
NEAppProxyProvider.h
NEAppProxyProviderManager.h
NEAppProxyTCPFlow.h
NEAppProxyUDPFlow.h
NEAppPushManager.h
NEAppPushProvider.h
NEAppRule.h
NEDNSProxyManager.h
NEDNSProxyProvider.h
NEDNSProxyProviderProtocol.h
NEDNSSettings.h
NEDNSSettingsManager.h
NEFilterControlProvider.h
NEFilterDataProvider.h
NEFilterFlow.h
NEFilterManager.h
NEFilterPacketProvider.h
NEFilterProvider.h
NEFilterProviderConfiguration.h
NEFilterRule.h
NEFilterSettings.h
NEFlowMetaData.h
NEHotspotConfigurationManager.h
NEHotspotHelper.h
NEHotspotNetwork.h
NEIPv4Settings.h
NEIPv6Settings.h
NENetworkRule.h
NEOnDemandRule.h
NEPacket.h
NEPacketTunnelFlow.h
NEPacketTunnelNetworkSettings.h
NEPacketTunnelProvider.h
NEProvider.h
NEProxySettings.h
NETransparentProxyManager.h
NETransparentProxyNetworkSettings.h
NETransparentProxyProvider.h
NETunnelNetworkSettings.h
NETunnelProvider.h
NETunnelProviderManager.h
NETunnelProviderProtocol.h
NETunnelProviderSession.h
NEVPNConnection.h
NEVPNManager.h
NEVPNProtocol.h
NEVPNProtocolIKEv2.h
NEVPNProtocolIPSec.h
NWBonjourServiceEndpoint.h
NWEndpoint.h
NWHostEndpoint.h
NWPath.h
NWTCPConnection.h
NWTLSParameters.h
NWUDPSession.h
NetworkExtension.apinotes
NetworkExtension.h
```

You can also see these headers on [alexy lysuik's github repo](https://github.com/alexey-lysiuk/macos-sdk/tree/master/MacOSX12.1.sdk/System/Library/Frameworks/NetworkExtension.framework/Versions/A/Headers). Unfortunately these headers didn't have the functions I needed. In fact it looked like these were the headers Xcode itself used for the compiler, aka my original issue :). But with this, I at least knew what the format needed to look like.

Googling more lead me to [this link](https://developer.limneos.net/index.php?ios=12.1&framework=NetworkExtension.framework&header=NEConfigurationManager.h) which I found very interesting. This header contained practically all of the information I needed, but it was for iOS 12. More importantly though was one of the first lines.

```shell
* This header is generated by classdump-dyld 1.0
```

This lead me down a new, very interesting path. The [iphone dev wiki](https://iphonedev.wiki/index.php/Reverse_Engineering_Tools#Class.2FMetadata_Dumping_tools) has a treasure trove of class/header dumping tools. Of course, as is always the case with macOS, most of these tools were really only designed to work on iOS.

[Since iOS 3.1](https://iphonedev.wiki/index.php/Dyld_shared_cache), Apple had moved to a cache file to improve performance. This feature finally came to macOS with the introduction of Big Sur. You can see these cache files within `/System/Library/dyld/` (dyld_shared_cache_x86_64 for Intel, dyld_shared_cache_arm64e for Apple Silicon).

[classdump-dyld](https://github.com/limneos/classdump-dyld) development seems to have stalled and doesn't support modern macOS versions, so I went looking for alternatives. I found a [macOS headers repo](https://github.com/w0lfschild/macOS_headers/tree/master/tools), but the headers were out of date and I didn't want to use them, even though they looked potentially viable. I wish I had read [issue 3](https://github.com/w0lfschild/macOS_headers/issues/3) at the time, but stopped immediately at [issue 5](https://github.com/w0lfschild/macOS_headers/issues/5). More info on this in a second.

As I continued down the litany of `classdymp-dyld` forks I found [this one](https://github.com/freedomtan/classdump-dyld) that looked promising as it even had Apple M1 support. I cloned the repo, quickly ran `make all` and hoped for the best.

There were several interesting arguments you could pass.

```bash
# Dumps everything
./classdump-dyld -o outdir -c

   Now dumping /System/Library/dyld/dyld_shared_cache_x86_64...


   Finished dumping /System/Library/dyld/dyld_shared_cache_x86_64...

  Done. Check "outdir" directory.
```

This shockingly resulted in nothing. Not even the `output` folder

```shell
# Dumps all frameworks from the following folder
./classdump-dyld -o outdir -r /System/Library/Frameworks/
...
  Dumping /System/Library/Frameworks/NetworkExtension.framework/PlugIns/NEIKEv2Provider.appex/Contents/MacOS/NEIKEv2Provider...(1 classes)
...
  Done. Check "outdir" directory.
```

No headers for what I wanted.

```shell
# Dumps just the framework we want
./classdump-dyld -o outdir -r /System/Library/Frameworks/NetworkExtension.framework/
  Dumping /System/Library/Frameworks/NetworkExtension.framework/PlugIns/NEIKEv2Provider.appex/Contents/MacOS/NEIKEv2Provider...(1 classes)
  Done. Check "outdir" directory.
```

Nothing. Not a single header. :( I googled around and found some links to building Apple's open source tool [dsc_extractor](https://opensource.apple.com/source/dyld/dyld-433.5/launch-cache/dsc_extractor.cpp.auto.html) (more info below) and then tried the original classdump on the extracted binary but again, nothing.

```shell
./classdump -o outdir -r ./dsc_extracted/System/Library/Frameworks/NetworkExtension.framework/Versions/A/NetworkExtension
  Done. Check "outdir" directory.
```

I was about to give up when I started looking author's [open issues](https://github.com/freedomtan/classdump-dyld/issues/3) again. Maybe it works on Big Sur? My wife is pretty slow at installing updates and she was still on macOS Big Sur 11.6, so with a little coercing, she handed me her laptop and I performed the same commands. Both times `-r` failed but `-c`...

```bash
# Dumps everything
./classdump-dyld -o outdir -c
...
  Dumping /System/Library/Frameworks/NetworkExtension.framework/Versions/A/NetworkExtension...(291 classes) (14%)

  Done. Check "outdir" directory.

ls -1 ./outdir/NetworkExtension.framework/Versions/A/NetworkExtension
CXNetworkExtensionVoIPXPCClient.h
NEAOVPN.h
NEAOVPNException.h
NEAOVPNNetworkAgent.h
NEAccountIdentifiers.h
NEAgentAppProxyExtension.h
NEAgentAppPushExtension.h
NEAgentDNSProxyExtension.h
NEAgentExtension.h
NEAgentFilterExtension.h
NEAgentPacketTunnelExtension.h
NEAgentSessionDelegate.h
NEAgentTunnelExtension.h
NEAppInfo.h
NEAppInfoCache.h
NEAppProxyFlow.h
NEAppProxyProvider.h
NEAppProxyProviderContainer.h
NEAppProxyProviderManager.h
NEAppProxyTCPFlow.h
NEAppProxyUDPFlow.h
NEAppPush.h
NEAppPushCallKitXPCClient.h
NEAppPushManager.h
NEAppPushPluginDriver.h
NEAppPushProvider.h
NEAppRule.h
NEAppSidecarPolicySession.h
NEAppVPNNetworkAgent.h
NEBundleProxy.h
NEByteParser.h
NEConfiguration.h
NEConfigurationCommandHandling.h
NEConfigurationLegacySupport.h
NEConfigurationManager.h
NEConfigurationValidating.h
NEContentFilter.h
NEContentFilterNetworkAgent.h
NEDNSOverHTTPSSettings.h
NEDNSOverTLSSettings.h
NEDNSPacket.h
NEDNSProxy.h
NEDNSProxyManager.h
NEDNSProxyPluginDriver.h
NEDNSProxyProvider.h
NEDNSProxyProviderProtocol.h
NEDNSQuery.h
NEDNSResourceRecord.h
NEDNSSettings.h
NEDNSSettingsBundle.h
NEDNSSettingsManager.h
NEDNSSettingsNetworkAgent.h
NEEvaluateConnectionRule.h
NEExtensionAppProxyProviderContext.h
NEExtensionAppProxyProviderHostContext.h
NEExtensionAppProxyProviderHostDelegate.h
NEExtensionAppProxyProviderHostProtocol.h
NEExtensionAppProxyProviderProtocol.h
NEExtensionAppPushProviderContext.h
NEExtensionAppPushProviderHostContext.h
NEExtensionAppPushProviderHostDelegate.h
NEExtensionAppPushProviderHostProtocol.h
NEExtensionAppPushProviderProtocol.h
NEExtensionDNSProxyProviderContext.h
NEExtensionDNSProxyProviderHostContext.h
NEExtensionDNSProxyProviderProtocol.h
NEExtensionPacketTunnelProviderContext.h
NEExtensionPacketTunnelProviderHostContext.h
NEExtensionPacketTunnelProviderHostProtocol.h
NEExtensionPacketTunnelProviderProtocol.h
NEExtensionProviderContext.h
NEExtensionProviderHostContext.h
NEExtensionProviderHostDelegate.h
NEExtensionProviderHostProtocol.h
NEExtensionProviderProtocol.h
NEExtensionTunnelProviderContext.h
NEExtensionTunnelProviderHostContext.h
NEExtensionTunnelProviderHostDelegate.h
NEExtensionTunnelProviderHostProtocol.h
NEExtensionTunnelProviderProtocol.h
NEFileHandle.h
NEFileHandleMaintainer.h
NEFilterAbsoluteVerdict.h
NEFilterBlockPage.h
NEFilterBrowserFlow.h
NEFilterControlExtensionProviderContext.h
NEFilterControlExtensionProviderHostContext.h
NEFilterControlExtensionProviderHostProtocol.h
NEFilterControlExtensionProviderProtocol.h
NEFilterControlProvider.h
NEFilterControlVerdict.h
NEFilterDataExtensionProviderContext.h
NEFilterDataExtensionProviderHostContext.h
NEFilterDataExtensionProviderHostProtocol.h
NEFilterDataExtensionProviderProtocol.h
NEFilterDataProvider.h
NEFilterDataSavedMessageHandler.h
NEFilterDataVerdict.h
NEFilterExtensionProviderContext.h
NEFilterExtensionProviderHostContext.h
NEFilterExtensionProviderHostDelegate.h
NEFilterExtensionProviderHostProtocol.h
NEFilterExtensionProviderProtocol.h
NEFilterFlow.h
NEFilterManager.h
NEFilterNewFlowVerdict.h
NEFilterPacketContext.h
NEFilterPacketExtensionProviderContext.h
NEFilterPacketExtensionProviderHostContext.h
NEFilterPacketExtensionProviderHostProtocol.h
NEFilterPacketInterpose.h
NEFilterPacketProvider.h
NEFilterPluginDriver.h
NEFilterProvider.h
NEFilterProviderConfiguration.h
NEFilterRemediationVerdict.h
NEFilterReport.h
NEFilterRule.h
NEFilterSettings.h
NEFilterSocketFlow.h
NEFilterSource.h
NEFilterVerdict.h
NEFlowDivertFileHandle.h
NEFlowDivertPluginDriver.h
NEFlowMetaData.h
NEFlowNexus.h
NEHasher.h
NEHelper.h
NEHotspotConfiguration.h
NEHotspotConfigurationHelper.h
NEHotspotConfigurationManager.h
NEHotspotEAPSettings.h
NEHotspotHS20Settings.h
NEHotspotHelper.h
NEHotspotHelperCommand.h
NEHotspotHelperResponse.h
NEHotspotNetwork.h
NEIKEv2ASN1DNIdentifier.h
NEIKEv2AddressAttribute.h
NEIKEv2AddressIdentifier.h
NEIKEv2AddressList.h
NEIKEv2AppVersionAttribute.h
NEIKEv2AuthPayload.h
NEIKEv2AuthenticationProtocol.h
NEIKEv2CertificatePayload.h
NEIKEv2CertificateRequestPayload.h
NEIKEv2ChildSA.h
NEIKEv2ChildSAConfiguration.h
NEIKEv2ChildSAPayload.h
NEIKEv2ChildSAProposal.h
NEIKEv2ConfigPayload.h
NEIKEv2ConfigurationAttribute.h
NEIKEv2ConfigurationDelegate.h
NEIKEv2ConfigurationMessage.h
NEIKEv2CreateChildPacket.h
NEIKEv2Crypto.h
NEIKEv2CustomData.h
NEIKEv2CustomPayload.h
NEIKEv2DHKeys.h
NEIKEv2DHProtocol.h
NEIKEv2DNSDomainAttribute.h
NEIKEv2DeleteChildContext.h
NEIKEv2DeleteIKEContext.h
NEIKEv2DeletePayload.h
NEIKEv2EAP.h
NEIKEv2EAPPayload.h
NEIKEv2EAPProtocol.h
NEIKEv2ESPSPI.h
NEIKEv2EncryptedFragmentPayload.h
NEIKEv2EncryptedPayload.h
NEIKEv2EncryptionProtocol.h
NEIKEv2FQDNIdentifier.h
NEIKEv2Helper.h
NEIKEv2IKEAuthPacket.h
NEIKEv2IKESA.h
NEIKEv2IKESAConfiguration.h
NEIKEv2IKESAInitPacket.h
NEIKEv2IKESAPayload.h
NEIKEv2IKESAProposal.h
NEIKEv2IKESPI.h
NEIKEv2IPv4AddressAttribute.h
NEIKEv2IPv4DHCPAttribute.h
NEIKEv2IPv4DNSAttribute.h
NEIKEv2IPv4NetmaskAttribute.h
NEIKEv2IPv4PCSCFAttribute.h
NEIKEv2IPv4SubnetAttribute.h
NEIKEv2IPv6AddressAttribute.h
NEIKEv2IPv6DHCPAttribute.h
NEIKEv2IPv6DNSAttribute.h
NEIKEv2IPv6PCSCFAttribute.h
NEIKEv2IPv6SubnetAttribute.h
NEIKEv2Identifier.h
NEIKEv2IdentifierPayload.h
NEIKEv2InformationalContext.h
NEIKEv2InformationalPacket.h
NEIKEv2InitiatorIdentifierPayload.h
NEIKEv2InitiatorTrafficSelectorPayload.h
NEIKEv2InitiatorTransportIPv6Address.h
NEIKEv2IntegrityProtocol.h
NEIKEv2KeyExchangePayload.h
NEIKEv2KeyIDIdentifier.h
NEIKEv2Listener.h
NEIKEv2MOBIKE.h
NEIKEv2MOBIKEContext.h
NEIKEv2NewChildContext.h
NEIKEv2NoncePayload.h
NEIKEv2NotifyPayload.h
NEIKEv2PRFProtocol.h
NEIKEv2Packet.h
NEIKEv2PacketReceiver.h
NEIKEv2PacketTunnelProvider.h
NEIKEv2Payload.h
NEIKEv2PrivateNotify.h
NEIKEv2RTT.h
NEIKEv2Rekey.h
NEIKEv2RekeyChildContext.h
NEIKEv2RekeyIKEContext.h
NEIKEv2RequestContext.h
NEIKEv2ResponderIdentifierPayload.h
NEIKEv2ResponderTrafficSelectorPayload.h
NEIKEv2ResponderTransportIPv6Address.h
NEIKEv2ResponseConfigPayload.h
NEIKEv2SPI.h
NEIKEv2Server.h
NEIKEv2Session.h
NEIKEv2SessionConfiguration.h
NEIKEv2SignatureHashProtocol.h
NEIKEv2StringAttribute.h
NEIKEv2SubnetAttribute.h
NEIKEv2SupportedAttribute.h
NEIKEv2TrafficSelector.h
NEIKEv2TrafficSelectorPayload.h
NEIKEv2Transport.h
NEIKEv2TransportClient.h
NEIKEv2TransportDelegate.h
NEIKEv2UserFQDNIdentifier.h
NEIKEv2VendorData.h
NEIKEv2VendorIDPayload.h
NEIPC.h
NEIPCWrapper.h
NEIPSecSA.h
NEIPSecSAKernelSession.h
NEIPSecSALocalSession.h
NEIPSecSASession.h
NEIPSecSASessionDelegate.h
NEIPsecNexus.h
NEIPv4Route.h
NEIPv4Settings.h
NEIPv6Route.h
NEIPv6Settings.h
NEIdentityKeychainItem.h
NEInternetNexus.h
NEKeychainItem.h
NELaunchServices.h
NELoopbackConnection.h
NENetworkAgent.h
NENetworkAgentRegistrationFileHandle.h
NENetworkRule.h
NENexus.h
NENexusAgent.h
NENexusAgentDelegate.h
NENexusBrowse.h
NENexusFlow.h
NENexusFlowAssignedProperties.h
NENexusFlowDivertFlow.h
NENexusFlowManager.h
NENexusPathFlow.h
NEOnDemandRule.h
NEOnDemandRuleConnect.h
NEOnDemandRuleDisconnect.h
NEOnDemandRuleEvaluateConnection.h
NEOnDemandRuleIgnore.h
NEPacket.h
NEPacketTunnelFlow.h
NEPacketTunnelNetworkSettings.h
NEPacketTunnelProvider.h
NEPathController.h
NEPathControllerNetworkAgent.h
NEPathEvent.h
NEPathEventObserver.h
NEPathRule.h
NEPluginDriver.h
NEPolicy.h
NEPolicyCondition.h
NEPolicyResult.h
NEPolicyRouteRule.h
NEPolicySession.h
NEPolicySessionFileHandle.h
NEPrettyDescription.h
NEProcessIdentity.h
NEProcessInfo.h
NEProfileIngestion.h
NEProfileIngestionDelegate.h
NEProfileIngestionPayloadInfo.h
NEProfilePayloadAOVPN.h
NEProfilePayloadBase.h
NEProfilePayloadBaseDelegate.h
NEProfilePayloadBaseVPN.h
NEProfilePayloadContentFilter.h
NEProfilePayloadHandlerDelegate.h
NEProvider.h
NEProviderAppConfigurationClient.h
NEProviderServer.h
NEProviderXPCListener.h
NEProvider_Subsystem.h
NEProxyConfigurationNetworkAgent.h
NEProxyServer.h
NEProxySettings.h
NETransparentProxyManager.h
NETransparentProxyNetworkSettings.h
NETransparentProxyProvider.h
NETunnelNetworkSettings.h
NETunnelProvider.h
NETunnelProviderManager.h
NETunnelProviderProtocol.h
NETunnelProviderSession.h
NEUserNotification.h
NEUtilConfigurationClient.h
NEVPN.h
NEVPNApp.h
NEVPNConnection.h
NEVPNIKEv1ProposalParameters.h
NEVPNIKEv2SecurityAssociationParameters.h
NEVPNManager.h
NEVPNNetworkAgent.h
NEVPNPluginDriver.h
NEVPNProtocol.h
NEVPNProtocolIKEv2.h
NEVPNProtocolIPSec.h
NEVPNProtocolL2TP.h
NEVPNProtocolPPP.h
NEVPNProtocolPPTP.h
NEVPNProtocolPlugin.h
NSCopying.h
NSExtensionRequestHandling.h
NSObject.h
NSSecureCoding.h
NSXPCListenerDelegate.h
NWNetworkAgent.h
NWTLSParameters.h
NetworkExtension-Structs.h
NetworkExtension.h
PKModularService.h
```

Yessssssssss! I finally had headers! Now I could start learning the next part.

# Adding headers to a swift project
So now I had the headers, but what do I actually do with them?

[Apple](https://developer.apple.com/documentation/swift/imported_c_and_objective-c_apis/importing_objective-c_into_swift) has some pretty good documentation for this. Essentially when you add a header file into your swift Application, Xcode will politely ask if you want to create an Objective-C bridging header.

![Importing Objective C into Swift App](/images/2022/gnes/swift-ImportingObjC-1.png)

![Swift ObjectiveC header](/images/2022/gnes/swift-ImportingObjC-2.png)

I also found [this blog post](https://medium.com/@subhangdxt/bridging-objective-c-and-swift-classes-5cb4139d9c80) pretty informative. With these sets of data, I was on my way. I knew I didn't need all of the headers that `classdump-dyld` provided, but just the types of data I needed and the particular classes the PyObjC code used.

At the very least, I knew I needed data from the following headers:
- NEConfiguration.h - Where all the core information is relating to the types of NetworkExtension configurations
- NEConfigurationManager.h - The classes where loading the configurations were
- NEContentFilter.h - The first type of Network Extension and the one I mainly cared about
- NEDNSProxy.h - The second type of Network Extension
- NEVPN.h - The third type of Network Extension
- NEProfileIngestionPayloadInfo.h - Parts of the data for the Network Extensions config that comes via MDM
- NEProfilePayloadHandlerDelegate.h - Parts of the data for the Network Extensions to handle the mdm payload

The bridging header needed to consume the primary headers.

```objc
//
//  Use this file to import your target's public headers that you would like to expose to Swift.
//

#import "NEConfigurationManager.h"
#import "NEProfileIngestionPayloadInfo.h"
#import "NEContentFilter.h"
#import "NEVPN.h"
#import "NEDNSProxy.h"
```

`NEConfigurationManager` needed to consume the configuration header but also had some standard classes that would only come from cocoa.

```objc
//

#import <Cocoa/Cocoa.h>
#import "NEConfiguration.h"
```

The profile ingestor header would need to consume the payload header.

```objc
//

#import "NEProfilePayloadHandlerDelegate.h"
```

Note that these imports were already defined, but using Apple's internal paths. I had to modify these to use the paths within my swift bundle. And with that, the original swift code could finally look comparable to the pyobjc code!

Again, here's the python code.

```python
from Foundation import NSBundle

NetworkExtension = NSBundle.bundleWithPath_('/System/Library/Frameworks/NetworkExtension.framework')
NEConfigurationManager = NetworkExtension.classNamed_('NEConfigurationManager')
manager = NEConfigurationManager.sharedManager()
err = manager.reloadFromDisk()
configs = manager.loadedConfigurations()
```

And now the swift code.

```swift
import Foundation
import NetworkExtension

let sharedManager = NEConfigurationManager.self.shared() // sharedManager() was deprecated to shared() in Swift
_ = sharedManager?.reloadFromDisk() // identical call like pyobjc
let loadedConfigurations = sharedManager?.loadedConfigurations // identical call like pyobjc without the ()
```

Finally I had something, but sadly it wasn't over.

# Swift types
I want to preface this by saying I am still learning this aspect of Swift and everything you will read in this section could be wrong. Please correct me if that is indeed the case and there is a better way to do this.

In PyObjC, once we had the loaded configurations we could loop through them with a simple for loop.

```python
if configs:
    for index, key in enumerate(configs):
        config = configs[key]
        if config.application() == identifier:
            enabled = config.contentFilter().isEnabled()
```

In swift, `loadedConfigurations` is a type of `NEConfigurationManager` which you cannot for loop. To solve this, we have to force cast the value as a `NSDictionary`. Once we do this though, the values of this dictionary become `AnyObject` and we lose the built in property of `NEConfiguration`. To solve for this, we have to again force cast these to the data we need, so we can use the other built-in logic that Swift handles for us.

```swift
if loadedConfigurations != nil {
  for (_, value) in loadedConfigurations! as NSDictionary { // Force cast NEConfigurationManager to NSDictionary
    let config = value as! NEConfiguration // Force cast to AnyObject to NEConfiguration
    if config.application == identifier {
      if (config.contentFilter != nil) {
        enabled = (config.contentFilter.enabled != 0) // isEnabled was changed to enabled in Swift
      }
    }
  }
}
```

While this is a bit more verbose/obtuse, this is identical code. We now have a working POC! There's a lot of other dragons to contend with, like other data having to be force casted, some keys not "existing" even with the headers extracted, but overall, this is exactly what I had to do to get working Swift code.

That leaves us to the best part of the blog.
# Introducing gnes (G Ness - Get Network Extension Status)
While I told myself I would never open source another tool, I have. I kind of had to. [gnes](https://github.com/erikng/gnes) is a Swift 5, Objective-C binary that has several options.

```shell
NAME
     gnes – Get Network Extension Status

SYNOPSIS
     gnes -debug [-identifier identifier] [-type type] output

DESCRIPTION
     The gnes command is used to read and print network extension status

OPTIONS
     The options are as follows:

     -debug
             Optional: Returns all found bundle identifiers and type if passed identifier is not found

     -identifier
             Required: The bundle identifier of the network extension to query

     -type
             Required: The type of network extension you are querying. Needed when an application installs multiple network extensions with the same bundle identifier
                "contentFilter", "dnsProxy", "vpn"

     output
            Optional: Specific output formats:
                -stdout-xml -stdout-json -stdout-enabled -stdout-raw
```

If for instance you just want to know if a NetworkExtension is enabled/disabled you can run the following:

```shell
sudo /Applications/Falcon.app/Contents/Resources/falconctl disable-filter
Falcon network filter is disabled

gnes -identifier "com.crowdstrike.falcon.App" -type contentFilter -stdout-enabled
false

sudo /Applications/Falcon.app/Contents/Resources/falconctl enable-filter
Falcon network filter is enabled

gnes -identifier "com.crowdstrike.falcon.App" -type contentFilter -stdout-enabled
true
```

This again has the benefit of getting this data directly from Apple, rather than trusting a vendor's implementation of this data. Since it reads the configuration in real-time, it is always fully up-to-date.

If you wanted the entire configuration of the extension you could run `gnes -identifier "com.crowdstrike.falcon.App" -type contentFilter -stdout-json`.

```json
{
  "application" : "com.crowdstrike.falcon.App",
  "applicationName" : "Falcon",
  "contentFilter" : {
    "enabled" : true,
    "filterGrade" : 1,
    "provider" : {
      "dataProviderBundleIdentifier" : "com.crowdstrike.falcon.Agent",
      "dataProviderDesignatedRequirement" : "identifier \"com.crowdstrike.falcon.Agent\" and anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] \/* exists *\/ and certificate leaf[field.1.2.840.113635.100.6.1.13] \/* exists *\/ and certificate leaf[subject.OU] = X9E956P446",
      "filterPackets" : false,
      "filterSockets" : true,
      "organization" : "CrowdStrike",
      "packetProviderBundleIdentifier" : "com.crowdstrike.falcon.Agent",
      "pluginType" : "com.crowdstrike.falcon.App",
      "preserveExistingConnections" : false
    }
  },
  "grade" : 1,
  "identifier" : "CD150001-EE65-447B-9251-B32D6CF828B7",
  "name" : "Falcon",
  "payloadInfo" : {
    "isSetAside" : false,
    "payloadOrganization" : "GitHub",
    "payloadUUID" : "8EF5C132-BEB4-499E-BEE3-07CF4361780F",
    "profileIdentifier" : "10D24B0A-2F2A-4F96-80FA-7A435D65981A",
    "profileIngestionDate" : "2022-03-08 00:00:00 -0000",
    "profileSource" : "mdm",
    "profileUUID" : "58417554-8EAB-4DF5-A2FB-D13AF9DC4042",
    "systemVersion" : "Version 12.2.1 (Build 21D62)"
  },
  "type" : "contentFilter"
}
```

If for some reason you like plists over json, `gnes` supports that as well with the `-stdout-xml` argument.

```xml
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
    <dict>
        <key>application</key>
        <string>com.crowdstrike.falcon.App</string>
        <key>applicationName</key>
        <string>Falcon</string>
        <key>contentFilter</key>
        <dict>
            <key>enabled</key>
            <true/>
            <key>filterGrade</key>
            <integer>1</integer>
            <key>provider</key>
            <dict>
                <key>dataProviderBundleIdentifier</key>
                <string>com.crowdstrike.falcon.Agent</string>
                <key>dataProviderDesignatedRequirement</key>
                <string>identifier "com.crowdstrike.falcon.Agent" and anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] /* exists */ and certificate leaf[field.1.2.840.113635.100.6.1.13] /* exists */ and certificate leaf[subject.OU] = X9E956P446</string>
                <key>filterPackets</key>
                <false/>
                <key>filterSockets</key>
                <true/>
                <key>organization</key>
                <string>CrowdStrike</string>
                <key>packetProviderBundleIdentifier</key>
                <string>com.crowdstrike.falcon.Agent</string>
                <key>pluginType</key>
                <string>com.crowdstrike.falcon.App</string>
                <key>preserveExistingConnections</key>
                <false/>
            </dict>
        </dict>
        <key>grade</key>
        <integer>1</integer>
        <key>identifier</key>
        <string>F5CF37FF-AD81-478A-BC44-158E0C098F9B</string>
        <key>name</key>
        <string>Falcon</string>
        <key>payloadInfo</key>
        <dict>
            <key>isSetAside</key>
            <false/>
            <key>payloadOrganization</key>
            <string>GitHub</string>
            <key>payloadUUID</key>
            <string>B477FCD3-BB72-4C65-9C81-CB54913C8D2B</string>
            <key>profileIdentifier</key>
            <string>40EC65F4-D642-44E7-89A8-B7F84D25BD79</string>
            <key>profileIngestionDate</key>
            <string>2022-03-08 00:00:00 -0000</string>
            <key>profileSource</key>
            <string>mdm</string>
            <key>profileUUID</key>
            <string>6A26A255-51BF-493C-8BC9-4DA9F01CEF6D</string>
            <key>systemVersion</key>
            <string>Version 12.2.1 (Build 21D62)</string>
        </dict>
        <key>type</key>
        <string>contentFilter</string>
    </dict>
</plist>
```

And finally, If you don't know what extension type you have installed or the identifier of the one you want to target, you can use the `-debug` argument.

```shell
gnes -identifier "com.example.fake.contentFilter" -type contentFilter -debug
Did not find network extension!
{
  "contentFilter" : [
    "com.crowdstrike.falcon.App",
    "com.cisco.anyconnect.macos.acsock"
  ],
  "dnsProxy" : [
    "com.cisco.anyconnect.macos.acsock"
  ],
  "unknown" : [

  ],
  "vpn" : [
    "com.cisco.anyconnect.macos.acsock"
  ]
}
```

A [future version of the tool](https://github.com/erikng/gnes/issues/1) will just return all extension data in either plist or json format, allowing your other tools to parse the data, rather than only returning specific filters.

Further optimization can likely be done with the headers like [combining them into a single file](https://github.com/udevsharold/airkeeper/blob/master/PrivateHeaders.h). There's also likely some [gotchas](https://swiftrocks.com/be-careful-with-objc-bridging-in-swift) with the objc bridge and clearly some optimization that needs to happen in the gnes code, but it at least we have something now that works.

I may also attempt to sign/notarize and package it for easier distribution and at Uber we plan on using this as a drop-in replacement for our [network extension code in the crowdstrike cookbook](https://github.com/uber/client-platform-engineering/blob/main/chef/cookbooks/cpe_crowdstrike_falcon_sensor) that we know has some issues.

# The state of class dumping on macOS
To be frank, it appears to be dying. You can [find lots of people](https://mjtsai.com/blog/2020/06/26/reverse-engineering-macos-11-0/) complaining about this since 2020.

> Incidentally, the new stripped framework cache on macOS 11 is horrendous for disassembly. If you’re trying to track down why there’s a bug in your app, or how a system implementation works, you are screwed. - [Steve Troughton-Smith](https://twitter.com/stroughtonsmith/status/1275898134942691330)

There are other [useful iOS header sources](https://headers.cynder.me/index.php?sdk=iOS15&fw=Frameworks/NetworkExtension.framework) that used other tools like [ktool](https://github.com/cxnder/ktool) but as of just a few days ago the author didn't think he could [ever support macOS Monterey](https://github.com/cxnder/ktool/issues/35). People who have [tried to maintain headers](https://github.com/LeoNatan/Apple-Runtime-Headers/) rely on these tools to work. [Older tools](https://github.com/nygard/class-dump) and their various forks do not work.

Tools like [DyldExtractor](https://github.com/arandomdev/DyldExtractor/issues/33) suffer the same fate. Alternative tools like [dsdump](https://github.com/DerekSelander/dsdump/issues/20) aren't really designed for creating header files and even [forks](https://github.com/paradiseduo/dsdump) or [new tools](https://github.com/paradiseduo/resymbol) based on `dsdump` still don't work on Monterey.

Tools like [dyld-shared-cache-extractor](https://github.com/keith/dyld-shared-cache-extractor) get us halfway there, but then you hit a roadblock (as mentioned above regarding `ktool`).

```python
./dyld-shared-cache-extractor /System/Library/dyld/dyld_shared_cache_x86_64 ./libraries
...
dsdump --objc --verbose=5 /System/Library/Frameworks/NetworkExtension.framework/Versions/A/NetworkExtension
nothing!
...
→ ktool dump --headers --out ./output ./libraries/System/Library/Frameworks/NetworkExtension.framework/Versions/A/NetworkExtension
Traceback (most recent call last):
  File "/usr/local/bin/ktool", line 8, in <module>
    sys.exit(main())
  File "/usr/local/lib/python3.9/site-packages/ktool/ktool_script.py", line 387, in main
    args.func(args)
  File "/usr/local/lib/python3.9/site-packages/ktool/ktool_script.py", line 915, in dump
    objc_image = ktool.load_objc_metadata(image)
  File "/usr/local/lib/python3.9/site-packages/ktool/ktool.py", line 125, in load_objc_metadata
    return ObjCImage.from_image(image)
  File "/usr/local/lib/python3.9/site-packages/ktool/objc.py", line 130, in from_image
    cat_prot_queue.go()
  File "/usr/local/lib/python3.9/site-packages/ktool/util.py", line 104, in go
    self.returns = [self.process_item(item) for item in self.items]
  File "/usr/local/lib/python3.9/site-packages/ktool/util.py", line 104, in <listcomp>
    self.returns = [self.process_item(item) for item in self.items]
  File "/usr/local/lib/python3.9/site-packages/ktool/util.py", line 94, in process_item
    return item.func(*item.args)
  File "/usr/local/lib/python3.9/site-packages/ktool/objc.py", line 910, in from_image
    loc = objc_image.get_int_at(category_ptr, 8, vm=True)
  File "/usr/local/lib/python3.9/site-packages/ktool/objc.py", line 186, in get_int_at
    return self.image.get_int_at(offset, length, vm, sectname)
  File "/usr/local/lib/python3.9/site-packages/ktool/dyld.py", line 205, in get_int_at
    offset = self.vm.get_file_address(offset, section_name)
  File "/usr/local/lib/python3.9/site-packages/ktool/macho.py", line 289, in get_file_address
    raise ValueError(f'Address {hex(vm_address)} couldn\'t be found in vm address set')
ValueError: Address 0xfffffff8427eeed8 couldn't be found in vm address set
```

You can also point Hopper at the shared cache in the folder `/System/Library/dyld/`, but Hopper isn't useful for extracting headers and getting usable code. Tools that kind of [helped with this](https://github.com/antons/dyld-shared-cache-big-sur) died after Big Sur Beta 9.

Even though Apple open sourced `dsc_extractor` it essentially is useless without [tremendous modifications to the code](https://lapcatsoftware.com/articles/bigsur.html), and things have changes greatly with [newer vesions](https://github.com/apple-oss-distributions/dyld) of Apple's source code to the point where Jeff Johnson's blog post is now longer complete. Others have found [clever tricks](https://gist.github.com/NSExceptional/85527151eeec4b0640187a0a165da1cd?permalink_comment_id=3707660#gistcomment-3707660) or simply [took the functions](https://twitter.com/zhuowei/status/1402137181502722051) necessary out of the [main code](https://gist.github.com/zhuowei/4bc4baeb12f64b2e03608cd2b2d7b4d7) but the issue remains - Even when the binary is dumped from the framework, the data is fundamentally missing for these tools to extract the headers/classes.

There are so many [cool tools](https://mroi.github.io/apple-internals/) around knowledge of macOS and reverse engineering [other formats](https://github.com/bartoszj/acextract) Apple has created, but it just seems like we are hitting a roadblock.

Without someone picking up the mantle (it won't be me), I worry about long term viability for projects like gnes. Future versions of macOS will have new behavior and if Apple continues on not providing admins a method to properly get this data in a supported state, we will be left with _nothing_. The mere fact that I was able to get this data from Big Sur was really due to Apple releasing System Extensions/Network Extensions with that OS. Future me and future macadmins may not be so lucky.

My hope is some of the [issues](https://github.com/DerekSelander/dsdump/issues/30) with [dsdump](https://github.com/DerekSelander/dsdump/issues/35) will be resolved and this can be the first part in getting usable data again. I may even take a stab at sending a pull request, time permitting.

# Conclusion
As you can see, this took a tremendous amount of effort for something that really should just be a public API. Please Apple, please, release one in a future version of macOS.

I have submitted [feedback to Apple]() and I would appreciate it being duplicated if you care about data like this.

PS. If for some reason you do want an incomplete version of gnes, but in python3, see this [gist](https://gist.github.com/erikng/407366fce4a3df6e1a5f8f44733f89ea)

Until next time...

## Table Of Contents
* Do not remove this line (it will not be displayed)
{:toc}
