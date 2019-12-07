#!/bin/bash
#
# Name:         backup-ora-full.bash
#
# Function:     This script backup oracle database in backup set. 
#				The number of channels will not exceed the number of mounts
#
# Show Usage: run the command to show the usage
#
# Changes:
# 11/20/19 Diana Yang   New script
# 11/30/19 Diana Yang   Add error checking
#
#################################################################

. ~/.bash_profile

function show_usage {
echo "usage: backup-ora-full.bash -h <host> -o <Oracle_sid> -m <mount-prefix> -n <number of mounts> -p <number of channels>" 
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
  echo "No input for host, set current server $host as host"
fi

if test $parallel
then 
  :
else
  echo "no input for parallel, set parallel to be 4." 
  parallel=4
fi

if [[ $parallel -lt $num ]]; 
then
  echo "When paralle is less than the number of mount points, the backup channels use parallel parameter which is $parallel"
else 
  echo "When paralle is equal or higher than the number of mount points, the backup channles use the number of mount points which is $num"
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


runlog=$DIR/log/$host/$oraclesid.$DATE_SUFFIX.log
rmanlog=$DIR/log/$host/$oraclesid.rman.$DATE_SUFFIX.log
rmanfile=$DIR/log/$host/$oraclesid.rman.$DATE_SUFFIX.rcv

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
    echo "Oracle database $oraclesid is up. Backup will start"
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
echo "Create rman file"

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
          echo "${mount}${i}/$host/$oraclesid directory is created"
       else
          echo "create ${mount}${i}/$host/$oraclesid failed. There is a permission issue"
          exit 1
       fi
    fi

    if [[ $i -le $parallel ]]; then
	   echo "allocate channel fs$i device type disk maxopenfiles = 1  format = '$mount$i/$host/$oraclesid/%d-%T-s%s-p%p-%U';" >> $rmanfile
	fi
    i=$[$i+1]
  else
    echo "$mount${i} is not a mount point. Backup cannot start"
	echo "The mount prefix may not be correct or"
	echo "The input of the number of mount points may exceed the actuall number of mount points"
	exit 1
  fi
done
echo "backup database filesperset=4 plus archivelog delete input;" >> $rmanfile
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
echo "finished creating rman file"
}

function backup {

echo "backup started at " `/bin/date '+%Y%m%d%H%M%S'` 
echo "backup started at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog

rman target / log $rmanlog @$rmanfile

if [ $? -ne 0 ]; then
  echo "full backup failed at " `/bin/date '+%Y%m%d%H%M%S'`
  echo "full backup failed at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog
  while IFS= read -r line
  do
    echo $line
  done < $rmanlog 
  exit 1
else
  echo "full backup finished at " `/bin/date '+%Y%m%d%H%M%S'`
  echo "full backup finished at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog 
fi

}

setup
create_rmanfile
backup 
