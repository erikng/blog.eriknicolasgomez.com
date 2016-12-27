---
layout: post
title: "Outset Luggage Companion"
description: "My first macadmin post."
tags: [Apple Configurator 2, logging, macOS, OS X]
comments: true
---

luggage.local

```bash
l_usr_local_outset_custom: l_usr_local
	@sudo mkdir -p ${WORK_D}/usr/local/outset/custom
	@sudo chown -R root:wheel ${WORK_D}/usr/local/outset/custom
	@sudo chmod -R 755 ${WORK_D}/usr/local/outset/custom

l_usr_local_outset_everyboot_scripts: l_usr_local
	@sudo mkdir -p ${WORK_D}/usr/local/outset/everyboot-scripts
	@sudo chown -R root:wheel ${WORK_D}/usr/local/outset/everyboot-scripts
	@sudo chmod -R 755 ${WORK_D}/usr/local/outset/everyboot-scripts
	
l_usr_local_outset_firstboot_packages: l_usr_local
	@sudo mkdir -p ${WORK_D}/usr/local/outset/firstboot-packages
	@sudo chown -R root:wheel ${WORK_D}/usr/local/outset/firstboot-packages
	@sudo chmod -R 755 ${WORK_D}/usr/local/outset/firstboot-packages
	
l_usr_local_outset_firstboot_scripts: l_usr_local
	@sudo mkdir -p ${WORK_D}/usr/local/outset/firstboot-scripts
	@sudo chown -R root:wheel ${WORK_D}/usr/local/outset/firstboot-scripts
	@sudo chmod -R 755 ${WORK_D}/usr/local/outset/firstboot-scripts
	
l_usr_local_outset_login_every: l_usr_local
	@sudo mkdir -p ${WORK_D}/usr/local/outset/login-every
	@sudo chown -R root:wheel ${WORK_D}/usr/local/outset/login-every
	@sudo chmod -R 755 ${WORK_D}/usr/local/outset/login-every
	
l_usr_local_outset_login_once: l_usr_local
	@sudo mkdir -p ${WORK_D}/usr/local/outset/login-once
	@sudo chown -R root:wheel ${WORK_D}/usr/local/outset/login-once
	@sudo chmod -R 755 ${WORK_D}/usr/local/outset/login-once
	
pack-usr-local-outset-custom-%: % l_usr_local_outset_custom
	@sudo ${INSTALL} -m 755 -g wheel -o root "${<}" ${WORK_D}/usr/local/outset/custom
	
pack-usr-local-outset-everyboot-scripts-%: % l_usr_local_outset_everyboot_scripts
	@sudo ${INSTALL} -m 755 -g wheel -o root "${<}" ${WORK_D}/usr/local/outset/everyboot-scripts

pack-usr-local-outset-firstboot-packages-%: % l_usr_local_outset_firstboot_packages
	@sudo ${INSTALL} -m 755 -g wheel -o root "${<}" ${WORK_D}/usr/local/outset/firstboot-packages

pack-usr-local-outset-firstboot-scripts-%: % l_usr_local_outset_firstboot_scripts
	@sudo ${INSTALL} -m 755 -g wheel -o root "${<}" ${WORK_D}/usr/local/outset/firstboot-scripts

pack-usr-local-outset-login-every-%: % l_usr_local_outset_login_every
	@sudo ${INSTALL} -m 755 -g wheel -o root "${<}" ${WORK_D}/usr/local/outset/login-every
	
pack-usr-local-outset-login-once-%: % l_usr_local_outset_login_once
	@sudo ${INSTALL} -m 755 -g wheel -o root "${<}" ${WORK_D}/usr/local/outset/login-once
```

Makefile

```makefile
USE_PKGBUILD=1
include /usr/local/share/luggage/luggage.make
PACKAGE_VERSION=1.1
TITLE=OutsetMakefileExample
REVERSE_DOMAIN=com.github.outset
PAYLOAD= \
		pack-usr-local-outset-custom-sample.py \
		pack-usr-local-outset-everyboot-scripts-sample_script_every.py \
		pack-usr-local-outset-firstboot-packages-sample_pkg.dmg \
		pack-usr-local-outset-firstboot-scripts-sample_script_firstboot.py \
		pack-usr-local-outset-login-every-sample_script_every.py \
		pack-usr-local-outset-login-once-sample_script_once.py
```