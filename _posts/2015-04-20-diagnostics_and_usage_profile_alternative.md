---
layout: post
title: "Controlling the Diagnostics & Usage report settings on Yosemite – A profile alternative"
description: "Use profiles if at all possible."
tags: [Profiles, macOS, OS X]
comments: true
---

For the past few weeks I have been trying to rid myself of all Default User Template changes. The last piece to the puzzle is Setup Assistant.

Beginning with Yosemite, Apple introduced a new page for submitting diagnostics and usage. [Rich Trouton](https://derflounder.wordpress.com/2014/11/21/controlling-the-diagnostics-usage-report-settings-on-yosemite/) and [Tim Sutton](http://macops.ca/diagnostics-prompt-yosemite) had documented this fairly well, but I wanted to put this in a mobile configuration profile. After digging around, it looks as if Apple has now added a feature in Profile Manager for this feature.

Attached is an example of the settings you will need to manage.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>PayloadIdentifier</key>
    <string>institution.profile.disablediagnostics.783cfc30-c9a5-0132-0f4b-003ee1c41406</string>
    <key>PayloadRemovalDisallowed</key>
    <true/>
    <key>PayloadScope</key>
    <string>System</string>
    <key>PayloadType</key>
    <string>Configuration</string>
    <key>PayloadUUID</key>
    <string>783cfc30-c9a5-0132-0f4b-003ee1c41406</string>
    <key>PayloadOrganization</key>
    <string>Institution</string>
    <key>PayloadVersion</key>
    <integer>1</integer>
	<key>PayloadDisplayName</key>
	<string>Submit Diagnostics</string>
	<key>PayloadDescription</key>
	<string>This profile disables diagnostic submissions.</string>
    <key>PayloadContent</key>
    <array>
      <dict>
        <key>PayloadType</key>
        <string>com.apple.SubmitDiagInfo</string>
        <key>PayloadVersion</key>
        <integer>1</integer>
        <key>PayloadIdentifier</key>
        <string>institution.profile.disablediagnostics.783cfc30-c9a5-0132-0f4b-003ee1c41406.privacy.81c44c90-c9a5-0132-0f4d-003ee1c41406.SubmitDiagInfo</string>
        <key>PayloadEnabled</key>
        <true/>
        <key>PayloadUUID</key>
        <string>5de39a10-edc1-3c95-68dd-9530c29c533c</string>
        <key>PayloadDisplayName</key>
        <string>SubmitDiagInfo</string>
        <key>AutoSubmit</key>
        <false/>
      </dict>
      <dict>
        <key>PayloadType</key>
        <string>com.apple.applicationaccess</string>
        <key>PayloadVersion</key>
        <integer>1</integer>
        <key>PayloadIdentifier</key>
        <string>institution.profile.disablediagnostics.783cfc30-c9a5-0132-0f4b-003ee1c41406.privacy.81c44c90-c9a5-0132-0f4d-003ee1c41406.applicationaccess</string>
        <key>PayloadEnabled</key>
        <true/>
        <key>PayloadUUID</key>
        <string>b60140b5-aca5-c71d-4665-e3a91cdffa7b</string>
        <key>PayloadDisplayName</key>
        <string>ApplicationAccess</string>
        <key>allowDiagnosticSubmission</key>
        <false/>
      </dict>
    </array>
  </dict>
</plist>
```

Once applied by your favorite tool, you're golden.