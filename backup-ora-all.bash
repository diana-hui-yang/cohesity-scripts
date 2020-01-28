#!/bin/bash
#
# Name:         backup-ora-all.bash
#
# Function:     This script backup oracle in backup set. 
#		It can do incremental backup and use Oracle recovery catalog
#		It can do archive log backup only. The retention time is in days.
#		If the retention time is unlimit, specify unlimit. It only deletes
#		the backup files. It won't clean RMMAN catalog. Oracle cleans its 
# 		RMAN catalog. 
#
# Show Usage: run the command to show the usage
#
# Changes:
# 11/20/19 Diana Yang   New script
# 11/26/19 Diana Yang   Add incremental backup option and RMAN login option
# 12/01/19 Diana Yang   Add error checking
# 01/11/2020 Diana Yang   Add more channels capability
# 01/13/2020 Diana Yang   Add retention policy
# 01/28/2020 Diana Yang   Delete archive logs that are five days older   
#
#################################################################

. ~/.bash_profile

function show_usage {
echo "usage: backup-ora-all.bash -r <RMAN login> -h <host> -o <Oracle_sid> -a <archive only> -i <incremental level> -m <mount-prefix> -n <number of mounts> -p <number of channels> -e <retention>" 
echo " -r : RMAN login (example: \"rman target /\", optional)"
echo " -h : host (optional)" 
echo " -o : ORACLE_SID" 
echo " -a : arch (archivelog backup only, optional. default is database backup)"
echo " -i : Incremental level"
echo " -m : mount-prefix (like /mnt/ora)"
echo " -n : number of mounts"
echo " -p : number of channels (Optional, default is 4)"
echo " -e : Retention time (days to retain the backups, Optional when doing archivelog backup)"
}

while getopts ":r:h:o:a:i:m:n:p:e:" opt; do
  case $opt in
    r ) rmanlogin=$OPTARG;;
    h ) host=$OPTARG;;
    o ) oraclesid=$OPTARG;;
    a ) arch=$OPTARG;;
    i ) level=$OPTARG;;
    m ) mount=$OPTARG;;
    n ) num=$OPTARG;;
    p ) parallel=$OPTARG;;
    e ) retday=$OPTARG;;
  esac
done

#echo $oraclesid, $mount, $host, $num

# Check required parameters
if test $mount && test $oraclesid && test $num && test $retday
then
  :
else
  show_usage 
  exit 1
fi

if [[ $arch = "arch" || $arch = "Arch" || $arch = "ARCH" || $arch = "yes" || $arch = "Yes" || $arch = "YES" ]]; then
  echo "Only backup archive logs"
  archivelogonly=yes
else
  echo "Will backup database backup plus archive logs"

  if test $level
  then
    :
  else
    echo "incremental level was not specified"
    echo " "
    show_usage 
    exit 1
  fi
  
  if [[ $level -ne 0 && $level -ne 1 ]]; then
    echo "incremental level is set to be $level. Backup won't start"
    echo "incremental backup level needs to be either 0 or 1"
    echo " "
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
  echo "no input for parallel, set parallel to be 4."
  parallel=4
fi

if [[ -z $rmanlogin ]]; then
  rmanlogin="rman target /"
fi

echo "rmanlogin is \"$rmanlogin\""
echo "rmanlogin syntax can be like \"rman target /\" or"
#echo "\"rman target '\"sysbackup/<password>@<database connect string> as sysbackup\"' \""
echo "\"rman target sys/<password>@<database connect string> catalog <user>/<password>@<catalog>\""

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


runlog=$DIR/log/$host/$oraclesid.$DATE_SUFFIX.log
rmanlog=$DIR/log/$host/$oraclesid.rman.$DATE_SUFFIX.log
rmanloga=$DIR/log/$host/$oraclesid.archive.$DATE_SUFFIX.log
rmanfiled=$DIR/log/$host/$oraclesid.rman.$DATE_SUFFIX.rcv
rmanfilea=$DIR/log/$host/$oraclesid.archive.$DATE_SUFFIX.rcv

#echo $host $oracle_sid $mount $num

#trim log directory
find $DIR/log/$host -type f -mtime +7 -exec /bin/rm {} \;

if [ $? -ne 0 ]; then
  echo "del old logs in $DIR/log/$host failed" >> $runlog
  echo "del old logs in $DIR/log/$host failed"
  exit 2
fi

echo "check whether this database is up running"
runoid=`ps -ef | grep pmon | awk '{print $8}' | grep -i $oraclesid | awk -F "_" '{print $3}'`

arroid=($runoid)

len=${#arroid[@]}

j=0
for (( i=0; i<$len; i++ ))
do
  if [[ ${arroid[$i]} == ${oraclesid} ]]; then
    echo "Oracle database $oraclesid is up. Backup can start"
    j=1
  fi
done

if [[ $j -eq 0 ]]
then
  echo "Oracle database $oraclesid is not up. Backup will not start"
  exit 2
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
#echo "CONFIGURE retention policy to recovery window of $retday days;" >> $rmanfiled
#echo "Delete obsolete;" >> $rmanfiled
echo "   " >> $rmanfiled
echo "   " >> $rmanfilea
echo "RUN {" >> $rmanfiled
echo "RUN {" >> $rmanfilea

i=1
j=1
while [ $i -le $num ]; do
  if mountpoint -q "${mount}${i}"; then
    echo "$mount${i} is mount point"
    echo " "
	
    if [[ ! -d "${mount}${i}/$host/$oraclesid" ]]; then
       echo "Directory ${mount}${i}/$host/$oraclesid does not exist, create it"
       if mkdir -p ${mount}${i}/$host/$oraclesid; then
          echo "${mount}${i}/$host/$oraclesid is created"
       else
          echo "creating ${mount}${i}/$host/$oraclesid failed. There is a permission issue"
          exit 1
       fi
    fi

    if [[ $j -le $parallel ]]; then
	   echo "allocate channel fs$j device type disk format = '$mount$i/$host/$oraclesid/%d_%T_%U.bdf';" >> $rmanfiled
	   echo "allocate channel fs$j device type disk format = '$mount$i/$host/$oraclesid/%d_%T_%U.blf';" >> $rmanfilea
    fi

    i=$[$i+1]
    j=$[$j+1]


    if [[ $i -gt $num && $j -le $parallel ]]; then 
       i=1
    fi
  else
    echo "$mount${i} is not a mount point. Backup will not start"
	echo "The mount prefix may not be correct or"
	echo "The input of the number of mount points may exceed the actuall number of mount points"
	exit 1
  fi
done
echo "backup INCREMENTAL LEVEL $level CUMULATIVE database filesperset=1;" >> $rmanfiled
echo "sql 'alter system switch logfile';" >> $rmanfiled
echo "backup archivelog all archivelog until time 'sysdate-5' delete input;" >> $rmanfilea
i=1
j=1
while [ $i -le $num ]; do
  	
    if [[ $j -le $parallel ]]; then
	   echo "release channel fs$j;" >> $rmanfiled
	   echo "release channel fs$j;" >> $rmanfilea
	fi
    i=$[$i+1]
    j=$[$j+1]

    if [[ $i -gt $num && $j -le $parallel ]]; then 
       i=1
    fi
	
done
echo "}" >> $rmanfiled
echo "}" >> $rmanfilea
echo "exit;" >> $rmanfiled
echo "exit;" >> $rmanfilea

echo "finished creating rman file" >> $runlog
echo "finished creating rman file"
}

function backup {

echo "Database backup started at " `/bin/date '+%Y%m%d%H%M%S'`
echo "Database backup started at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog

$rmanlogin log $rmanlog @$rmanfiled

if [ $? -ne 0 ]; then
  echo "Database backup failed at " `/bin/date '+%Y%m%d%H%M%S'`
  echo "Database backup failed at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog
  while IFS= read -r line
  do
    echo $line
  done < $rmanlog 
  exit 1
else
  echo "Database backup finished at " `/bin/date '+%Y%m%d%H%M%S'`
  echo "Database backup finished at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog 
fi

}

function archive {

echo "Archive logs backup started at " `/bin/date '+%Y%m%d%H%M%S'`
echo "Archive logs backup started at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog

$rmanlogin log $rmanloga @$rmanfilea

if [ $? -ne 0 ]; then
  echo "Archive logs backup failed at " `/bin/date '+%Y%m%d%H%M%S'`
  echo "Archive logs backup failed at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog
  while IFS= read -r line
  do
    echo $line
  done < $rmanloga 
  exit 1
else
  echo "Archive logs backup finished at " `/bin/date '+%Y%m%d%H%M%S'`
  echo "Archive logs backup finished at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog 
fi
}


setup
create_rmanfile
if [[ $archivelogonly = "yes" ]]; then
  echo "archive logs backup only"
  archive
else
  echo "backup database plus archive logs"
  backup 
  archive
fi

if ! [[ "$retday" =~ ^[0-9]+$ ]]
then
   echo "$retday is not an integer. No data expiration after this backup"
else
   let retnewday=$retday+1
   echo "Clean old backup longer than $retnewday started at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog
   find ${mount}1/$host/$oraclesid -type f -mtime +$retnewday -exec /bin/rm -f {} \;
   find ${mount}1/$host/$oraclesid -depth -type d -empty -exec rmdir {} \;
fi
