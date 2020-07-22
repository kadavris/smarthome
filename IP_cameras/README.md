# smarthome components
## Scripts for IP cameras recording, backup and housekeeping.
## Short description:
* cam_service.pl - main component. service daemon which records single camera rtsp stream.  
* cam_cleaner.pl - keep footage to a specified minimum size. Run from cron or manually.
* cam_proxy.pl - Service daemon to provide a rtsp proxy, allowing multiple connections for dumb cameras.  
* cam_event.pl - Event processor/initiator.  
* cam_sync.pl - Another service daemon. Runs rclone to backup entire event directory to cloud or remote storage.

## Detailed overview
The daemons run using 'smarthome' username and group. Change stuff to your preference before activating the services.

### cam_service:
Main workhorse. Uses ffmpeg to suck in stream from camera and save into neatly sized clips for later.
Start separate services via cam_service@<CAMID>  
Run with -h switch to get help   
Main configuration is in the cam_service.config.  
It include cam_common.config for base settings and cam_rtsp.config for camera-specific stuff.

### cam_event:
Main purpose is to hardlink the footage of specified cameras around the current time into the event directory.  
This creates series of existing clips starting N seconds _before_ the current time.  
Then it loops and waits and when a when a fresh clip detected it links it too.  
Repeating for another N seconds of footage is there.  
By making this happen the user may see what got the event to run at the first place and what happened some time after.  
When run manually it just do that. Or if -p=on switch is used it do it job for unlimited time until persistent-recording flag is gone.  
When run with -m switch it runs as a daemon, connect to a MQTT server and subscribe to specified topic, waiting for event to come.  
When triggered it forks to do actual job and quickly return to event listener.

### cam_sync:
Another service daemon. When sync flag detected it runs rclone to backup entire event directory to cloud or remote storage.  
Must be run from account owning rclone's configuration.

### cam_cleaner:
Cleans up old recordings. Expected to be run from cron.hourly. Script included.

### cam_proxy:
The idea is to make it possible for dumb cameras to be viewed and recorded in background at the same time.  
Yet it seems that many cheap chinese cameras have broken rtsp implementation, so live555 constantly whines
about inconsistensies and usually re-stream broken picture.  
Maybe it is in fact live555's problem as ffmpeg works just fine.
This stuff is disabled by default and you don't need it if your camera(s) support multiple rtsp connections

