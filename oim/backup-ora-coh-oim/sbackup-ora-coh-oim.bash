#!/bin/bash
#
# Name:         sbackup-ora-coh-oim.bash
#
# Function:     This script is written to run on Solaris server. 
#               It backups oracle using Oracle Incremental Merge
#               using nfs mount on a Solaris server. It can do incremental backup and use Oracle
#               recovery catalog. It can do archive log backup only. The retention 
#               time is in days. If the retention time is unlimit, specify unlimit.
#		It only deletes the backup files. It won't clean RMMAN catalog.
#               Oracle cleans its RMAN catalog.
#
#
# Show Usage: run the command to show the usage
#
# Changes:
# 06/11/20 Diana Yang   New script
# 07/01/20 Diana Yang   Add crosscheck
# 07/17/20 Diana Yang   Add catalog oracle datafiles created by Cohesity snapshot
# 08/26/20 Diana Yang   Add more contrains in RAC environment.
# 10/15/20 Diana Yang   Add Deletion of the expired backup using unix command
# 10/23/20 Diana Yang   Modify it to work in Solaris environment
#
#################################################################

function show_usage {
echo "usage: sbackup-ora-coh-oim.bash -r <RMAN login> -h <host> -o <Oracle_DB_Name> -t <backup type> -a <archive only> -m <mount-prefix> -n <number of mounts> -p <number of channels> -e <retention> -l <archive log keep days> -b <ORACLE_HOME> -w <yes/no>" 
echo " "
echo " Required Parameters"
echo " -h : host (scanname is required if it is RAC. optional if it is standalone.)"
echo " -o : ORACLE_DB_NAME (Need to have an entry of this database in /var/opt/oracle/oratab. If it is RAC, it is db_unique_name)"
echo " -t : backup type: Full or Incre"
echo " -a : yes (yes means archivelog backup only, no means database backup plus archivelog backup, no is optional)"
echo " -m : mount-prefix (like /mnt/ora)"
echo " -n : number of mounts"
echo " -e : Retention time (days to retain the backups, apply only after uncomment \"Delete obsolete\" in this script)"
echo " "
echo " Optional Parameters"
echo " -r : RMAN login (example: \"rman target /\", optional)"
echo " -p : number of channels (Optional, default is 4)"
echo " -l : Archive logs retain days (days to retain the local archivelogs before deleting them. default is 1 day)"
echo " -b : ORACLE_HOME (default is /var/opt/oracle/oratab, optional.)"
echo " -w : yes means preview rman backup scripts"
}

while getopts ":r:h:o:a:t:m:n:p:e:l:b:w:" opt; do
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
    b ) oracle_home=$OPTARG;;
    w ) preview=$OPTARG;;
  esac
done

echo $dbname, $mount, $host, $num

# Check required parameters
if test $mount && test $dbname && test $num && test $retday
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
  hostdefinded=yes
else
  host=`hostname`
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
else
  if [[ `echo $rmanlogin | grep -i "rman target /"` ]]; then
    echo "It is local backup"
  else
    remote="yes"
  fi
fi

echo $remote

DATE_SUFFIX=`/bin/date '+%Y%m%d%H%M%S'`
#echo $DATE_SUFFIX

DIRcurrent=$0
echo $DIRcurrent
DIR=`echo $DIRcurrent |  gawk 'BEGIN{FS=OFS="/"}{NF--; print}'`
if [[ ${DIR::1} != "/" ]]; then
  if [[ $DIR = '.' ]]; then
    DIR=`pwd`
  else
    DIR=`pwd`/${DIR}
  fi
fi

if [[ ! -d $DIR/log/$host ]]; then
  echo " $DIR/log/$host does not exist, create it"
  mkdir -p $DIR/log/$host
  
  if [ $? -ne 0 ]; then
    echo "create log directory $DIR/log/$host failed. There is a permission issue"
    exit 1
  fi
fi


if [[ $archivelogonly != "yes" ]]; then
  echo export backup_time=$DATE_SUFFIX > /tmp/$dbname.cohesity.oim
  echo export backup_dir=$host/$dbname >> /tmp/$dbname.cohesity.oim
  echo export host=$host >> /tmp/$dbname.cohesity.oim
fi


runlog=$DIR/log/$host/$dbname.$DATE_SUFFIX.log
runrlog=$DIR/log/$host/${dbname}.r.$DATE_SUFFIX.log
rmanlog=$DIR/log/$host/$dbname.rman.$DATE_SUFFIX.log
rmanloga=$DIR/log/$host/$dbname.archive.$DATE_SUFFIX.log
rmanlogar=$DIR/log/$host/$dbname.archive_r.$DATE_SUFFIX.log
rmanfiled=$DIR/log/$host/$dbname.rman.$DATE_SUFFIX.rcv
rmanfilea=$DIR/log/$host/$dbname.archive.$DATE_SUFFIX.rcv
rmanfilear=$DIR/log/$host/$dbname.archive_r.$DATE_SUFFIX.rcv
catalog_bash=$DIR/log/$host/${dbname}_catalog.$DATE_SUFFIX.bash
catalog_log=$DIR/log/$host/${dbname}_catalog.$DATE_SUFFIX.log
tag=${dbname}_${DATE_SUFFIX}

#echo $host $oracle_sid $mount $num

#trim log directory
gfind $DIR/log/$host -type f -mtime +7 -exec /bin/rm {} \;

if [ $? -ne 0 ]; then
  echo "del old logs in $DIR/log/$host failed" >> $runlog
  echo "del old logs in $DIR/log/$host failed"
  exit 2
fi

if [[ $remote != "yes" ]]; then
  echo "check whether this database is up running on $host"
  runoid=`ps -ef | grep pmon | gawk 'NF>1{print $NF}' | grep -i $dbname | gawk -F "pmon" '{print $2}' | sort -t _ -k 1`

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
       break
    else
       if [[ $lastc =~ ^[0-9]+$ ]]; then
         if [[ ${oracle_sid::${#oracle_sid}-1} == ${dbname} ]]; then
	    if [[ -z $hostdefinded ]]; then
   	      echo "This is RAC environment, scanname should be provided after -h option"
	      echo "  "
	      exit 2
   	    else
              echo "Oracle database $dbname is up on $host. Backup can start"
              yes_oracle_sid=$oracle_sid
    	      j=1
 	    fi
         fi
       fi 
    fi
  done

  if [[ $j -eq 0 ]]; then
    echo "Oracle database $dbname is not up on $host. Backup will not start on $host"
    exit 2
  fi
fi

#echo yes_oracle_sid is $yes_oracle_sid

# get ORACLE_HOME in /var/opt/oracle/oratab if it is not provided in input

if [[ -z $oracle_home ]]; then

  oratabinfo=`grep -i $dbname /var/opt/oracle/oratab`

#echo oratabinfo is $oratabinfo

  arrinfo=($oratabinfo)
  leninfo=${#arrinfo[@]}

  k=0
  for (( i=0; i<$leninfo; i++))
  do
    orasidintab=`echo ${arrinfo[$i]} | gawk -F ":" '{print $1}'`
    orahomeintab=`echo ${arrinfo[$i]} | gawk -F ":" '{print $2}'`
  
    if [[ $orasidintab == ${dbname} ]]; then    
       oracle_home=$orahomeintab
       export ORACLE_HOME=$oracle_home
       export PATH=$PATH:$ORACLE_HOME/bin
       k=1
    fi
#   echo orasidintab is $orasidintab
  done


  if [[ $k -eq 0 ]]; then
    echo "No Oracle db_unique_name $dbname information in /var/opt/oracle/oratab. Cannot determine ORACLE_HOME"
    exit 2
  else
    echo ORACLE_HOME is $ORACLE_HOME
  fi
else
  export ORACLE_HOME=$oracle_home
  export PATH=$PATH:$ORACLE_HOME/bin
fi

which rman

if [ $? -ne 0 ]; then
  echo "oracle home $oracle_home provided or found in /var/opt/oracle/oratab is incorrect"
  exit 1
fi

export NLS_DATE_FORMAT='DD:MM:YYYY-HH24:MI:SS'
export ORACLE_SID=$yes_oracle_sid

echo oracle sid is $ORACLE_SID

if [[ $remote == "yes" ]]; then
# test rman connection
echo   rmanr=$rmanlogin 
   rmanr=`$rmanlogin << EOF
   exit;
EOF`

   echo $rmanr | grep -i connected
   
   if [ $? -ne 0 ]; then
      echo "rman connection using $rmanlogin is incorrect
           "
      echo $rmanr
      echo "
           rmanlogin syntax can be like \"rman target /\" or
          \"rman target sys/<password>@<database connect string> catalog <user>/<password>@<catalog>\""
      exit 1
   fi
fi

echo "rmanlogin is \"$rmanlogin\""
}

function create_rmanfile_all {


echo "Create rman file" >> $runlog

echo "
CONFIGURE DEFAULT DEVICE TYPE TO disk;
CONFIGURE CONTROLFILE AUTOBACKUP ON;
CONFIGURE CONTROLFILE AUTOBACKUP FORMAT FOR DEVICE TYPE DISK TO '${mount}1/$host/$dbname/controlfile/%d_%F.ctl';
CONFIGURE retention policy to recovery window of $retday days;
" > $rmanfiled
#echo "Delete obsolete;" >> $rmanfiled
echo " 
RUN {
" >> $rmanfiled

echo "
CONFIGURE DEFAULT DEVICE TYPE TO disk;
CONFIGURE CONTROLFILE AUTOBACKUP ON;
CONFIGURE CONTROLFILE AUTOBACKUP FORMAT FOR DEVICE TYPE DISK TO '${mount}1/$host/$dbname/controlfile/%d_%F.ctl';

RUN {
" >> $rmanfilea

i=1
j=0
while [ $i -le $num ]; do
  mountstatus=`mount | grep -i  "${mount}${i}"`
  if [[ -n $mountstatus ]]; then
    echo "
	$mount${i} is mount point
    "
	
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

    if [[ $j -lt $parallel ]]; then
	   allocate_database[$j]="allocate channel fs$j device type disk format = '$mount$i/$host/$dbname/datafile/%d_%T_%U';"
	   allocate_archive[$j]="allocate channel fs$j device type disk format = '$mount$i/$host/$dbname/archivelog/%d_%T_%U.blf';"
       unallocate[j]="release channel fs$j;"
    fi

    i=$[$i+1]
    j=$[$j+1]


    if [[ $i -gt $num && $j -lt $parallel ]]; then 
       i=1
    fi
  else
    echo "$mount${i} is not a mount point. Backup will not start
    The mount prefix may not be correct or
    The input of the number of mount points may exceed the actuall number of mount points"
    exit 1
  fi
done

for (( i=0; i < ${#allocate_database[@]}; i++ )); do
   echo ${allocate_database[$i]} >> $rmanfiled
done

for (( i=0; i < ${#allocate_archive[@]}; i++ )); do
   echo ${allocate_archive[$i]} >> $rmanfilea
done

if [[ $ttype = "full" || $type = "Full" || $ttype = "FULL" ]]; then
   echo "Full backup" 
   echo "Full backup" >> $runlog
   echo "
   crosscheck datafilecopy all;
   delete noprompt expired datafilecopy all;
   delete noprompt copy of database tag 'incre_update';
   backup incremental level 1 for recover of copy with tag 'incre_update' database;
   recover copy of database with tag  'incre_update';
   " >> $rmanfiled
#   echo "
#   crosscheck backup;
#   delete noprompt expired backup;
#   " >> $rmanfiled
elif [[  $ttype = "incre" || $ttype = "Incre" || $ttype = "INCRE" ]]; then
   echo "incremental merge" 
   echo "incremental merge" >> $runlog
   echo "
   crosscheck datafilecopy all;
   delete noprompt expired datafilecopy all;
   backup incremental level 1 for recover of copy with tag 'incre_update' database;
   recover copy of database with tag 'incre_update';
   " >> $rmanfiled
#   echo "
#   crosscheck backup;
#   delete noprompt expired backup;
#   " >> $rmanfiled
else
   echo "backup type entered is not correct. It should be full or incre"
   echo "backup type entered is not correct. It should be full or incre" >> $runlog
   exit 1
fi
   
echo "sql 'alter system switch logfile';" >> $rmanfiled
if [[ $archretday -eq 0 ]]; then
   echo "backup archivelog all not backed up 1 times delete input;" >> $rmanfilea
else
   echo "backup archivelog all not backed up 1 times archivelog until time 'sysdate-$archretday' delete input;" >> $rmanfilea
fi

for (( i=0; i < ${#unallocate[@]}; i++ )); do
   echo ${unallocate[$i]} >> $rmanfiled
   echo ${unallocate[$i]} >> $rmanfilea
done

echo " 
}
exit;
" >> $rmanfiled
echo "
}
exit;
" >> $rmanfilea

echo "finished creating rman file" >> $runlog
echo "finished creating rman file"
}

function create_rmanfile_archive {

echo "Create rman file" >> $runrlog

echo "CONFIGURE DEFAULT DEVICE TYPE TO disk;" >> $rmanfilear
echo "CONFIGURE CONTROLFILE AUTOBACKUP ON;" >> $rmanfilear
#echo "CONFIGURE DEVICE TYPE DISK PARALLELISM $parallel BACKUP TYPE TO BACKUPSET;" >> $rmanfilear
#echo "CONFIGURE retention policy to recovery window of $retday days;" >> $rmanfilear 
#echo "Delete obsolete;" >> $rmanfilear 
echo "   " >> $rmanfilear
echo "RUN {" >> $rmanfilear

i=1
j=0
while [ $i -le $num ]; do
  mountstatus=`mount | grep -i  "${mount}${i}"`
  if [[ -n $mountstatus ]]; then
    echo "$mount${i} is mount point"
    echo " "
	
    if [[ ! -d "${mount}${i}/$host/$dbname/datafile" ]]; then
       echo "There is no database image backup. Database Image backup should be performed first "
       exit 1
    fi
	
	
    if [[ $j -lt $parallel ]]; then
	   allocate_archive[$j]="allocate channel fs$j device type disk format = '$mount$i/$host/$dbname/archivelog/%d_%T_%U.blf';"
       unallocate[j]="release channel fs$j;"
    fi

    i=$[$i+1]
    j=$[$j+1]


    if [[ $i -gt $num && $j -lt $parallel ]]; then 
       i=1
    fi
  else
    echo "$mount${i} is not a mount point. Backup will not start
    The mount prefix may not be correct or
    The input of the number of mount points may exceed the actuall number of mount points"
    exit 1
  fi
done

for (( i=0; i < ${#allocate_archive[@]}; i++ )); do
   echo ${allocate_archive[$i]} >> $rmanfilear
done

if [[ $archretday -eq 0 ]]; then
   echo "backup archivelog all not backed up 1 times delete input;" >> $rmanfilear
else
   echo "backup archivelog all not backed up 1 times archivelog until time 'sysdate-$archretday' delete input;" >> $rmanfilear
fi

for (( i=0; i < ${#unallocate[@]}; i++ )); do
   echo ${unallocate[$i]} >> $rmanfilear
done

echo "}
exit;" >> $rmanfilear

echo "finished creating rman file" >> $runrlog
echo "finished creating rman file"
}

function catalog_snapshot {

#create a bash script that will catalog the baskup files created by Cohesity snapshot
echo "#!/bin/bash

echo \"Catalog the snapshot files started at  \" \`/bin/date '+%Y%m%d%H%M%S'\`
export ORACLE_HOME=$oracle_home
export PATH=$PATH:$ORACLE_HOME/bin
export NLS_DATE_FORMAT='DD:MM:YYYY-HH24:MI:SS'
export ORACLE_SID=$yes_oracle_sid
$rmanlogin log $catalog_log << EOF
CONFIGURE DEFAULT DEVICE TYPE TO disk;
CONFIGURE CONTROLFILE AUTOBACKUP ON;
CONFIGURE CONTROLFILE AUTOBACKUP FORMAT FOR DEVICE TYPE DISK TO '${mount}1/$host/$dbname/controlfile/%d_%F.ctl';
" >> $catalog_bash
#cd ${mount}1/$host/$dbname/datafile.$DATE_SUFFIX
cd ${mount}1/$host/$dbname/datafile
	 
num_dfile=`ls *_data_*| wc -l`
dfile=(`ls *_data_*`)
i=1
j=0
while [ $i -le $num ]; do
  	
  if [[ $j -lt $num_dfile ]]; then
	 echo "CATALOG DATAFILECOPY '${mount}${i}/$host/$dbname/datafile.$DATE_SUFFIX/${dfile[$j]}' tag '${tag}';" >> $catalog_bash
  fi

  i=$[$i+1]
  j=$[$j+1]


  if [[ $i -gt $num && $j -le $num_dfile ]]; then 
     i=1
  fi
  
done

echo "
backup as copy current controlfile format '${mount}1/$host/$dbname/controlfile/$dbname.ctl.$DATE_SUFFIX';
exit;
EOF

if [[ ! -z \`grep -i error" $catalog_log"\` ]]; then
  echo \"catalog the snapshot files failed at \" \`/bin/date '+%Y%m%d%H%M%S'\`
  echo \"catalog the snapshot files failed at \" \`/bin/date '+%Y%m%d%H%M%S'\` >> $runlog
  exit 1
else
  echo \"Catalog the snapshot files finished at  \" \`/bin/date '+%Y%m%d%H%M%S'\`
  echo \"Catalog the snapshot files finished at  \" \`/bin/date '+%Y%m%d%H%M%S'\` >> $runlog
fi
" >> $catalog_bash

    
chmod 750 $catalog_bash

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
  echo "Archive logs backup finished at " `/bin/date '+%Y%m%d%H%M%S'` >> $runrlog 
fi

grep -i error $rmanlogar
 
if [ $? -eq 0 ]; then
   echo "Backup is successful. However there are channels not correct"
   exit 1
else
   echo "Backup is successful."
fi
}

function delete_expired {

if ! [[ "$retday" =~ ^[0-9]+$ ]]; then
  echo "$retday is not an integer. No data expiration after this backup"
  exit 1
  echo "Need to change the parameter after -e to be an integer"
else
  let retnewday=$retday+1
  echo "Clean backup files older than $retnewday started at " `/bin/date '+%Y%m%d%H%M%S'`
  echo "Clean backup files older than $retnewday started at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog
  echo "only delete old expired backup during database backup" >> $runlog
  if [[ -d "${mount}1/$host/$dbname" ]]; then
    gfind ${mount}1/$host/$dbname -type f -mtime +$retnewday -exec /bin/rm -f {} \;
    gfind ${mount}1/$host/$dbname -depth -type d -empty -exec rmdir {} \;
  fi
  echo "Clean backup files older than $retnewday finished at " `/bin/date '+%Y%m%d%H%M%S'`
  echo "Clean backup files older than $retnewday finished at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog
fi

}

setup

if [[ $archivelogonly = "yes" ]]; then
  echo "archive logs backup only"
  create_rmanfile_archive
  if [[ $preview = "yes" || $preview = "Yes" || $preview = "YES" ]]; then
    echo " "
    echo ORACLE ARCHIVE LOG BACKUP RMAN SCRIPT 
    echo " "
    echo "---------------"
    cat $rmanfilear
    echo "---------------"
  else
    archiver
  fi 
else
  create_rmanfile_all
  if [[ $preview = "yes" || $preview = "Yes" || $preview = "YES" ]]; then
    catalog_snapshot
    echo "   "
    echo ORACLE ARCHIVE LOG BACKUP RMAN SCRIPT
    echo "---------------"
    echo " "
    cat $rmanfilea
    echo "---------------"
    echo " "
    echo ORACLE DATABASE BACKUP RMAN SCRIPT
    echo " "
    echo "---------------"
    cat $rmanfiled
    echo "---------------"
    echo ORACLE CATALOG SNAPSHOT BACKUP FILES BASH SCRIPT
    echo " "
    echo "---------------"
    cat $catalog_bash
    echo "---------------"
  else
    backup
    catalog_snapshot
    archive
    delete_expired
  fi

  grep -i error $runlog
  
  if [ $? -eq 0 ]; then
     echo "Backup is successful. However there are channels not correct"
     exit 1
  fi

fi
