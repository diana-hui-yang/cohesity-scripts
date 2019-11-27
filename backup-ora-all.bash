#!/bin/bash
#
# Name:         backup-ora-all.bash
#
# Function:     This script backup oracle in backup set. 
#				The number of channels will not exceed the number of mounts
#				It can do incremental backup and use Oracle recovery catalog
#				It can do archive log backup only
#
# Show Usage: run the command to show the usage
#
# Changes:
# 11/20/19 Diana Yang   New script
# 11/26/19 Diana Yang   Add incremental backup option and RMAN login option
#
#################################################################

. /home/oracle/.bash_profile

function show_usage {
echo "usage: backup-ora-all.bash -r <RMAN login> -h <host> -o <Oracle_sid> -a <archive only> -i <incremental level> -m <mount-prefix> -n <number of mounts> -p <number of channels>" 
echo " -r : RMAN login (example: \"rman target /\", optional)"
echo " -h : host (optional)" 
echo " -o : ORACLE_SID" 
echo " -a : arch (archivelog backup only, optional. default is database backup)"
echo " -i : Incremental level"
echo " -m : mount-prefix (like /mnt/ora)"
echo " -n : number of mounts"
echo " -p : number of channels (optional, default is 4)"
}

while getopts ":r:h:o:a:i:m:n:p:" opt; do
  case $opt in
    r ) rmanlogin=$OPTARG;;
    h ) host=$OPTARG;;
    o ) oraclesid=$OPTARG;;
	a ) arch=$OPTARG;;
	i ) level=$OPTARG;;
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

if [[ $arch = "arch" || $arch = "Arch" || $arch = "ARCH" ]]; then
  echo "archivelog only backup"
  archivelogonly=yes
else
  echo "database backup plus archive logs backup"
  
  if test $level
  then
    :
  else
    show_usage 
    exit 1
  fi
  
  if [[ $level -ne 0 && $level -ne 1 ]]; then
    echo "incremental backup level needs to be either 0 or 1"
    show_usage 
    exit 1
  fi
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

if [[ -z $rmanlogin ]]; then
  rmanlogin="rman target /"
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
rmanfiled=$DIR/log/$host/$oraclesid.rman.$DATE_SUFFIX.rcv
rmanfilea=$DIR/log/$host/$oraclesid.archive.$DATE_SUFFIX.rcv

#echo $host $oracle_sid $mount $num

#trim log directory
find $DIR/log/$host -type f -mtime +7 -exec /bin/rm {} \;

if [ $? -ne 0 ]; then
    echo "del old logs in $DIR/log/$host failed" >> $runlog
    exit 1
fi

export ORACLE_SID=$oraclesid 
}

function create_rmanfile {

echo "Create rman file" >> $runlog

echo "CONFIGURE DEFAULT DEVICE TYPE TO disk;" >> $rmanfiled
echo "CONFIGURE DEFAULT DEVICE TYPE TO disk;" >> $rmanfilea
echo "CONFIGURE CONTROLFILE AUTOBACKUP ON;" >> $rmanfiled
echo "CONFIGURE CONTROLFILE AUTOBACKUP ON;" >> $rmanfilea
echo "CONFIGURE CONTROLFILE AUTOBACKUP FORMAT FOR DEVICE TYPE DISK TO '${mount}1/$host/$oraclesid/%d_%F.ctl';" >> $rmanfiled
echo "CONFIGURE CONTROLFILE AUTOBACKUP FORMAT FOR DEVICE TYPE DISK TO '${mount}1/$host/$oraclesid/%d_%F.ctl';" >> $rmanfilea
#echo "CONFIGURE DEVICE TYPE DISK PARALLELISM $parallel BACKUP TYPE TO BACKUPSET;" >> $rmanfiled
echo "   " >> $rmanfiled
echo "   " >> $rmanfilea
echo "RUN {" >> $rmanfiled
echo "RUN {" >> $rmanfilea

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
	   echo "allocate channel fs$i device type disk maxopenfiles = 1  format = '$mount$i/$host/$oraclesid/%d-%T-s%s-p%p-%U';" >> $rmanfiled
	   echo "allocate channel fs$i device type disk maxopenfiles = 1  format = '$mount$i/$host/$oraclesid/%d-%T-s%s-p%p-%U';" >> $rmanfilea
	fi
    i=$[$i+1]
  else
    echo "$mount${i} is not a mount point, exit"
	exit
  fi
done
echo "backup INCREMENTAL LEVEL $level CUMULATIVE database plus archivelog delete input;" >> $rmanfiled
echo "backup archivelog all delete input;" >> $rmanfilea
i=1
while [ $i -le $num ]; do
  	
    if [[ $i -le $parallel ]]; then
	   echo "release channel fs$i;" >> $rmanfiled
	   echo "release channel fs$i;" >> $rmanfilea
	fi
    i=$[$i+1]
	
done
echo "}" >> $rmanfiled
echo "}" >> $rmanfilea
echo "exit;" >> $rmanfiled
echo "exit;" >> $rmanfilea

echo "finished creating rman file" >> $runlog
}

function backup {

echo "backup started at " `/bin/date '+%Y%m%d%H%M%S'` 

rman target / log $rman1log @$rmanfiled

echo "backup finished at " `/bin/date '+%Y%m%d%H%M%S'`
}

function archive {
echo "backup started at " `/bin/date '+%Y%m%d%H%M%S'` 

rman target / log $rman1log @$rmanfilea

echo "backup finished at " `/bin/date '+%Y%m%d%H%M%S'`
}


setup
create_rmanfile
if [[ $archivelogonly = "yes" ]]; then
  echo "archive logs backup only"
  archive
else
  echo "backup database plus archive logs"
  backup 
fi
