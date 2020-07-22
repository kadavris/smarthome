#PREFIX = /tmp
USER = smarthome
GROUP = smarthome

DESTDIR = /etc/smarthome/cams
FILES_EXE = cam_cleaner.pl cam_event.pl cam_proxy.pl cam_service.pl cam_sync.pl
FILES_PLAIN = cam_cleaner.config.sample cam_common.config.sample cam_event.config.sample cam_proxy.config.sample cam_rtsp.config.sample cam_service.config.sample cam_sync.config.sample

FILES_SVC = cam_event.service cam_proxy@.service cam_service@.service cam_sync.service
SVC = cam_event cam_sync
SVCDEST = /etc/systemd/system

FILES_CRON = cam_hourly.cron
CRONDIR = /etc/cron.hourly

INSTPARMS = -D --verbose --compare --group=$(GROUP) --owner=$(USER)
MODE_PLAIN = ug=r,o-rwx
MODE_EXE = ug=rx,o-rwx

.PHONY: install
install: $(FILES_EXE) $(FILES_PLAIN) $(FILES_SVC) $(FILES_CRON) install_exe install_plain install_svc install_cron

.PHONY: install_exe
install_exe: $(FILES_EXE)
	install $(INSTPARMS) --target-directory="$(PREFIX)$(DESTDIR)" --mode=$(MODE_EXE) $(FILES_EXE)

.PHONY: install_plain
install_plain: $(FILES_PLAIN)
	install $(INSTPARMS) --target-directory="$(PREFIX)$(DESTDIR)" --mode=$(MODE_PLAIN) $(FILES_PLAIN)

.PHONY: install_svc
install_svc: $(FILES_SVC)
	install $(INSTPARMS) --target-directory="$(SVCDEST)" --mode=ug=rw,o-rwx --mode=$(MODE_PLAIN) --owner=root $(FILES_SVC)
	systemctl daemon-reload
	for s in $(SVC); do if systemctl is-active $$s; then systemctl restart $$s; else echo "Do not forget to (re)start $$s"; fi; done

.PHONY: install_cron
install_cron:
	install $(INSTPARMS) --target-directory="$(PREFIX)$(CRONDIR)" --mode=$(MODE_EXE) $(FILES_CRON)

.PHONY: uninstall
uninstall:
	rm -f $(PREFIX)$(DESTDIR)/$(FILES_EXE)
	rm -f $(PREFIX)$(DESTDIR)/$(FILES_PLAIN)
	rm -f $(PREFIX)$(SVCDEST)/$(FILES_SVC)
	rm -f $(PREFIX)$(CRONDIR)/$(FILES_CRON)
