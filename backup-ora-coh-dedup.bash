#!/bin/bash
#
# Name:         backup-ora-coh-dedup.bash
#
# Function:     This script backup oracle in backup set using Cohesity dedup library. 
#		It can do incremental backup and use Oracle recovery catalog
#		It can do archive log backup only. The retention time is in days.
#		If the retention time is unlimit, specify unlimit.  
#
# Show Usage: run the command to show the usage
#
# Changes:
# 03/07/19 Diana Yang   New script
#
#################################################################

function show_usage {
echo "usage: backup-ora-coh-dedup.bash -r <RMAN login> -h <host> -o <Oracle_sid> -a <archive only> -i <incremental level> -f <vip file> -v <view> -s <sbt home> -p <number of channels> -e <retention> -l <archive log keep days>" 
echo " -r : RMAN login (example: \"rman target /\", optional)"
echo " -h : host (optional)" 
echo " -o : ORACLE_SID" 
echo " -a : arch (archivelog backup only, optional. default is database backup)"
echo " -i : Incremental level"
echo " -f : file that has vip list"
echo " -v : Cohesity view"
echo " -s : Cohesity SBT library home"
echo " -p : number of channels (Optional, default is 4)"
echo " -e : Retention time (days to retain the backups, Optional when doing archivelog backup)"
echo " -l : Archive logs retain days (days to retain the local archivelogs before deleting them. default is 1 day)"
}

while getopts ":r:h:o:a:i:f:v:s:p:e:l:" opt; do
  case $opt in
    r ) rmanlogin=$OPTARG;;
    h ) host=$OPTARG;;
    o ) oraclesid=$OPTARG;;
    a ) arch=$OPTARG;;
    i ) level=$OPTARG;;
    f ) vipfile=$OPTARG;;
    v ) view=$OPTARG;;
	s ) sbthome=$OPTARG;;
    p ) parallel=$OPTARG;;
    e ) retday=$OPTARG;;
    l ) archretday=$OPTARG;;
  esac
done

#echo $oraclesid, $vipfile, $host, $view

# Check required parameters
if test $vipfile && test $oraclesid && test $view && test $retday && test $sbthome
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

if [[ -z $archretday  ]]; then
  echo "Only retain one day local archive logs"
  archretday=1
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

echo "get ORACLE_HOME"
oratabinfo=`grep -i $oraclesid /etc/oratab`

arrinfo=($oratabinfo)
leninfo=${#arrinfo[@]}

k=0
for (( i=0; i<$leninfo; i++))
do
   orasidintab=`echo ${arrinfo[$i]} | awk -F ":" '{print $1}'`
   orahomeintab=`echo ${arrinfo[$i]} | awk -F ":" '{print $2}'`
   if [[ $orasidintab == ${oraclesid} ]]; then    
      oracle_home=$orahomeintab
	  export ORACLE_HOME=$oracle_home
	  export PATH=$PATH:$ORACLE_HOME/bin
	  k=1
   fi
done

if [[ $k -eq 0 ]]
then
  echo "No Oracle sid $oraclesid information in /etc/oratab. Cannot determine ORACLE_HOME"
  exit 2
fi


export ORACLE_SID=$oraclesid 
}

function create_rmanfile {

echo "Create rman file" >> $runlog

echo "CONFIGURE DEFAULT DEVICE TYPE TO sbt_tape;" >> $rmanfiled
echo "CONFIGURE DEFAULT DEVICE TYPE TO sbt_tape;" >> $rmanfilea
echo "CONFIGURE CONTROLFILE AUTOBACKUP ON;" >> $rmanfiled
echo "CONFIGURE CONTROLFILE AUTOBACKUP OFF;" >> $rmanfilea
echo "CONFIGURE CONTROLFILE AUTOBACKUP FORMAT FOR DEVICE TYPE sbt_tape TO '%d_%F.ctl';" >> $rmanfiled
echo "CONFIGURE retention policy to recovery window of $retday days;" >> $rmanfiled
echo "   " >> $rmanfiled
echo "   " >> $rmanfilea

i=1
j=1
while [ $j -le $parallel ]; do

    while IFS= read -r line; do
	
	echo "Test whether IP $line can be connected"
	echo "Test whether IP $line can be connected" >> $runlog
	ping $line -c 2 | grep -i error
	
	if [ $? -ne 0 ]; then
	
	   if [[ $i -eq 1 ]]; then
	      echo "CONFIGURE CHANNEL DEVICE TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbthome/libsbt_6_linux-x86_64.so,SBT_PARMS=(mount_path=$line:/$view,vips=$line)';" >> $rmanfiled
#	      echo "Delete obsolete;" >> $rmanfiled
	      echo "RUN {" >> $rmanfiled
	      echo "RUN {" >> $rmanfilea
	   fi
	
       if [[ $j -le $parallel ]]; then
	      echo "allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbthome/libsbt_6_linux-x86_64.so,SBT_PARMS=(mount_path=$line:/$view,vips=$line)' format '%d_%T_%U.bdf';" >> $rmanfiled
	      echo "allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbthome/libsbt_6_linux-x86_64.so,SBT_PARMS=(mount_path=$line:/$view,vips=$line)' format '%d_%T_%U.blf';" >> $rmanfilea
       fi
	   i=$[$i+1]
       j=$[$j+1]
	else
	   echo "error: IP $line can't be connected. It may not be a valid IP. Skip this IP"
	   echo "error: IP $line can't be connected. It may not be a valid IP. Skip this IP" >> $runlog
	fi
     
    done < $vipfile

done

echo "backup INCREMENTAL LEVEL $level CUMULATIVE database filesperset=1;" >> $rmanfiled
echo "sql 'alter system switch logfile';" >> $rmanfiled
if [[ $archretday -eq 0 ]]; then
   echo "backup archivelog all format '%d_%T_%U.bdf' delete input;" >> $rmanfilea
else
   echo "backup archivelog all archivelog until time 'sysdate-$archretday' delete input;" >> $rmanfilea
fi
i=1
j=1
while [ $j -le $parallel ]; do

    while IFS= read -r line; do
	
    if [[ $j -le $parallel ]]; then
	   echo "release channel c$j;" >> $rmanfiled
	   echo "release channel c$j;" >> $rmanfilea
    fi
     
	i=$[$i+1]
    j=$[$j+1]
    
    done < $vipfile

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

grep -i error $runlog

if [ $? -eq 0 ]; then
   echo "Backup is successful. However there are IPs in $vipfile not correct"
   exit 1
fi
