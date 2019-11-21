#!/bin/bash
#
# Name:         backup.bash
#
# Function:     This script backup oracle in backup set. 
#
# Show Usage: run the command to show the usage
#
# Changes:
# 11/20/19 Diana Yang   New script
#
#################################################################

. /home/oracle/.bash_profile

function show_usage {
echo "usage: backup.bash -h <host> -o <Oracle_sid> -m <mount-prefix> -n <number of mounts> -p <number of channels>" 
echo " -h : host (optional)"  
echo " -o : ORACLE_SID" 
echo " -m : mount-prefix (like /mnt/ora)"
echo " -n : number of mounts"
echo " -p : number of channels (optional, default is 4)"
}

while getopts ":h:o:m:n:p:" opt; do
  case $opt in
    h ) host=$OPTARG;;
    o ) oraclesid=$OPTARG;;
	m ) mount=$OPTARG;;
	n ) num=$OPTARG;;
	p ) parallel=$OPTARG;;
  esac
done

#echo $oraclesid, $mount, $host, $num

# Check required parameters
if test $mount && test $oraclesid && test $num
then
  :
else
  show_usage 
  exit 1
fi

function setup {
if test $host
then
  :
else
  host=`hostname -s`
fi

if test $parallel
then
  :
else
  parallel=4
fi

DATE_SUFFIX=`/bin/date '+%Y%m%d%H%M%S'`
echo $DATE_SUFFIX

DIRcurrent=$0
DIR=`echo $DIRcurrent |  awk 'BEGIN{FS=OFS="/"}{NF--; print}'`
if [[ $DIR = '.' ]]; then
   DIR=`pwd`
fi

if [[ ! -d $DIR/log/$host ]]; then
    echo " $DIR/log/$host does not exist, create it"
    mkdir -p $DIR/log/$host
fi


runlog=$DIR/log/$host/$oraclesid.$DATE_SUFFIX.log
rman1log=$DIR/log/$host/$oraclesid.rman.$DATE_SUFFIX.log
rmanfile=$DIR/log/$host/$oraclesid.rman.$DATE_SUFFIX.rcv

#echo $host $oracle_sid $mount $num

export ORACLE_SID=$oraclesid 
}

function create_rmanfile {

echo "Create rman file" >> $runlog

echo "CONFIGURE DEFAULT DEVICE TYPE TO disk;" >> $rmanfile
echo "CONFIGURE CONTROLFILE AUTOBACKUP ON;" >> $rmanfile
echo "CONFIGURE CONTROLFILE AUTOBACKUP FORMAT FOR DEVICE TYPE DISK TO '${mount}1/$host/$oraclesid/%d_%F.ctl';" >> $rmanfile
echo "CONFIGURE DEVICE TYPE DISK PARALLELISM $parallel BACKUP TYPE TO BACKUPSET;" >> $rmanfile
echo "   " >> $rmanfile
echo "RUN {" >> $rmanfile

i=1
while [ $i -le $num ]; do
  if mountpoint -q "${mount}${i}"; then
	echo "$mount${i} is mount point"
    echo " "
	
	if [[ ! -d "${mount}${i}/$host/$oraclesid" ]]; then
       echo "Directory ${mount}${i}/$host/$oraclesid does not exist, create it"
       if mkdir -p ${mount}${i}/$host/$oraclesid; then
          echo "$COHESITY_DIR_PATH2 is created"
       fi
    fi

    if [[ $i -le $parallel ]]; then
	   echo "allocate channel fs$i device type disk  format = '$mount$i/$host/$oraclesid/%d-%T-s%s-p%p-%U';" >> $rmanfile
	fi
    i=$[$i+1]
  fi
done
echo "backup database plus archivelog delete input maxopenfiles 1;" >> $rmanfile
i=1
while [ $i -le $num ]; do
  	
    if [[ $i -le $parallel ]]; then
	   echo "release channel fs$i;" >> $rmanfile
	fi
    i=$[$i+1]
	
done
echo "}" >> $rmanfile
echo "exit;" >> $rmanfile

echo "finished creating rman file" >> $runlog
}

function backup {

echo "backup started at " `/bin/date '+%Y%m%d%H%M%S'` 

rman target / log $rman1log @$rmanfile

echo "backup finished at " `/bin/date '+%Y%m%d%H%M%S'`
}

setup
create_rmanfile
backup 
