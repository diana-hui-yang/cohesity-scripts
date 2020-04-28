#!/bin/bash
#
# Name:         backup-ora-coh-nfs.bash
#
# Function:     This script backup oracle in backup set using nfs mount. 
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
# 02/24/2020 Diana Yang   get ORACLE_HOME from /etc/oratab file 
# 03/01/2020 Diana Yang   Delete archive logs by specified time 
# 03/06/2020 Diana Yang   Only backup control file after full/incremental backup 
# 03/07/2020 Diana Yang   Rename the script to backup-ora-coh-nfs.bash 
# 04/07/2020 Diana Yang   Better support for RAC database
#
#################################################################

function show_usage {
echo "usage: backup-ora-coh-nfs.bash -r <RMAN login> -h <host> -o <Oracle_sid> -a <archive only> -i <incremental level> -m <mount-prefix> -n <number of mounts> -p <number of channels> -e <retention> -l <archive log keep days>" 
echo " -r : RMAN login (example: \"rman target /\", optional)"
echo " -h : host (optional)" 
echo " -o : ORACLE_SID" 
echo " -a : arch (yes means archivelogonly, no means database backup plus archivelog)"
echo " -i : Incremental level"
echo " -m : mount-prefix (like /mnt/ora)"
echo " -n : number of mounts"
echo " -p : number of channels (Optional, default is 4)"
echo " -e : Retention time (days to retain the backups)"
echo " -l : Archive logs retain days (days to retain the local archivelogs before deleting them. default is 1 day)"
}

while getopts ":r:h:o:a:i:m:n:p:e:l:" opt; do
  case $opt in
    r ) rmanlogin=$OPTARG;;
    h ) host=$OPTARG;;
    o ) dbname=$OPTARG;;
    a ) arch=$OPTARG;;
    i ) level=$OPTARG;;
    m ) mount=$OPTARG;;
    n ) num=$OPTARG;;
    p ) parallel=$OPTARG;;
    e ) retday=$OPTARG;;
    l ) archretday=$OPTARG;;
  esac
done

#echo $dbname, $mount, $host, $num

# Check required parameters
if test $mount && test $dbname && test $num && test $retday && test $arch
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


runlog=$DIR/log/$host/$dbname.$DATE_SUFFIX.log
rmanlog=$DIR/log/$host/$dbname.rman.$DATE_SUFFIX.log
rmanloga=$DIR/log/$host/$dbname.archive.$DATE_SUFFIX.log
rmanfiled=$DIR/log/$host/$dbname.rman.$DATE_SUFFIX.rcv
rmanfiled_b=$DIR/log/$host/$dbname.rman_b.$DATE_SUFFIX.rcv
rmanfiled_e=$DIR/log/$host/$dbname.rman_e.$DATE_SUFFIX.rcv
rmanfilea=$DIR/log/$host/$dbname.archive.$DATE_SUFFIX.rcv
rmanfilea_b=$DIR/log/$host/$dbname.archive_b.$DATE_SUFFIX.rcv
rmanfilea_e=$DIR/log/$host/$dbname.archive_e.$DATE_SUFFIX.rcv

#echo $host $oracle_sid $mount $num

#trim log directory
find $DIR/log/$host -type f -mtime +7 -exec /bin/rm {} \;

if [ $? -ne 0 ]; then
  echo "del old logs in $DIR/log/$host failed" >> $runlog
  echo "del old logs in $DIR/log/$host failed"
  exit 2
fi

echo "check whether this database is up running"
runoid=`ps -ef | grep pmon | awk '{print $8}' | grep -i $dbname | awk -F "pmon" '{print $2}'`

arroid=($runoid)

len=${#arroid[@]}

j=0
for (( i=0; i<$len; i++ ))
do
   oracle_sid=${arroid[$i]}
   oracle_sid=${oracle_sid:1:${#oracle_sid}-1}
   lastc=${oracle_sid: -1}
   if [[ $oracle_sid == ${dbname} ]]; then
      echo "Oracle database $dbname is up on $host. Backup can start"
      yes_oracle_sid=$dbname
      j=1
   else
      if [[ $lastc =~ ^[0-9]+$ ]]; then
         if [[ ${oracle_sid::-1} == ${dbname} ]]; then
            echo "Oracle database $dbname is up on $host. Backup can start"
            yes_oracle_sid=$oracle_sid
    	    j=1
         fi
      fi 
   fi
done

if [[ $j -eq 0 ]]
then
  echo "Oracle database $dbname is not up. Backup will not start"
  exit 2
fi

echo "get ORACLE_HOME"
oratabinfo=`grep -i $yes_oracle_sid /etc/oratab`

if [[ -z $oratabinfo ]]; then
  echo "No Oracle sid $yes_oracle_sid information in /etc/oratab. Cannot determine ORACLE_HOME"
  exit 2
fi

arrinfo=($oratabinfo)
leninfo=${#arrinfo[@]}

k=0
for (( i=0; i<$leninfo; i++))
do
   orasidintab=`echo ${arrinfo[$i]} | awk -F ":" '{print $1}'`
   orahomeintab=`echo ${arrinfo[$i]} | awk -F ":" '{print $2}'`
   if [[ $orasidintab == ${yes_oracle_sid} ]]; then    
      oracle_home=$orahomeintab
      export ORACLE_HOME=$oracle_home
      export PATH=$PATH:$ORACLE_HOME/bin
      k=1
   fi
   echo orasidintab is $orasidintab
done

if [[ $k -eq 0 ]]
then
  echo "No Oracle sid $dbname information in /etc/oratab. Cannot determine ORACLE_HOME"
  exit 2
else
  echo ORACLE_HOME is $ORACLE_HOME
fi


export ORACLE_SID=$yes_oracle_sid
}

function create_rmanfile_all {

echo "Create rman file" >> $runlog

echo "CONFIGURE DEFAULT DEVICE TYPE TO disk;" >> $rmanfiled_b
echo "CONFIGURE DEFAULT DEVICE TYPE TO disk;" >> $rmanfilea_b
echo "CONFIGURE CONTROLFILE AUTOBACKUP ON;" >> $rmanfiled_b
echo "CONFIGURE CONTROLFILE AUTOBACKUP OFF;" >> $rmanfilea_b
echo "CONFIGURE CONTROLFILE AUTOBACKUP FORMAT FOR DEVICE TYPE DISK TO '${mount}1/$host/$dbname/%d_%F.ctl';" >> $rmanfiled_b
#echo "CONFIGURE DEVICE TYPE DISK PARALLELISM $parallel BACKUP TYPE TO BACKUPSET;" >> $rmanfiled_b
#echo "CONFIGURE retention policy to recovery window of $retday days;" >> $rmanfiled_b
#echo "Delete obsolete;" >> $rmanfiled_b
echo "   " >> $rmanfiled_b
echo "   " >> $rmanfilea_b
echo "RUN {" >> $rmanfiled_b
echo "RUN {" >> $rmanfilea_b

i=1
j=1
while [ $i -le $num ]; do
  if mountpoint -q "${mount}${i}"; then
    echo "$mount${i} is mount point"
    echo " "
	
    if [[ ! -d "${mount}${i}/$host/$dbname" ]]; then
       echo "Directory ${mount}${i}/$host/$dbname does not exist, create it"
       if mkdir -p ${mount}${i}/$host/$dbname; then
          echo "${mount}${i}/$host/$dbname is created"
       else
          echo "creating ${mount}${i}/$host/$dbname failed. There is a permission issue"
          exit 1
       fi
    fi

    if [[ $j -le $parallel ]]; then
	   echo "allocate channel fs$j device type disk format = '$mount$i/$host/$dbname/%d_%T_%U.bdf';" >> $rmanfiled_b
	   echo "allocate channel fs$j device type disk format = '$mount$i/$host/$dbname/%d_%T_%U.blf';" >> $rmanfilea_b
	   echo "release channel fs$j;" >> $rmanfiled_e
	   echo "release channel fs$j;" >> $rmanfilea_e
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
echo "backup INCREMENTAL LEVEL $level CUMULATIVE database filesperset=1;" >> $rmanfiled_b
echo "sql 'alter system switch logfile';" >> $rmanfiled_b
if [[ $archretday -eq 0 ]]; then
   echo "backup archivelog all delete input;" >> $rmanfilea_b
else
   echo "backup archivelog all archivelog until time 'sysdate-$archretday' delete input;" >> $rmanfilea_b
fi

cat $rmanfiled_b $rmanfiled_e > $rmanfiled
cat $rmanfilea_b $rmanfilea_e > $rmanfilea

echo "}" >> $rmanfiled
echo "}" >> $rmanfilea
echo "exit;" >> $rmanfiled
echo "exit;" >> $rmanfilea

echo "finished creating rman file" >> $runlog
echo "finished creating rman file"
}
function create_rmanfile_archive {

echo "Create rman file" >> $runlog

echo "CONFIGURE DEFAULT DEVICE TYPE TO disk;" >> $rmanfilea_b
echo "CONFIGURE CONTROLFILE AUTOBACKUP OFF;" >> $rmanfilea_b
#echo "CONFIGURE DEVICE TYPE DISK PARALLELISM $parallel BACKUP TYPE TO BACKUPSET;" >> $rmanfiled_b
#echo "CONFIGURE retention policy to recovery window of $retday days;" >> $rmanfiled_b
#echo "Delete obsolete;" >> $rmanfiled_b
echo "   " >> $rmanfilea_b
echo "RUN {" >> $rmanfilea_b

i=1
j=1
while [ $i -le $num ]; do
  if mountpoint -q "${mount}${i}"; then
    echo "$mount${i} is mount point"
    echo " "
	
    if [[ ! -d "${mount}${i}/$host/$dbname" ]]; then
       echo "Directory ${mount}${i}/$host/$dbname does not exist, create it"
       if mkdir -p ${mount}${i}/$host/$dbname; then
          echo "${mount}${i}/$host/$dbname is created"
       else
          echo "creating ${mount}${i}/$host/$dbname failed. There is a permission issue"
          exit 1
       fi
    fi

    if [[ $j -le $parallel ]]; then
	   echo "allocate channel fs$j device type disk format = '$mount$i/$host/$dbname/%d_%T_%U.blf';" >> $rmanfilea_b
	   echo "release channel fs$j;" >> $rmanfilea_e
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

if [[ $archretday -eq 0 ]]; then
   echo "backup archivelog all delete input;" >> $rmanfilea_b
else
   echo "backup archivelog all archivelog until time 'sysdate-$archretday' delete input;" >> $rmanfilea_b
fi

cat $rmanfilea_b $rmanfilea_e > $rmanfilea

echo "}" >> $rmanfilea
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
if [[ $archivelogonly = "yes" ]]; then
  echo "archive logs backup only"
  create_rmanfile_archive
  archive
else
  echo "backup database plus archive logs"
  create_rmanfile_all
  backup 
  archive
fi

if ! [[ "$retday" =~ ^[0-9]+$ ]]
then
   echo "$retday is not an integer. No data expiration after this backup"
else
   let retnewday=$retday+1
   echo "Clean old backup longer than $retnewday started at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog
   find ${mount}1/$host/$dbname -type f -mtime +$retnewday -exec /bin/rm -f {} \;
   find ${mount}1/$host/$dbname -depth -type d -empty -exec rmdir {} \;
fi

grep -i error $runlog

if [ $? -eq 0 ]; then
   echo "Backup is successful. However there are channels not correct"
   exit 1
fi

