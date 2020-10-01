# smarthome components
There are several sub-projects that I personally use inside my home
* IP_Cameras - Scripts for IP cameras recording, backup and housekeeping.
* mqtt - pure MQTT-related things
* reporters - tools for monitoring and alerts
* SIA-Ajax - rudimentary SIA monitoring station for logging purposes

## IP Cameras:
Runs partially as services (systemd) and partially from cron
* cam_service.pl - main component. service daemon which records single camera rtsp stream.  
* cam_cleaner.pl - keep footage directory to a specified minimum size. Run from cron or manually.
* cam_proxy.pl - Service daemon to provide a rtsp proxy, allowing multiple connections for dumb cameras.  
* cam_event.pl - Event processor/initiator. Can be used in mqtt subscriber mode.
* cam_sync.pl - Another service daemon. Runs rclone to backup entire event directory to cloud or remote storage.

For details see inside the folder.

## mqtt
Currently hosting only one python tool that can do almost all requests possible.
Two modes available:
* Command line: classics for quick publish or get a single topic. Or more.
* stdin/pipe mode. It listens for json commands on standard input. Great for long sessions with multiple goals.

## reporters
* mqtt-boot-send - inteneded to run on boot, pushing basic host info once
* mqtt-power - Power appliances monitoring via NUT's upsc command line interface. Many options to report.  
* mqtt-storage-sd-reports - Collect data from nagios check_ide_smart and smartctl.

## SIA-Ajax
Well. It sits as a service, listening to incoming packets, sendimg ACKs and logging. Nothing more. Maybe later.