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

As of Big Sur and higher, EDR vendors have begun to implement Content Filter Network Extensions that pass all network traffic through it. Many of these vendors highly recommend implementing it in enterprise environments and it comes on as default.

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

Macadmins on the CrowdStrike slack channel had found the following could tell them of the state.

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

While this is an OK method, I had concerns about trusting CrowdStrike to return it's own health state. When discussing this issue with CrowdStrike, one of their engineers recommended doing the following.

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

I much preferred this method as this information was sourced directly from Apple. What I didn't like though was the multi grep.

When playing around with this in [macadmins python](https://github.com/macadmins/python) I realized this plist is in a very strange format.

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

But having Chef, which is written in Ruby depend on Python just felt like the wrong approach. Luckily as of Chef 17.7.22, Chef now has a built in method for using a [Ruby to ObjC bridge for CoreFoundation](https://github.com/chef/chef/pull/11898). With that bridge available, I [ported the python code into ruby and made it a dynamic function](https://github.com/uber/client-platform-engineering/blob/main/chef/cookbooks/uber_helpers/libraries/node_utils.rb#L737-L760) so we could use it for other Network Extensions, should the time come.

We were then able to hook into this [function directly in our crowdstrike code](https://github.com/uber/client-platform-engineering/blob/main/chef/cookbooks/cpe_crowdstrike_falcon_sensor/resources/cpe_crowdstrike_falcon_sensor.rb#L318-L334).

Life was great! But then we started seeing failures on some of our devices. Further investigation showed that this function failed when there were multiple content filters. CFPreferences, or at least the bridge that the Progress team had written was failing, causing Chef runs to fail.

With a bit of a hint, I went back to python, but this time tried via PyObjc:

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

This looks _much_ better, is much more stable, but one of my original requirements was back to being a problem. I decided to take a look at what the Progress team did with [CoreFoundation](https://github.com/chef/corefoundation) and immediately noped my way off that cliff.

I started thinking about using JXA as other [macadmins](https://scriptingosx.com/2021/11/the-unexpected-return-of-javascript-for-automation/) have been discussing using this option, but I'm not too fond (or good) with javascript and the idea of shelling out to _another_ non-compiled language bothered me. It also felt like it was going to get [very complex](https://github.com/JXA-Cookbook/JXA-Cookbook/wiki/Using-Objective-C-%28ObjC%29-with-JXA#jxa-objc-bridge---the-fundamentals) very quickly for implementing an Objective-C bridge.

As someone decently versed in Swift these days, I figured that porting my PyObjC code to Swift would be pretty painless, given that so much of my Nudge-Python code easily ported to Swift.

I was absolutely wrong.

# The real journey
So right off the bat things didn't look so good. Even though Swift had the module `NetworkExtension` already available, you couldn't just grab the class `NEConfigurationManager`

```swift
import NetworkExtension

let NEConfigurationManager = NetworkExtension.classNamed("NEConfigurationManager")

ERROR: Module 'NetworkExtension' has no member named 'classNamed'
```

Swift has something similar to the PyObjC method where you can load a [bundle via the framework path](https://stackoverflow.com/a/58124538)

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

Somewhat progress, but then we hit the next stumbling block

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

Because the compiler didn't know what `NEConfigurationManager` is, we had to cast it to `AnyClass?` and now, the compiler has no idea that there is a sub class called `sharedManager()`

If we add back the original NetworkExtension we get _another_ error

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

When googling this error, essentially the compiler doesn't know what `sharedManager()` to use, because multiple frameworks have the same name. Going back to the issue in the previous iteration, we had to force cast it to `AnyClass?` so we've muddled the waters.

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

This gave me a bunch of sub classes via stdout

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

This showed me where the objects were

```
Optional(0x00007ff8196cdfd4)
Optional(0x00007ff8196df6a1)
Program ended with exit code: 0
```

With this, I thought I could call [method invoke](https://developer.apple.com/documentation/objectivec/1456726-method_invoke) and get passed the issue

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

Googling this lead me to another issue. This function, can accept `AnyObject`, [so it's defined as a variadic function](https://akrabat.com/wrapping-variadic-functions-for-use-in-swift/). At this point I was pretty frustrated as I had wasted hours upon hours at night on something that I thought would be a 5 minute port.

It was pretty obvious to me that Apple didn't think we needed access to this functionality (or want us to have it) and the only way was to follow [another person's lead](https://blog.timac.org/2018/0717-macos-vpn-architecture/) who built an [open source VPN](https://blog.timac.org/2018/0719-vpnstatus/) that exposed small elements of the [headers](https://github.com/Timac/VPNStatus/blob/97e6932cfab86c3ec1dfddd7fdd3a633044a47ea/Common/ACDefines.h#L101-L114). 

> With this knowledge, it is easy to build a replacement for macOS built-in VPN Status menu. This application can use the NEConfigurationManager class from the private part of the NetworkExtension.framework in order to retrieve the NEConfiguration configurations.

Unfortunately for me, while this was helpful, his application was pure Objective-C. It was now obvious to me though. I needed to dump the headers and get what I needed from them.

# Stop hitting yourself
Long ago when writing the Untouchables series, I had learned about `ovtool` and that was my first attempt at trying to understand the framework file

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

With this information I could again see the pointers of the functions, but it's not really useful for my purposes. I tried [another tool](https://github.com/nst/RuntimeBrowser) to no avail. My next thought was that Apple provides headers in the Xcode bundle itself. For macOS it is located at `/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk`

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

You can also see these headers on [alexy lysuik's github repo](https://github.com/alexey-lysiuk/macos-sdk/tree/master/MacOSX12.1.sdk/System/Library/Frameworks/NetworkExtension.framework/Versions/A/Headers). Unfortunately these headers didn't have the functions I needed. In fact it looked like these were the headers Xcode itself used for the compiler, aka my original issue :) But with this, I at least knew what the format needed to look like.

Googling more lead me to [this link](https://developer.limneos.net/index.php?ios=12.1&framework=NetworkExtension.framework&header=NEConfigurationManager.h) which I found very interesting. This header contained practically all of the information I needed, but it was for iOS 12. More importantly though was one of the first lines.

```shell
* This header is generated by classdump-dyld 1.0
```

This lead me down a new, very interesting path. The [iphone dev wiki](https://iphonedev.wiki/index.php/Reverse_Engineering_Tools#Class.2FMetadata_Dumping_tools) has a treasure trove of class/header dumping tools. Of course, as is this case always with macOS, most of these tools were really only designed to work on iOS.

[Since iOS 3.1](https://iphonedev.wiki/index.php/Dyld_shared_cache), Apple had moved to a cache file to improve performance. This feature finally came to macOS with the introduction of Big Sur. You can see these cache files within `/System/Library/dyld/` (dyld_shared_cache_x86_64 for Intel, dyld_shared_cache_arm64e for Apple Silicon).

[classdump-dyld](https://github.com/limneos/classdump-dyld) development seems to have stalled and doesn't support modern macOS versions, so I went looking for alternatives. I found a [macOS headers repo](https://github.com/w0lfschild/macOS_headers/tree/master/tools), but the headers were out of date and I didn't want to use them, even though they looked potentially viable. I wish I had read [issue 3](https://github.com/w0lfschild/macOS_headers/issues/3) at the time, but stopped immediately at [issue 5](https://github.com/w0lfschild/macOS_headers/issues/5). More info on this in a second.

As I continued down the litany of `classdymp-dyld` forks I found [this one](https://github.com/freedomtan/classdump-dyld) that looked promising as it even had Apple M1 support.

I cloned the repo and quickly ran `make all` and hoped for the best.

There were several interesting arguments you could pass
- `./classdump-dyld -o outdir -c` would dump everything it possibly could.
- `./classdump-dyld -o outdir -r /System/Library/Frameworks/` would dump all the sub frameworks, but was taking quite a while to process it all.
- `./classdump-dyld -o outdir -r /System/Library/Frameworks/NetworkExtension.framework/` seemed to be what I was looking for

```shell
./classdump-dyld -o outdir -r /System/Library/Frameworks/NetworkExtension.framework
  Dumping /System/Library/Frameworks/NetworkExtension.framework/PlugIns/NEIKEv2Provider.appex/Contents/MacOS/NEIKEv2Provider...(1 classes)
  Done. Check "outdir" directory.
```

Nothing. Not a single header. :( I googled around and found some links to building Apple's open source tool [dsc_extractor](https://opensource.apple.com/source/dyld/dyld-433.5/launch-cache/dsc_extractor.cpp.auto.html) (more info below) and then tried the original classdump on the extracted binary but again, nothing.

```shell
./classdump -o outdir -r ./dsc_extracted/System/Library/Frameworks/NetworkExtension.framework/Versions/A/NetworkExtension
  Done. Check "outdir" directory.
```

I was about to give up when I started looking author's [open issues](https://github.com/freedomtan/classdump-dyld/issues/3) again. Maybe it works on Big Sur? My wife is pretty slow at installing updates and she was still on macOS Big Sur 11.6, so with a little coercing, she handed me her laptop and I performed the same commands.

```shell

```

Yessssssssss! I finally had some progress and could start learning the next part.

# Adding headers to a swift project

# Introducing gnes (G Ness - Get Network Extension Status)
[gnes](https://github.com/erikng/gnes) is a Swift 5, Objective-C binary that has several options.

Further optimization can likely be done with the headers like [combining them into a single file](https://github.com/udevsharold/airkeeper/blob/master/PrivateHeaders.h), there's likely some [gotchas](https://swiftrocks.com/be-careful-with-objc-bridging-in-swift) with the objc bridge and clearly some optimization that needs to happen in the gnes code, but it at least we have something now that works.

# The state of class dumping on macOS
To be frank, it appears to be dying. You can [find lots of people](https://mjtsai.com/blog/2020/06/26/reverse-engineering-macos-11-0/) complaining about this since 2020.

> Incidentally, the new stripped framework cache on macOS 11 is horrendous for disassembly. If you’re trying to track down why there’s a bug in your app, or how a system implementation works, you are screwed. - [Steve Troughton-Smith](https://twitter.com/stroughtonsmith/status/1275898134942691330)

There are other [useful iOS header sources](https://headers.cynder.me/index.php?sdk=iOS15&fw=Frameworks/NetworkExtension.framework) that used other tools like [ktool](https://github.com/cxnder/ktool) but as of just a few days ago the author didn't think he could [ever support macOS Monterey](https://github.com/cxnder/ktool/issues/35). People who have [tried to maintain headers](https://github.com/LeoNatan/Apple-Runtime-Headers/) rely on these tools to work. [Older tools](https://github.com/nygard/class-dump) and their various forks do not work.

Tools like [DyldExtractor](https://github.com/arandomdev/DyldExtractor/issues/33) suffer the same fate. Alternative tools like [dsdump](https://github.com/DerekSelander/dsdump/issues/20) aren't really designed for creating header files and even [forks](https://github.com/paradiseduo/dsdump) or [new tools](https://github.com/paradiseduo/resymbol) based on dsdump still don't work on Monterey.

Tools like [dyld-shared-cache-extractor](https://github.com/keith/dyld-shared-cache-extractor) get us halfway there, but then you hit a roadblock (as mentioned above regarding ktool)
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

You can also point Hopper at the shared cache in the folder `/System/Library/dyld/`, but Hopper isn't useful for extracting headers and getting usable code. Tools that kind of [helped with this](https://github.com/antons/dyld-shared-cache-big-sur) died after Big Sur Beta 9

Even though Apple offers `dsc_extractor` it essentially is useless without [tremendous modifications to the code](https://lapcatsoftware.com/articles/bigsur.html) (things have changes greatly with [newer vesions](https://github.com/apple-oss-distributions/dyld) of Apple's source code). Others have found [clever tricks](https://gist.github.com/NSExceptional/85527151eeec4b0640187a0a165da1cd?permalink_comment_id=3707660#gistcomment-3707660) or simply [took the functions](https://twitter.com/zhuowei/status/1402137181502722051) necessary out of the [main code](https://gist.github.com/zhuowei/4bc4baeb12f64b2e03608cd2b2d7b4d7) but the issue remains - there is data fundamentally missing for these tools to extract the header files.

There are so many [cool tools](https://mroi.github.io/apple-internals/) around knowledge of macOS and reverse engineering [other formats](https://github.com/bartoszj/acextract) Apple has created, but it just seems like we are hitting a roadblock.

Without someone picking up the mantle (it won't be me), I worry about long term viability for projects like gnes. Future versions of macOS will have new behavior and if Apple continues on not providing admins a method to properly get this data in a supported state, we will be left with _nothing_. The mere fact that I was able to get this data from Big Sur was really due to Apple releasing System Extensions/Network Extensions with that OS.

My hope is some of the [issues](https://github.com/DerekSelander/dsdump/issues/30) with [dsdump](https://github.com/DerekSelander/dsdump/issues/35) will be resolved and this can be the first part in getting usable data again. I may even take a stab at sending a pull request, time permitting.

# Conclusion
As you can see, this took a tremendous amount of effort for something that really should just be a public API. Please Apple, please, release one in a future version of macOS. 

PS. If for some reason you do want an incomplete version of gnes, but in python3, see this [gist](https://gist.github.com/erikng/407366fce4a3df6e1a5f8f44733f89ea)

Until next time...

## Table Of Contents
* Do not remove this line (it will not be displayed)
{:toc}
