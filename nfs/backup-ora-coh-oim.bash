#!/bin/bash
#
# Name:         backup-ora-coh-oim.bash
#
# Function:     This script backup oracle using Oracle Incremental Merge
#               using nfs mount. It can do incremental backup and use Oracle
#               recovery catalog. It can do archive log backup only. The retention 
#               time is in days. If the retention time is unlimit, specify unlimit.
#		        It only deletes the backup files. It won't clean RMMAN catalog.
#               Oracle cleans its RMAN catalog.
#
#
# Show Usage: run the command to show the usage
#
# Changes:
# 06/11/2020 Diana Yang   New script
#
#################################################################

function show_usage {
echo "usage: backup-ora-coh-oim.bash -r <RMAN login> -h <host> -o <Oracle_sid> -t <backup type> -a <archive only> -m <mount-prefix> -n <number of mounts> -p <number of channels> -e <retention> -l <archive log keep days>" 
echo " -r : RMAN login (example: \"rman target /\", optional)"
echo " -h : host (optional)" 
echo " -o : ORACLE_SID" 
echo " -t : backup type: Full or Incre"
echo " -a : arch (yes means archivelogonly, no means database backup plus archivelog)"
echo " -m : mount-prefix (like /mnt/ora)"
echo " -n : number of mounts"
echo " -p : number of channels (Optional, default is 4)"
echo " -e : Retention time (days to retain the backups, Optional when doing archivelog backup)"
echo " -l : Archive logs retain days (Optional, days to retain the local archivelogs before deleting them. default is 1 day)"
}

while getopts ":r:h:o:a:t:m:n:p:e:l:" opt; do
  case $opt in
    r ) rmanlogin=$OPTARG;;
    h ) host=$OPTARG;;
    o ) dbname=$OPTARG;;
    a ) arch=$OPTARG;;
    t ) ttype=$OPTARG;;
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

  if test $ttype
  then
    :
  else
    echo "Backup type was not specified. neet to set up parameter using -t "
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
runrlog=$DIR/log/$host/$dbname_r.$DATE_SUFFIX.log
rmanlog=$DIR/log/$host/$dbname.rman.$DATE_SUFFIX.log
rmanloga=$DIR/log/$host/$dbname.archive.$DATE_SUFFIX.log
rmanlogar=$DIR/log/$host/$dbname.archive_r.$DATE_SUFFIX.log
rmanfiled=$DIR/log/$host/$dbname.rman.$DATE_SUFFIX.rcv
rmanfiled_b=$DIR/log/$host/$dbname.rman_b.$DATE_SUFFIX.rcv
rmanfiled_e=$DIR/log/$host/$dbname.rman_e.$DATE_SUFFIX.rcv
rmanfilea=$DIR/log/$host/$dbname.archive.$DATE_SUFFIX.rcv
rmanfilea_b=$DIR/log/$host/$dbname.archive_b.$DATE_SUFFIX.rcv
rmanfilea_e=$DIR/log/$host/$dbname.archive_e.$DATE_SUFFIX.rcv
rmanfilear=$DIR/log/$host/$dbname.archive_r.$DATE_SUFFIX.rcv
rmanfilear_b=$DIR/log/$host/$dbname.archive_rb.$DATE_SUFFIX.rcv
rmanfilear_e=$DIR/log/$host/$dbname.archive_re.$DATE_SUFFIX.rcv

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
#   echo orasidintab is $orasidintab
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
echo "CONFIGURE CONTROLFILE AUTOBACKUP FORMAT FOR DEVICE TYPE DISK TO '${mount}1/$host/$dbname/controlfile/%d_%F.ctl';" >> $rmanfiled_b
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
	
    if [[ ! -d "${mount}${i}/$host/$dbname/datafile" ]]; then
       echo "Directory ${mount}${i}/$host/$dbname/datafile does not exist, create it"
       if mkdir -p ${mount}${i}/$host/$dbname/datafile; then
          echo "${mount}${i}/$host/$dbname/datafile is created"
       else
          echo "creating ${mount}${i}/$host/$dbname/datafile failed. There is a permission issue"
          exit 1
       fi
    fi
	
    if [[ ! -d "${mount}${i}/$host/$dbname/controlfile" ]]; then
       echo "Directory ${mount}${i}/$host/$dbname/controlfile does not exist, create it"
       if mkdir -p ${mount}${i}/$host/$dbname/controlfile; then
          echo "${mount}${i}/$host/$dbname/controlfile is created"
       else
          echo "creating ${mount}${i}/$host/$dbname/controlfile failed. There is a permission issue"
          exit 1
       fi
    fi
	
    if [[ ! -d "${mount}${i}/$host/$dbname/archivelog" ]]; then
       echo "Directory ${mount}${i}/$host/$dbname/archivelog does not exist, create it"
       if mkdir -p ${mount}${i}/$host/$dbname/archivelog; then
          echo "${mount}${i}/$host/$dbname/archivelog is created"
       else
          echo "creating ${mount}${i}/$host/$dbname/archivelog failed. There is a permission issue"
          exit 1
       fi
    fi

    if [[ $j -le $parallel ]]; then
       echo "allocate channel fs$j device type disk format = '$mount$i/$host/$dbname/datafile/%d_%T_%U';" >> $rmanfiled_b
       echo "allocate channel fs$j device type disk format = '$mount$i/$host/$dbname/archivelog/%d_%T_%U.blf';" >> $rmanfilea_b
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

if [[ $ttype = "full" || $type = "Full" || $ttype = "FULL" ]]; then
   echo "Full backup" 
   echo "Full backup" >> $runlog
   echo "delete noprompt copy of database tag 'incre_update';" >> $rmanfiled_b
   echo "crosscheck datafilecopy like '${mount}1/$host/$dbname/datafile/%';" >> $rmanfiled_b
   echo "delete noprompt expired datafilecopy all;" >> $rmanfiled_b
   echo "backup incremental level 1 for recover of copy with tag 'incre_update' database;" >> $rmanfiled_b
   echo "recover copy of database with tag  'incre_update';" >> $rmanfiled_b
elif [[  $ttype = "incre" || $ttype = "Incre" || $ttype = "INCRE" ]]; then
   echo "incremental merge" 
   echo "incremental merge" >> $runlog
   echo "backup incremental level 1 for recover of copy with tag 'incre_update' database;" >> $rmanfiled_b
   echo "recover copy of database with tag 'incre_update';" >> $rmanfiled_b
else
   echo "backup type entered is not correct. It should be full or incre"
   echo "backup type entered is not correct. It should be full or incre" >> $rmanfiled_b
   exit 1
fi
   
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

echo "Create rman file" >> $runrlog

echo "CONFIGURE DEFAULT DEVICE TYPE TO disk;" >> $rmanfilear_b
echo "CONFIGURE CONTROLFILE AUTOBACKUP OFF;" >> $rmanfilear_b
#echo "CONFIGURE DEVICE TYPE DISK PARALLELISM $parallel BACKUP TYPE TO BACKUPSET;" >> $rmanfiled_b
#echo "CONFIGURE retention policy to recovery window of $retday days;" >> $rmanfiled_b
#echo "Delete obsolete;" >> $rmanfiled_b
echo "   " >> $rmanfilear_b
echo "RUN {" >> $rmanfilear_b

i=1
j=1
while [ $i -le $num ]; do
  if mountpoint -q "${mount}${i}"; then
    echo "$mount${i} is mount point"
    echo " "
	
    if [[ ! -d "${mount}${i}/$host/$dbname/datafile" ]]; then
       echo "There is no database image backup. Database Image backup should be performed first "
       exit 1
    fi
	
	
    if [[ $j -le $parallel ]]; then
       echo "allocate channel fs$j device type disk format = '$mount$i/$host/$dbname/archivelog/%d_%T_%U.blf';" >> $rmanfilear_b
       echo "release channel fs$j;" >> $rmanfilear_e
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
   echo "backup archivelog all delete input;" >> $rmanfilear_b
else
   echo "backup archivelog all archivelog until time 'sysdate-$archretday' delete input;" >> $rmanfilear_b
fi

cat $rmanfilear_b $rmanfilear_e > $rmanfilear

echo "}" >> $rmanfilear
echo "exit;" >> $rmanfilear

echo "finished creating rman file" >> $runrlog
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


function archiver {

echo "Archive logs backup started at " `/bin/date '+%Y%m%d%H%M%S'`
echo "Archive logs backup started at " `/bin/date '+%Y%m%d%H%M%S'` >> $runrlog

$rmanlogin log $rmanlogar @$rmanfilear

if [ $? -ne 0 ]; then
  echo "Archive logs backup failed at " `/bin/date '+%Y%m%d%H%M%S'`
  echo "Archive logs backup failed at " `/bin/date '+%Y%m%d%H%M%S'` >> $runrlog
  while IFS= read -r line
  do
    echo $line
  done < $rmanlogar
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
  archiver
else

  if ! [[ "$retday" =~ ^[0-9]+$ ]]
  then
    echo "$retday is not an integer. No data expiration after this backup"
    exit 1
    echo "Need to change the parameter after -e to be an integer"
  else
    let retnewday=$retday+1
    echo "Clean backup longer than $retnewday started at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog
    echo "only delete onder backup during database backup" >> $runlog
    if [[ -d "${mount}1/$host/$dbname" ]]; then
       find ${mount}1/$host/$dbname -type f -mtime +$retnewday -exec /bin/rm -f {} \;
       find ${mount}1/$host/$dbname -depth -type d -empty -exec rmdir {} \;
    fi
  fi
  create_rmanfile_all
  backup
  archive
fi

grep -i error $runlog

if [ $? -eq 0 ]; then
   echo "Backup is successful. However there are channels not correct"
   exit 1
fi

