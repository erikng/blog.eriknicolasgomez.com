---
layout: post
title: "Yosemite Style Banners for Munki 2"
description: "You get a banner. Everyone gets a banner."
tags: [Munki Manifest Selector, Imagr]
comments: true
---
![MSC Hero](/images/2015/05/xcode.png "MSC Hero")

---

Customizing munki can be quite rewarding when done right. By utilizing the `client_resources.zip` file you can make a great looking GUI for your users.

## Trick 1: Add CSS into footer_template.html

[Bart Reardon](https://github.com/bartreardon/munki_client_resources) first documented this trick. You can modify (for better or worse) the css Munki utilizes by adding your desired changes directly into the `footer_template.html`. The following is what I am currently using to make Munki look more like the App Store in Yosemite.

```css
<style>
html, body {
    -webkit-background-size: auto;
    background-repeat: repeat-x;
    background-color: #ffffff;
    background: -webkit-linear-gradient(top, #ffffff 0%, #f5f5f5 75%, #e1e1e1 100%);
    background-attachment: fixed;
}
```

This simply changes the background color to white and adds a subtle gradient to the bottom of the window. You can add CSS to any template file, but the footer_template is on _every_ page view.

## Trick 2: Adding an icon to the sidebar (sidebar_template.html)

Adding an icon to the sidebar is quite simple - simply add your .png file to your resources folder and use a relative link. Make sure you center it (and don't go over 128x128 px) or it will look terrible!

```html
<div class="sidebar">
    <div class="chart titled-box quick-links">
        <h2>Quick Links</h2>
        <div class="content">
           		<div class="artwork">
                	<center><img target="_blank" href="https://github.com/munki/munki" width="128" height="128" alt="Munki Github" class="artwork" src="custom/resources/MSC.png" />
                </div>
            </ol>
        </div>
    </div>
</div>
```

## Trick 3: Linking banners to Optional Installs (showcase_template.html)

This isn't really a trick, but more of a feature that isn't completely documented. You can link individual banners to specific items in your repository.

Below you will find three examples: All Categories, Music and iMovie. Make sure you add __.html__ to each item or it will not work.

```html
<div class="showcase">
    <div class="stage" onClick='stageClicked();'>
        <img href="categories.html" alt="Categories" src="custom/resources/App_Store_1.png" />
        <img href="category-Music.html" alt="Music Category" src="custom/resources/Making_Music.png" />
        <img href="detail-iMovie.html" alt="iMovie" src="custom/resources/iMovie.png" />
    </div>
</div>
```

![MSC Screenshot](/images/2015/05/MSC_SS.png "MSC Screenshot")


## Erik's Sweet Giveaway (Oprah Style)

Attached below are several banners that I have modified from the Mac App Store. These banners are the correct dimension (1158x200) and configured in a way so no matter how small MSC is, items will not be cut off. Enjoy!

![MSC Banner](/images/2015/05/1password.png "MSC Banner")
![MSC Banner](/images/2015/05/app_development.png "MSC Banner")
![MSC Banner](/images/2015/05/app_store_1.png "MSC Banner")
![MSC Banner](/images/2015/05/apps_for_photographers.png "MSC Banner")
![MSC Banner](/images/2015/05/apps_made_by_apple.png "MSC Banner")
![MSC Banner](/images/2015/05/autodesk_pixlr.png "MSC Banner")
![MSC Banner](/images/2015/05/autodesk_sketchbook.png "MSC Banner")
![MSC Banner](/images/2015/05/better_together.png "MSC Banner")
![MSC Banner](/images/2015/05/business_apps.png "MSC Banner")
![MSC Banner](/images/2015/05/clear.png "MSC Banner")
![MSC Banner](/images/2015/05/compressor.png "MSC Banner")
![MSC Banner](/images/2015/05/dayone.png "MSC Banner")
![MSC Banner](/images/2015/05/djay_pro.png "MSC Banner")
![MSC Banner](/images/2015/05/evernote.png "MSC Banner")
![MSC Banner](/images/2015/05/fantastical_2.png "MSC Banner")
![MSC Banner](/images/2015/05/final_cut_pro_x.png "MSC Banner")
![MSC Banner](/images/2015/05/garageband.png "MSC Banner")
![MSC Banner](/images/2015/05/get_stuff_done.png "MSC Banner")
![MSC Banner](/images/2015/05/ia_writer_pro.png "MSC Banner")
![MSC Banner](/images/2015/05/ibooks_author.png "MSC Banner")
![MSC Banner](/images/2015/05/imovie.png "MSC Banner")
![MSC Banner](/images/2015/05/keynote.png "MSC Banner")
![MSC Banner](/images/2015/05/logic_pro_x.png "MSC Banner")
![MSC Banner](/images/2015/05/mainstage.png "MSC Banner")
![MSC Banner](/images/2015/05/making_music.png "MSC Banner")
![MSC Banner](/images/2015/05/microsoft_onenote.png "MSC Banner")
![MSC Banner](/images/2015/05/motion.png "MSC Banner")
![MSC Banner](/images/2015/05/notability.png "MSC Banner")
![MSC Banner](/images/2015/05/notification_center_widgets.png "MSC Banner")
![MSC Banner](/images/2015/05/numbers.png "MSC Banner")
![MSC Banner](/images/2015/05/pages.png "MSC Banner")
![MSC Banner](/images/2015/05/pixelmator.png "MSC Banner")
![MSC Banner](/images/2015/05/reeder.png "MSC Banner")
![MSC Banner](/images/2015/05/skitch.png "MSC Banner")
![MSC Banner](/images/2015/05/twitter.png "MSC Banner")
![MSC Banner](/images/2015/05/wunderlist.png "MSC Banner")
![MSC Banner](/images/2015/05/xcode.png "MSC Banner")