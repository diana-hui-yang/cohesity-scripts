#!/bin/bash
#
# Name:         prepare-restore.bash
#
# Function:     This script needs root privilege or sudoers for oracle to run mount command   
#		It mounts the same Cohesity view on Linux server using Cohesity VIPs.
#		The number of mounts is the number of VIPs in vip-list file
#
# Show Usage: run the command to show the usage
#
# Changes:
# 06/15/20 Diana Yang   New script
# 06/22/20 Diana Yang   Add more checking
#
#################################################################

function show_usage {
echo "usage: prepare-restore.bash -f <vip file> -u <cohesity user> -d <user domain> -v <production view> -n <restore view> -j <job name> -m <mount-prefix> -t <point in time>"
echo " -f : file that has vip list"
echo " -u : username: username to authenticate to Cohesity cluster"
echo " -d : domain: (optional) domain of username, defaults to local"
echo " -v : Cohesity view for Oracle backup"
echo " -n : Cohesity view for Oracle restore. The name should have restore in it"
echo " -j : jobname: name of protection job to run, exmaple "snap view""
echo " -m : mount-prefix (The name should have restore in it. like /coh/orarestore)"
echo " -t : (optional) select backup version before specified date, defaults to latest backup, format \"2020-04-18 18:00:00\")"
}

while getopts ":f:u:d:v:n:j:m:t:" opt; do
  case $opt in
    f ) vipfile=$OPTARG;;
    u ) user=$OPTARG;;
    d ) dom=$OPTARG;;
    v ) sview=$OPTARG;;
    n ) tview=$OPTARG;;
    j ) job=$OPTARG;;
    m ) mount=$OPTARG;;
    t ) otime=$OPTARG;;
  esac
done

#echo  $vipfile, $tview, $mount, $job
#exit

# Check required parameters
if test $vipfile && test $user && test $sview && test $tview && test $mount
then
  :
else
  show_usage 
  exit 1
fi

if test -f $vipfile
then
   echo "file $vipfile provided exist, script continue"
else 
   echo "file $vipfile provided does not exist"
   exit 1
fi

if [[ $tview = *restore* ]]; then
   echo "tview naming is correct. It has restore in it"
else
   echo "tview name needs to be changed. It should has \"restore\" in it"
   exit 1
fi

if [[ -z $job ]]; then
   show_usage
   exit 1
else
   job=\"${job}\"
fi

DATE_SUFFIX=`/bin/date '+%Y%m%d%H%M%S'`
#echo $DATE_SUFFIX    

DIRcurrent=$0
DIR=`echo $DIRcurrent |  awk 'BEGIN{FS=OFS="/"}{NF--; print}'`
if [[ $DIR = '.' ]]; then
  DIR=`pwd`
fi

if [[ ! -d $DIR/log/$host ]]; then
  echo " $DIR/log/$host does not exist, create it"
  mkdir -p $DIR/log/$host
  
  if [ $? -ne 0 ]; then
    echo "create log directory $DIR/log/$host failed. There is a permission issue"
    exit 1
  fi
fi


runlog=$DIR/log/runlog-$tview.$DATE_SUFFIX.log
deletelog=$DIR/log/deleteview-$tview.$DATE_SUFFIX.log
clonelog=$DIR/log/cloneview-$tview.$DATE_SUFFIX.log
deleteview=$DIR/log/deleteview-$tview.$DATE_SUFFIX.bash
cloneview=$DIR/log/clone-view-$tview.$DATE_SUFFIX.bash

#trim log directory
find $DIR/log/$host -type f -mtime +7 -exec /bin/rm {} \;

if [ $? -ne 0 ]; then
  echo "del old logs in $DIR/log/$host failed" >> $runlog
  echo "del old logs in $DIR/log/$host failed"
  exit 2
fi

##umount old mount
function umount_view {
echo "umount old mount points"
i=1  
while IFS= read -r ip; do
  
  ip=`echo $ip | xargs echo -n`    	
  echo "Check whether IP $ip can be connected"

  if [[ -n $ip ]]; then
     return=`/bin/ping $ip -c 2`

#    echo "return is $return"
     if echo $return | grep -q error; then
        echo "error: IP $ip can't be connected. It may not be a valid IP. Skip this IP"	 
     else
        echo "IP $ip can be connected"
		iptrue=$ip
        if mountpoint -q "${mount}$i"; then
            if [[ ${mount}$i = *restore* ]]; then
               echo "${mount}$i is a restore mount point, will umount it"
               sudo umount ${mount}$i
            else
               echo "${mount}$i name does not have restore in it. may be used for backup."
               echo "change the name to have \"restore\" in it"
               exit 1 
            fi
        else
            echo "${mount}}$i is not a mount point. No need to unount it"
	fi
              
      fi
    i=$[$i+1]
  fi
            
done < $vipfile
}

#mount them back
function mount_view {
echo "mount cloned cohesity view $tview"
i=1  
while IFS= read -r ip; do

  if [[ ! -d "${mount}$i" ]]; then
    echo "Directory ${mount}$i does not exist, create it"
    if mkdir -p ${mount}$i; then
        echo "${mount}$i is created"
    else
        echo "creating ${mount}$i failed. There is a permission issue or old mount points no longer valid"
        echo "run "df -h" or "mount" to verify"
        exit 1
    fi
  fi
    
  ip=`echo $ip | xargs echo -n`    	
  echo "Check whether IP $ip can be connected"

  if [[ -n $ip ]]; then
    return=`/bin/ping $ip -c 2`

#   echo "return is $return"
    if echo $return | grep -q error; then
       echo "error: IP $ip can't be connected. It may not be a valid IP. Skip this IP"	 
    else
       echo "IP $ip can be connected"
   	  sudo  mount -o intr,hard,rsize=1048576,wsize=1048576,proto=tcp,vers=3 ${ip}:/${tview} ${mount}$i
    fi
              
    i=$[$i+1]
  fi
            
done < $vipfile
}

function refresh_view {
#refresh cohesity view
echo "delete Cohesity View $tview"
echo "$DIR/deleteView.py -s $iptrue -u $user -d $dom -v $tview" > $deleteview
chmod 750 $deleteview 
echo "clone view $sview to view $tview"
if [[ -z $otime ]]; then
    echo "$DIR/cloneView.py -s $iptrue -u $user -d $dom -v $sview -n $tview -j $job -w" > $cloneview
else
    echo "$DIR/cloneView.py -s $iptrue -u $user -d $dom -v $sview -n $tview -j $job -b -f '$otime' -w" > $cloneview
fi
chmod 750 $cloneview

echo "delete view $tview started at " `/bin/date '+%Y%m%d%H%M%S'` 
$deleteview 
echo "delete view $tview finished at " `/bin/date '+%Y%m%d%H%M%S'`

echo "clone view $tview started at " `/bin/date '+%Y%m%d%H%M%S'` 
$cloneview 
if [ $? -ne 0 ]; then
  echo "clone view $tview failed at " `/bin/date '+%Y%m%d%H%M%S'`
  exit 1
else
  echo "clone view $tview finished at " `/bin/date '+%Y%m%d%H%M%S'`
fi
}
umount_view
refresh_view
mount_view

ls -ld ${mount}1

echo "Need to change the permission to Oracle if it is not set up yet"
