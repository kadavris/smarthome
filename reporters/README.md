## reporters
* mqtt-boot-send - inteneded to run on boot, pushing basic host info once
* mqtt-power - Power appliances monitoring via NUT's upsc command line interface.  
  See reporters.ini.sample [power] section for configuration options
  Basically it runc upsc in loop and logs and/or pushes the data to mqtt.  
  Require python, NUT, mqtt
* mqtt-storage-sd-reports - Collect data from SDD/HDD S.M.A.R.T
  See reporters.ini.sample [storage] section for configuration options
  You can configure it to use nagios check_ide_smart and/or smartctl.
  smartctl will provide much more comprehensive data for gaze upon and analyze  
* mqtt-storage-sd-reports-win-svc-create.sh - this script simplifies Windows service creation
* hassio-sample-sensors-server-storage.yaml - sample storage reporting yaml config for home-assistant
* hassio-sample-sensors-server-power.yaml - sample power reporting yaml config for home-assistant
