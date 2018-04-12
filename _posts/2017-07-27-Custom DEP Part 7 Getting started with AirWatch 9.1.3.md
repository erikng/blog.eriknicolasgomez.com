---
layout: post
author: Erik Gomez
title: "Custom DEP - Part 7: Getting started with AirWatch 9.1.3"
description: "Custom DEP for all AirWatch customers"
tags: [AirWatch, macOS, DEP, MDM, EMM, InstallApplication, InstallApplications, mdmclient]
published: true
date: 2017-07-27 11:40:00
comments: true
---

Three months to the day I announced that AirWatch had released custom DEP in AirWatch 9.1. This was a limited release due to a few outstanding issues with `mdmclient`, especially in regard to the `InstallApplication` command. With macOS 10.12.6, Apple has now resolved these bugs and AirWatch feels comfortable with releasing this to _all_ AirWatch customers.

As of today, AirWatch 9.1.3 has now been put into General Availability. In this blog post, I will show you how to quickly setup DEP in a brand new AirWatch environment so you can quickly get started on your custom DEP adventure.

# Requirements
- DEP Portal access [https://deploy.apple.com](https://deploy.apple.com)
- AirWatch 9.1.3 On-Premise/Dedicated Cloud/Shared Cloud
- A signed/distribution package for deployment (I recommend using [InstallApplications](/2017/04/05/Custom-DEP-Part-5-Dynamic-InstallApplication/))

# Configuring AirWatch
Although AirWatch is a beast of a console, you can get custom DEP setup in about 15 minutes.

## Configuring DEP Stage 1 - Registering with Apple
- Go to **Groups & Settings** -> **All Settings**

![AirWatch - All Settings](/images/2017/07/AirWatch_All_Settings.png)

- Go to **Devices & Users** -> **Apple** -> **Device Enrollment Program** -> **Configure**

![AirWatch - DEP Configuration](/images/2017/07/AirWatch_DEP_Configuration.png)

- Download the **Public Key** that is provided by AirWatch
- Leave this AirWatch tab open as you will come back to it

![AirWatch - DEP Token](/images/2017/07/AirWatch_DEP_Token.png)

- In other tab, go to [https://deploy.apple.com](https://deploy.apple.com) and sign in with your DEP Apple ID.
- Once signed in go to **Device Enrollment Program** -> **Manage Servers** -> **Add MDM Server**

![DEP - Add MDM Server](/images/2017/07/DEP_Add_MDM_Server.png)

- Give your MDM/DEP Server a **name** and then upload the **Public Key** you downloaded from AirWatch.

![DEP - Upload Public Key](/images/2017/07/DEP_Upload_Public_Key.png)

- Download the **Server Token** and hit **Done**
- Keep the Apple DEP page open.

![DEP - Download Server Token](/images/2017/07/DEP_Download_Server_Token.png)

- Back in the AirWatch tab, upload the **Server Token**

![AirWatch - Upload Server Token](/images/2017/07/AirWatch_Server_Token.png)

Congrats - you now have DEP configured - now to the fun stuff.

## Configuring DEP Stage 2 - Configuring DEP Profile

### Notes
While you can have DEP unauthenticated, I feel this leaves your DEP server in a vulnerable state - an attacker would only need to know one serial number from your fleet.

Because of this, the following tutorial will make an assumption that _all_ macOS devices will require authentication to fully register in DEP.

### Configuring DEP Authentication
- Turn **Authentication** to **On**
- Configure the **Device Ownership Type** to **Corporate - Dedicated**
- Select your Device Organization Group
- Turn off **Custom Prompt** (This is to customize the macOS authentication box.)

![AirWatch - DEP Authentication](/images/2017/07/AirWatch_DEP_Authentication.png)

### Configuring DEP Features
- Give your **Profile Name** a name
- Set a **Department** name
- Configure a **Support Number**
- Ensure **Require MDM enrollment** is set to **Enabled**
- Ensure **Supervision** is set to **Enabled**
- Ensure **Lock MDM Profile** is set to **Enabled**
- Ensure **Await Configuration** is set to **Enabled**

These four settings will ensure that DEP is mandatory for all macOS devices. `Await Configuration` is an interesting command in that your custom DEP package will begin to download (and possibly install if it's very small) _prior_ to the SetupAssistant finishing.

![AirWatch - DEP Features](/images/2017/07/Airwatch_DEP_Features.png)

### Configuring DEP SetupAssistant
For most custom DEP enrollments (especially ones that require authentication), there will only be a few settings that administrator cares about.

- Ensure **Location Services** is set to **Don't Skip**
- Ensure **Account Setup** is set to **Don't Skip**
- Ensure **Account Type** is set to **Administrator**
- Ensure **Create New Admin Account** is set to **No**

This will allow the user to enable location services (to properly setup the timezone) and give them administrative rights to the machine.

![AirWatch - DEP SetupAssistant](/images/2017/07/AirWatch_DEP_SetupAssistant.png)

## Saving DEP Profile
Once you have finalized your settings, you will be sent to a confirmation window.

- Ensure **Sync Now and Assign to All Devices** is set to **Yes** to assign this DEP profile to your devices.
- Ensure **Auto Assign Default Profile** is set to **Yes** to assign new DEP devices to this profile.
- Hit **Save**

![AirWatch - DEP Save](/images/2017/07/AirWatch_DEP_Save.png)

If everything is complete, you should see a window like this.

![AirWatch - DEP Save](/images/2017/07/AirWatch_DEP_Save_2.png)

Congrats - you now have setup DEP and assigned it to your macOS devices... but you're not done yet.

## Configuring DEP Stage 3 - Assigning devices to a DEP server

### Apple Portal
Now that you have a DEP profile assigned and set as default, you need to add some devices to your DEP server.

- In the Apple tab, go to **Device Enrollment Program** -> **Manage Devices**
- Under the **Choose Devices By:** section, select **Serial Number** and paste your serial number(s) into the window, each separated by a **comma**
- Under the **Choose Action:** section, select **Assign to Server** and choose the DEP server you configured earlier.
- Hit **OK**

![Apple - DEP Assign Devices](/images/2017/07/DEP_Assign_Devices.png)

- If successful you will see an **Assignment Complete** window.

![Apple - DEP Assign Devices Successful](/images/2017/07/DEP_Assign_Devices_Successful.png)

### AirWatch console
- In the AirWatch console, go to **Devices** -> **Lifecycle** -> **Enrollment Status**
- Under the **Add** button, select **Sync Devices**

![AirWatch - DEP Sync Devices](/images/2017/07/AirWatch_DEP_Sync_Devices.png)

- You will be asked to confirm a synchronization. Select **Sync**

![AirWatch - DEP Sync Devices Confirmation](/images/2017/07/AirWatch_DEP_Sync_Devices_Confirmation.png)

- If successful, your devices will show up in the **Enrollment Status** page
- If your devices have successfully been assigned your DEP profile, they will have a **Registered** status

![Apple - DEP Assign Devices Success](/images/2017/07/AirWatch_DEP_Sync_Devices_Success.png)

Congrats - now you have macOS devices syncing, but there's some more work to be done.

## Configuring DEP Stage 4 - Adding a test user
In order to authenticate to DEP on your macOS device, you will need a user registered in the console. Typically this is connected to a directory service of some kind, but for this demo, we will setup a standard user.

- In the AirWatch console, go to **Accounts** -> **List View** -> **Add** -> **Add User**

![AirWatch - Add User](/images/2017/07/AirWatch_Add_User.png)

- Set the **Usernane**, **Password**, **Full Name** and **Email Address**
- Under **Enrollment** ensure that it is assigned the same **Organization Group**. This should happen by default.
- Under **Notification**, set it to **None** so no one will be e-mailed about this user creation.
- Hit **Save**

![AirWatch - Add User 2](/images/2017/07/AirWatch_Add_User_2.png)

Congrats - you're inching closer to being done, but there's just a few more things to do.

## Configuring DEP Stage 5 - Add and assign a custom DEP package
Now onto the fun part.

Assuming you have already created your custom DEP package (that is a **signed, distribution package!**) you can now easily add and assign it to your devices.

- Go to **Apps & Books** -> **List View**
- Under the **Internal** tab, select **Add Application**

![AirWatch - Add Custom Pkg](/images/2017/07/Airwatch_Add_Custom_Pkg.png)

- Under **Application File**, select **Upload**.

![AirWatch - Add Custom Pkg 2](/images/2017/07/Airwatch_Add_Custom_Pkg_2.png)

- Select the type **Local File** and browse to your custom package.
- Hit **Save**

![AirWatch - Add Custom Pkg 3](/images/2017/07/Airwatch_Add_Custom_Pkg_3.png)

- If uploaded successfully, you will see it appear as an **Application File**
- Hit **Continue**

![AirWatch - Add Custom Pkg 4](/images/2017/07/Airwatch_Add_Custom_Pkg_4.png)

- AirWatch will detect that this is a **DEP Bootstrap** package
- Select **Save & Assign**

![AirWatch - Bootstrap Pkg](/images/2017/07/AirWatch_Bootstrap_Pkg.png)

- In the **Update Assignment** window, select **Add Assignment**

![AirWatch - Bootstrap Pkg Assignment](/images/2017/07/AirWatch_Bootstrap_Pkg_Assignment.png)

- Under **Select Assignment Groups** select **All Devices**
- Under **App Delivery Method** select **Auto**
- Hit **Add**

![AirWatch - Bootstrap Pkg Assignment 2](/images/2017/07/AirWatch_Bootstrap_Pkg_Assignment_2.png)

- Hit **Save & Publish**

![AirWatch - Bootstrap Pkg Assignment 3](/images/2017/07/AirWatch_Bootstrap_Pkg_Assignment_3.png)


## Configuring DEP Stage 6 - Disabling AirWatch agent installation.
Through at least 10.13.4, you will not be able to reliably install _both_ the custom package and the AirWatch agent. This is due to a macOS [bug](https://openradar.appspot.com/radar?id=4927456712589312) and was one of the reasons why AirWatch held off releasing this feature. 

If you are using a tool like [InstallApplications](https://github.com/erikng/installapplications) or [munki](https://github.com/munki/munki), you may not need to have the AirWatch agent installed or you may actually install it through another mechanism.

To disable the agent:
- Go to **Groups & Settings** -> **All Settings** -> **Devices & Users** -> **Apple** -> **Apple macOS** -> **Agent Application**
- Set the **Current Setting** to **Override**
- **Uncheck** the **Download Mac Agent Post Enrollment** option
- Hit **Save**

![AirWatch - Disable AirWatch Agent](/images/2017/07/AirWatch_Disable_Airwatch_Agent.png)

Congrats! You are DONE. Time to test! :smile:


### Optional Step - Disabling AirWatch Catalog
By default, Airwatch deploys a web clip pointing to the AirWatch catalog. If you are using a tool like munki, you more than likely want to disable this feature.

To disable the catalog web clip:
- Go to **Groups & Settings** -> **All Settings** -> **Apps** -> **Workspace ONE** -> **AirWatch Catalog** -> **General**
- Go to the **Publishing** tab
- Set the **Current Setting** to **Override**
- Under **Platforms** set **macOS** to **Disabled**
- Hit **Save**

![AirWatch - Disable AirWatch Catalog](/images/2017/07/AirWatch_Disable_Catalog.png)

### Notes about custom packages
While this post is to mainly describe how to get setup, you could easily create macOS groups internally that scope to specific custom packages. This would then allow you to have a `production` package that everyone gets, while also being able to use a `test` environment for your own devices. The ideas are endless.

## Testing Custom DEP
This is the easy part.

Turn on a macOS device that you've registered in DEP (or better yet [check out my guide](https://blog.eriknicolasgomez.com/2018/03/26/macOS-testing-tricks-reusing-base-images-and-obtaining-a-root-shell-prior-to-SetupAssistant-with-LanguageChooser/#macos-testing-trick-3---using-vfuse-templates-to-create-a-dep-capable-vm-with-a-pre-allocated-snapshot) on how to create a DEP capable virtual machine with [vfuse](https://github.com/chilcote/vfuse)).

- If DEP worked you should see something like this

![DEP Activation](/images/2017/07/DEP_Activation.png)

- If you set DEP for authorization, authenticate with the username you created earlier.

![DEP Auth](/images/2017/07/DEP_Auth.png)

- Finish the Setup Assistant and get into the desktop.
- If you were successful, you should see the package installed. For myself, that's a mixture of [DEPNotify](https://gitlab.com/Mactroll/DEPNotify), [Chef](https://github.com/chef/chef), [Munki](https://github.com/munki/munki) and [Yo](https://github.com/sheagcraig/yo).

![DEP Success](/images/2017/07/DEP_Success.png)

## Final Thoughts
It's been a very long time since I originally discussed the concept of custom DEP and since then multiple vendors have begun work on adding this functionality. I hope you have enjoyed this series and I look forward to hearing about your results.

For further reading, please see [VMware's GitHub repository on using the Bootstrap package feature.](https://github.com/vmwaresamples/AirWatch-samples/tree/master/macOS-Samples/BootstrapPackage)


---

Hey JAMF - how about you join this custom DEP thing?


## Table Of Contents
* Do not remove this line (it will not be displayed)
{:toc}
