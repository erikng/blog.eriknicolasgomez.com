---
layout: post
title: "Moving your DeployStudio Workflows to Imagr"
description: "Stop using Apple's... I mean 'admin's' tool."
tags: [DeployStudio, Imagr]
comments: true
---

If you're here, chances are you're interested in Imagr and read a [blog post](https://managingosx.wordpress.com/2015/04/22/introducing-imagr/) or [two](https://managingosx.wordpress.com/2015/04/22/setting-up-server-side-resources-for-imagr-testing/) or [three](https://osxdominion.wordpress.com/2015/05/12/we-are-imagr-and-so-can-you/). Unfortunately, something is holding you back. Maybe it's time, your imaging process or a very specific function of DeployStudio that you absolutely need. As you'll quickly find out, most barriers are short lived.

## Benefits of Imagr:
- Open Source
- Light
- [You actually know the maintainers!](https://groups.google.com/forum/#!topic/macenterprise/neLd-ScON5o)

### Areas of Improvement:
- Server Logging
- Embedded Workflows
- Fusion Drive Support

### Imagr isn't:
- A tool for capturing thick images
- GUI based for the Admin

---

## A few basic scripts
I've created two Imagr Wiki pages:

- [DeployStudio Alternative Scripts](https://github.com/grahamgilbert/imagr/wiki/DeployStudio-Alternative-Scripts)
- [Admin Provided Scripts](https://github.com/grahamgilbert/imagr/wiki/Admin-Provided-Scripts)

Sir Gilbert has opted for the Wiki route for a few reasons:

- Smaller codebase to maintain
- Easier entry for admins to contribute to the project.

Currently there are only a few scripts. As you begin to transition over to Imagr, if there is a configuration setting that you find to script, please add it to the list.

---

## Breaking down your DeployStudio Workflows
I've taken DeployStudio for granted for many years. While I document many other processes, due to DeployStudio being mostly WYSIWYG, I've never felt compelled to actually list out each process I used.

If you want a successful transition you're going to want to document. You know those checkboxes you use in DeployStudio? Document them!

### Deploy Studio Breakdown Example
1. DS Restore Task
  - Restore System Recovery Partition
  - Set as Default Startup Volume
  - Preventative Volume Repair
  - Convert to CoreStorage
2. DS HostName Task
3. DS Configure Task
  - Skip Apple Setup Assistant
  - Disable Gatekeeper
4. DS Generic Task
  - Munki Manifest Selector
5. DS Package Install Task
  - Munki
6. DS SoftwareUpdate Task
7. Time Task
8. DS Active Directory Task
9. Automatic Reboot after completion (built into DS)


Let's tackle these one by one. All of these tasks should be added to the `components` array

## DS Restore Task
This one can is rather simple. By default, Imagr will automatically `bless` the volume.

```xml
<dict>
  <key>type</key>
  <string>image</string>
  <key>url</key>
  <string>http://10.10.10.10/imagr/masters/OS_X_10.10.3-14D136.hfs.dmg</string>
</dict>
<dict>
  <key>type</key>
  <string>script</string>
  <key>content</key>
  <string>#!/bin/bash
# Repair Disk Permissions
diskutil repairPermissions /
  </string>
</dict>
<dict>
  <key>type</key>
  <string>script</string>
  <key>content</key>
  <string>#!/bin/bash
# Convert to CoreStorage
diskutil cs convert disk0s2
  </string>
</dict>
```

## DS HostName Task
Imagr can now prompt for a name.

```xml
<dict>
    <key>type</key>
    <string>computer_name</string>
</dict>
```

If your naming convention is based via serial number (like me) you can even remove your custom DS script.

```xml
<dict>
    <key>type</key>
    <string>computer_name</string>
    <key>use_serial</key>
    <true/>
    <key>auto</key>
    <true/>
</dict>
```

## DS Configure Task
Both of these tasks are rather simple.

```xml
<dict>
  <key>type</key>
  <string>script</string>
  <key>content</key>
  <string>#!/bin/bash
# Disable Gatekeeper
spctl --master-disable
  </string>
</dict>
<dict>
  <key>type</key>
  <string>script</string>
  <key>content</key>
  <string>#!/bin/bash
# Bypass Apple Assistant
/usr/bin/touch "{{target_volume}}/private/var/db/.AppleSetupDone"
  </string>
</dict>
```

## DS Generic Task
Basically everything we are doing here are considered "Generic Tasks". See [my other post](/2015/05/14/munki_manifest_selector_with_imagr.html) for an approach to non-scripted generic tasks.

## DS Package Install Task
Packages are very straight forward

```xml
<dict>
    <key>type</key>
    <string>package</string>
    <key>url</key>
    <string>http://10.10.10.10/imagr/packages/munkitools.pkg</string>
    <key>first_boot</key>
    <false/>
</dict>
```

## DS SoftwareUpdate Task
Here is where I recommend a mobile configuration file. If you still want to do it the DeployStudio way, here is an example.

```xml
<dict>
  <key>type</key>
  <string>script</string>
  <key>content</key>
  <string>#!/bin/sh
# Variables
SUS="URLPATH"

/usr/bin/defaults write "{{target_volume}}/Library/Preferences/com.apple.SoftwareUpdate" CatalogURL $SUS
chmod 644 "{{target_volume}}/Library/Preferences/com.apple.SoftwareUpdate.plist"
/usr/sbin/chown root:admin "{{target_volume}}/Library/Preferences/com.apple.SoftwareUpdate.plist"
  </string>
</dict>
```

## Time Task
[Rich Trouton](https://github.com/rtrouton/rtrouton_scripts/blob/master/rtrouton_scripts/time_settings/time_settings.sh) has a great script to accomplish this.

```bash
<dict>
  <key>type</key>
  <string>script</string>
  <key>content</key>
  <string>#!/bin/sh
#Primary Time server for Company Macs

TimeServer1=timeserver1.company.com

#Secondary Time server for Company Macs

TimeServer2=timeserver2.company.com

#Tertiary Time Server for Company Macs, used outside of Company network

TimeServer3=time.apple.com

# Time zone for Company Macs

TimeZone=America/New_York

# Configure network time server and region

# Set the time zone
/usr/sbin/systemsetup -settimezone $TimeZone

# Set the primary network server with systemsetup -setnetworktimeserver
# Using this command will clear /etc/ntp.conf of existing entries and
# add the primary time server as the first line.

/usr/sbin/systemsetup -setnetworktimeserver $TimeServer1

# Add the secondary time server as the second line in /etc/ntp.conf
echo "server $TimeServer2" >> /etc/ntp.conf

# Add the tertiary time server as the third line in /etc/ntp.conf
echo "server $TimeServer3" >> /etc/ntp.conf

# Enables the Mac to set its clock using the network time server(s)
/usr/sbin/systemsetup -setusingnetworktime on
</string>
</dict>
```

## DS Active Directory Task
I would highly recommend that you package this as saving this directly in the imagr_config.plist will leave your AD binding account exposed.

With that said, [Sir Gilbert](https://github.com/grahamgilbert/macscripts/blob/master/AD%20Bind/postinstall) has a great script for this (taken from DS.)

```bash
<dict>
  <key>type</key>
  <string>script</string>
  <key>content</key>
  <string>#!/bin/sh

# This was stolen from DeployStudio. I didn't write it, but dammit, I'm going to use it.

#
# Script config
#

AD_DOMAIN="ad.company.com"
COMPUTER_ID=`/usr/sbin/scutil --get LocalHostName`
COMPUTERS_OU="OU=Macs,OU=London,DC=ad,DC=company,DC=com"
ADMIN_LOGIN="bindUser"
ADMIN_PWD="bindPassword"
MOBILE="enable"
MOBILE_CONFIRM="disable"
LOCAL_HOME="enable"
USE_UNC_PATHS="enable"
UNC_PATHS_PROTOCOL="smb"
PACKET_SIGN="allow"
PACKET_ENCRYPT="allow"
PASSWORD_INTERVAL="0"
ADMIN_GROUPS="COMPANY\Domain Admins,COMPANY\Enterprise Admins"

# UID_MAPPING=
# GID_MAPPING=
# GGID_MAPPING==

# disable history characters
histchars=

SCRIPT_NAME=`basename "${0}"`

echo "${SCRIPT_NAME} - v1.26 ("`date`")"

#
# functions
#
is_ip_address() {
  IP_REGEX="\b(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\b"
  IP_CHECK=`echo ${1} | egrep ${IP_REGEX}`
  if [ ${#IP_CHECK} -gt 0 ]
  then
    return 0
  else
    return 1
  fi
}


#
# Wait for the naming script to have run
#
if [ ${COMPUTER_ID} -eq "" ]
then
echo "The mac doesn't have a name, exiting."
  exit 1
fi

# AD can only use a 15 character name
COMPUTER_ID=`echo ${COMPUTER_ID} | cut -c1-15`

#
# Wait for network services to be initialized
#
echo "Checking for the default route to be active..."
ATTEMPTS=0
MAX_ATTEMPTS=18
while ! (netstat -rn -f inet | grep -q default)
do
  if [ ${ATTEMPTS} -le ${MAX_ATTEMPTS} ]
  then
    echo "Waiting for the default route to be active..."
    sleep 10
    ATTEMPTS=`expr ${ATTEMPTS} + 1`
  else
    echo "Network not configured, AD binding failed (${MAX_ATTEMPTS} attempts), will retry at next boot!" 2>&1
    exit 1
  fi
done

#
# Wait for the related server to be reachable
# NB: AD service entries must be correctly set in DNS
#
SUCCESS=
is_ip_address "${AD_DOMAIN}"
if [ ${?} -eq 0 ]
then
  # the AD_DOMAIN variable contains an IP address, let's try to ping the server
  echo "Testing ${AD_DOMAIN} reachability" 2>&1
  if ping -t 5 -c 1 "${AD_DOMAIN}" | grep "round-trip"
  then
    echo "Ping successful!" 2>&1
    SUCCESS="YES"
  else
    echo "Ping failed..." 2>&1
  fi
else
  ATTEMPTS=0
  MAX_ATTEMPTS=12
  while [ -z "${SUCCESS}" ]
  do
    if [ ${ATTEMPTS} -lt ${MAX_ATTEMPTS} ]
    then
      AD_DOMAIN_IPS=( `host "${AD_DOMAIN}" | grep " has address " | cut -f 4 -d " "` )
      for AD_DOMAIN_IP in ${AD_DOMAIN_IPS[@]}
      do
        echo "Testing ${AD_DOMAIN} reachability on address ${AD_DOMAIN_IP}" 2>&1
        if ping -t 5 -c 1 ${AD_DOMAIN_IP} | grep "round-trip"
        then
          echo "Ping successful!" 2>&1
          SUCCESS="YES"
        else
          echo "Ping failed..." 2>&1
        fi
        if [ "${SUCCESS}" = "YES" ]
        then
          break
        fi
      done
      if [ -z "${SUCCESS}" ]
      then
        echo "An error occurred while trying to get ${AD_DOMAIN} IP addresses, new attempt in 10 seconds..." 2>&1
        sleep 10
        ATTEMPTS=`expr ${ATTEMPTS} + 1`
      fi
    else
      echo "Cannot get any IP address for ${AD_DOMAIN} (${MAX_ATTEMPTS} attempts), aborting lookup..." 2>&1
      break
    fi
  done
fi

if [ -z "${SUCCESS}" ]
then
  echo "Cannot reach any IP address of the domain ${AD_DOMAIN}." 2>&1
  echo "AD binding failed, will retry at next boot!" 2>&1
  exit 1
fi

#
# Unbinding computer first
#
echo "Unbinding computer..." 2>&1
dsconfigad -remove -username "${ADMIN_LOGIN}" -password "${ADMIN_PWD}" 2>&1

#
# Try to bind the computer
#
ATTEMPTS=0
MAX_ATTEMPTS=12
SUCCESS=
while [ -z "${SUCCESS}" ]
do
  if [ ${ATTEMPTS} -le ${MAX_ATTEMPTS} ]
  then
    echo "Binding computer to domain ${AD_DOMAIN}..." 2>&1
    dsconfigad -add "${AD_DOMAIN}" -computer "${COMPUTER_ID}" -ou "${COMPUTERS_OU}" -username "${ADMIN_LOGIN}" -password "${ADMIN_PWD}" -force 2>&1
    IS_BOUND=`dsconfigad -show | grep "Active Directory Domain"`
    if [ -n "${IS_BOUND}" ]
    then
      SUCCESS="YES"
    else
      echo "An error occured while trying to bind this computer to AD, new attempt in 10 seconds..." 2>&1
      sleep 10
      ATTEMPTS=`expr ${ATTEMPTS} + 1`
    fi
  else
    echo "AD binding failed (${MAX_ATTEMPTS} attempts), will retry at next boot!" 2>&1
    SUCCESS="NO"
  fi
done

if [ "${SUCCESS}" = "YES" ]
then
  #
  # Update AD plugin options
  #
  echo "Setting AD plugin options..." 2>&1
  dsconfigad -mobile ${MOBILE} 2>&1
  sleep 1
  dsconfigad -mobileconfirm ${MOBILE_CONFIRM} 2>&1
  sleep 1
  dsconfigad -localhome ${LOCAL_HOME} 2>&1
  sleep 1
  dsconfigad -useuncpath ${USE_UNC_PATHS} 2>&1
  sleep 1
  dsconfigad -protocol ${UNC_PATHS_PROTOCOL} 2>&1
  sleep 1
  dsconfigad -packetsign ${PACKET_SIGN} 2>&1
  sleep 1
  dsconfigad -packetencrypt ${PACKET_ENCRYPT} 2>&1
  sleep 1
  dsconfigad -passinterval ${PASSWORD_INTERVAL} 2>&1
  if [ -n "${ADMIN_GROUPS}" ]
  then
    sleep 1
    dsconfigad -groups "${ADMIN_GROUPS}" 2>&1
  fi
  sleep 1

  if [ -n "${AUTH_DOMAIN}" ] && [ "${AUTH_DOMAIN}" != 'All Domains' ]
  then
    dsconfigad -alldomains disable 2>&1
  else
    dsconfigad -alldomains enable 2>&1
  fi
  AD_SEARCH_PATH=`dscl /Search -read / CSPSearchPath | grep "Active Directory" | sed 's/^ *//' | sed 's/ *$//'`
  if [ -n "${AD_SEARCH_PATH}" ]
  then
    echo "Deleting '${AD_SEARCH_PATH}' from authentication search path..." 2>&1
    dscl localhost -delete /Search CSPSearchPath "${AD_SEARCH_PATH}" 2>/dev/null
    echo "Deleting '${AD_SEARCH_PATH}' from contacts search path..." 2>&1
    dscl localhost -delete /Contact CSPSearchPath "${AD_SEARCH_PATH}" 2>/dev/null
  fi
  dscl localhost -create /Search SearchPolicy CSPSearchPath 2>&1
  dscl localhost -create /Contact SearchPolicy CSPSearchPath 2>&1
  AD_DOMAIN_NODE=`dscl localhost -list "/Active Directory" | head -n 1`
  if [ "${AD_DOMAIN_NODE}" = "All Domains" ]
  then
    AD_SEARCH_PATH="/Active Directory/All Domains"
  elif [ -n "${AUTH_DOMAIN}" ] && [ "${AUTH_DOMAIN}" != 'All Domains' ]
  then
    AD_SEARCH_PATH="/Active Directory/${AD_DOMAIN_NODE}/${AUTH_DOMAIN}"
  else
    AD_SEARCH_PATH="/Active Directory/${AD_DOMAIN_NODE}/All Domains"
  fi
  echo "Adding '${AD_SEARCH_PATH}' to authentication search path..." 2>&1
  dscl localhost -append /Search CSPSearchPath "${AD_SEARCH_PATH}"
  echo "Adding '${AD_SEARCH_PATH}' to contacts search path..." 2>&1
  dscl localhost -append /Contact CSPSearchPath "${AD_SEARCH_PATH}"

  if [ -n "${UID_MAPPING}" ]
  then
    sleep 1
    dsconfigad -uid "${UID_MAPPING}" 2>&1
  fi
  if [ -n "${GID_MAPPING}" ]
  then
    sleep 1
    dsconfigad -gid "${GID_MAPPING}" 2>&1
  fi
  if [ -n "${GGID_MAPPING}" ]
  then
    sleep 1
    dsconfigad -ggid "${GGID_MAPPING}" 2>&1
  fi

  GROUP_MEMBERS=`dscl /Local/Default -read /Groups/com.apple.access_loginwindow GroupMembers 2>/dev/null`
  NESTED_GROUPS=`dscl /Local/Default -read /Groups/com.apple.access_loginwindow NestedGroups 2>/dev/null`
  if [ -z "${GROUP_MEMBERS}" ] && [ -z "${NESTED_GROUPS}" ]
  then
    echo "Enabling network users login..." 2>&1
    dseditgroup -o edit -n /Local/Default -a netaccounts -t group com.apple.access_loginwindow 2>/dev/null
  fi

  #
  # Self-removal
  #
  if [ "${SUCCESS}" = "YES" ]
  then
    if [ -e "/System/Library/CoreServices/ServerVersion.plist" ]
    then
      DEFAULT_REALM=`more /Library/Preferences/edu.mit.Kerberos | grep default_realm | awk '{ print $3 }'`
      if [ -n "${DEFAULT_REALM}" ]
      then
        echo "The binding process looks good, will try to configure Kerberized services on this machine for the default realm ${DEFAULT_REALM}..." 2>&1
        /usr/sbin/sso_util configure -r "${DEFAULT_REALM}" -a "${ADMIN_LOGIN}" -p "${ADMIN_PWD}" all
      fi
      #
      # Give OD a chance to fully apply new settings
      #
      echo "Applying changes..." 2>&1
      sleep 10
    fi
    if [ -e "${CONFIG_FILE}" ]
    then
      /usr/bin/srm -mf "${CONFIG_FILE}"
    fi
    /usr/bin/srm -mf "${0}"
    exit 0
  fi
fi

exit 1
</string>
</dict>
```

## DS Automatic Reboot
If you would like Image to automatically reboot after deploying your image (and begin it's first boot processes), add this somewhere in your workflow.

```xml
<key>restart_action</key>
<string>restart</string>
```

## Final Thoughts

As you can see, many of DeployStudio's checkboxes are very small configuration changes. While none of these examples contain any error checking, they work quite well.

Through the years my workflows have slimmed down considerably. Most have been converted to mobile configuration files, while others have simply moved into munki/outset. While you may consider some aspects of DeployStudio essential, I continue to find myself _decreasing_ the amount of steps needed for a "successful image". As you transfer your workflows over to Imagr, think about trimming down as much fat as possible. In the end your results will be much more stable and you'll become a more dynamic admin.