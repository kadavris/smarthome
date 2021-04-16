#!/bin/bash
# This script is used to create a Windows service for running reporder in background
# CygWin is assumed to be installed
svcname='mqtt-storage-sd-reports'

if [ "$1" == "" ]
then
  echo 'Use with <path to log folder> argument'
  echo Run it from the folder where reporter scripts live
  echo example:
  echo $0 \"/cygdrive/d/log\"
  exit
fi

logdir="$1"
b=`which bash | head -1`
p=`which python3 | head -1`
cwd=`pwd`

# cygwin tends to do a lot of nested symplinks to the most recent executable
while [ -L "$p" ]
do
  p=`readlink "$p"`
done

cygrunsrv -V -E $svcname
cygrunsrv -V -R $svcname

cygrunsrv -V -I $svcname -p "${p}.exe" -a "$cwd/$svcname -l 20" -1 "$logdir/$svcname.log" -2 "$logdir/$svcname.log"

cygrunsrv -V -S $svcname
