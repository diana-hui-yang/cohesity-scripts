#!/bin/bash
#
# Name:         backup-ora-coh-sbt.bash
#
# Function:     This script backup oracle in backup set using Cohesity sbt library. 
#		It can do incremental backup and use Oracle recovery catalog
#		It can do archive log backup only. The retention time is in days.
#		It can also launch RMAN backup from a remote location
#
# Show Usage: run the command to show the usage
#
# Changes:
# 03/07/19 Diana Yang   New script
# 04/04/20 Diana Yang   Allow Oracle sid name has "_" symbol
# 04/04/20 Diana Yang   Better support for RAC database
# 07/21/20 Diana Yang   Improve the code
# 07/21/20 Diana Yang   Add Oracle section size option option
# 07/22/20 Diana Yang   Add option to be able to backup database remotely
# 08/06/20 Diana Yang   Rename this from backup-ora-coh-dedup.bash to backup-ora-coh-sbt.bash
# 08/14/20 Diana Yang   Add more contrains in RAC environment. 
#
#################################################################

function show_usage {
echo "usage: backup-ora-coh-sbt.bash -r <RMAN login> -h <host> -o <Oracle_DB_Name> -a <archive only> -i <incremental level> -f <vip file> -v <view> -s <sbt home> -p <number of channels> -e <retention> -l <archive log keep days> -z <section size> -m <ORACLE_HOME> w <yes/no>"
echo " -r : RMAN login (example: \"rman target /\", optional)"
echo " -h : host (scanname is required if it is RAC. optional if it is standalone.)" 
echo " -o : ORACLE_DB_NAME (Need to have an entry of this database in /etc/oratab. If it is RAC, it is db_unique_name)" 
echo " -a : arch (archivelog backup only, optional. default is database backup)"
echo " -i : Incremental level"
echo " -f : file that has vip list"
echo " -v : Cohesity view"
echo " -s : Cohesity SBT library name including directoy or just directory (default name is libsbt_6_and_7_linux-x86_64.so) "
echo " -p : number of channels (Optional, default is 4)"
echo " -e : Retention time (days to retain the backups, apply only after uncomment \"Delete obsolete\" in this script)"
echo " -l : Archive logs retain days (days to retain the local archivelogs before deleting them. default is 1 day)"
echo " -m : ORACLE_HOME (default is /etc/oratab, optional.)"
echo " -z : section size in GB (Optional, default is no section size)"
echo " -w : yes means preview rman backup scripts"
echo "

"
echo "Notes: Oracle \"Delete obsolete\" may delete readonly files within the recovery window.
please read "https://support.oracle.com/epmos/faces/DocumentDisplay?parent=DOCUMENT&sourceId=2245178.1&id=29633753.8"
"
}

while getopts ":r:h:o:a:i:f:v:s:p:e:l:z:m:w:" opt; do
  case $opt in
    r ) rmanlogin=$OPTARG;;
    h ) host=$OPTARG;;
    o ) dbname=$OPTARG;;
    a ) arch=$OPTARG;;
    i ) level=$OPTARG;;
    f ) vipfile=$OPTARG;;
    v ) view=$OPTARG;;
    s ) sbtname=$OPTARG;;
    p ) parallel=$OPTARG;;
    e ) retday=$OPTARG;;
    l ) archretday=$OPTARG;;
    z ) sectionsize=$OPTARG;;
    m ) oracle_home=$OPTARG;;
    w ) preview=$OPTARG;;
  esac
done

#echo $dbname, $vipfile, $host, $view

# Check required parameters
if test $vipfile && test $dbname && test $view && test $retday && test $arch
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
  hostdefinded=yes
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
else
  remote="yes"
fi

DATE_SUFFIX=`/bin/date '+%Y%m%d%H%M%S'`
#echo $DATE_SUFFIX

DIRcurrent=$0
DIR=`echo $DIRcurrent |  awk 'BEGIN{FS=OFS="/"}{NF--; print}'`
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

if test -f $vipfile; then
   echo "file $vipfile provided exists, script continue"
else 
   echo "file $vipfile provided does not exist"
   exit 1
fi

if [[ -n $sbtname ]]; then
   if [[ $sbtname == *".so" ]]; then
      echo "we will use the sbt library provided $sbtname"
   else  
      echo "This may be a directory"
      sbtname=${sbtname}/libsbt_6_and_7_linux-x86_64.so
   fi
else
    echo "we assume the sbt library is in the current directory"
    sbtname=${DIR}/libsbt_6_and_7_linux-x86_64.so
fi

if test -f $sbtname; then
   echo "file $sbtname exists, script continue"
else
   echo "file $sbtname does not exist. exit"
   exit 1
fi
    

runlog=$DIR/log/$host/$dbname.$DATE_SUFFIX.log
runrlog=$DIR/log/$host/${dbname}.r.$DATE_SUFFIX.log
rmanlog=$DIR/log/$host/$dbname.rman.$DATE_SUFFIX.log
rmanloga=$DIR/log/$host/$dbname.archive.$DATE_SUFFIX.log
rmanlogar=$DIR/log/$host/$dbname.archive_r.$DATE_SUFFIX.log
rmanfiled=$DIR/log/$host/$dbname.rman.$DATE_SUFFIX.rcv
rmanfilea=$DIR/log/$host/$dbname.archive.$DATE_SUFFIX.rcv
rmanfilear=$DIR/log/$host/$dbname.archive_r.$DATE_SUFFIX.rcv


#echo $host $dbname $mount $num

#trim log directory
find $DIR/log/$host -type f -mtime +7 -exec /bin/rm {} \;

if [ $? -ne 0 ]; then
  echo "del old logs in $DIR/log/$host failed" >> $runlog
  echo "del old logs in $DIR/log/$host failed"
  exit 2
fi

if [[ $remote != "yes" ]]; then
  echo "check whether this database is up running on $host"
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

# get ORACLE_HOME in /etc/oratab if it is not provided in input

if [[ -z $oracle_home ]]; then

oratabinfo=`grep -i $dbname /etc/oratab`

#echo oratabinfo is $oratabinfo

  arrinfo=($oratabinfo)
  leninfo=${#arrinfo[@]}

  k=0
  for (( i=0; i<$leninfo; i++))
  do
    orasidintab=`echo ${arrinfo[$i]} | awk -F ":" '{print $1}'`
    orahomeintab=`echo ${arrinfo[$i]} | awk -F ":" '{print $2}'`
  
    if [[ $orasidintab == ${dbname} ]]; then    
       oracle_home=$orahomeintab
       export ORACLE_HOME=$oracle_home
       export PATH=$PATH:$ORACLE_HOME/bin
       k=1
    fi
#   echo orasidintab is $orasidintab
  done


  if [[ $k -eq 0 ]]; then
    echo "No Oracle db_unique_name $dbname information in /etc/oratab. Cannot determine ORACLE_HOME"
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
  echo "oracle home $oracle_home provided or found in /etc/oratab is incorrect"
  exit 1
fi

export NLS_DATE_FORMAT='DD:MM:YYYY-HH24:MI:SS'
export ORACLE_SID=$yes_oracle_sid

if [[ $remote == "yes" ]]; then
# test rman connection
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
CONFIGURE DEFAULT DEVICE TYPE TO sbt_tape;
CONFIGURE CONTROLFILE AUTOBACKUP ON;
CONFIGURE CONTROLFILE AUTOBACKUP FORMAT FOR DEVICE TYPE sbt_tape TO '%d_%F.ctl';
CONFIGURE retention policy to recovery window of $retday days;
" > $rmanfiled


echo "
CONFIGURE DEFAULT DEVICE TYPE TO sbt_tape;
CONFIGURE CONTROLFILE AUTOBACKUP ON;
CONFIGURE CONTROLFILE AUTOBACKUP FORMAT FOR DEVICE TYPE sbt_tape TO '%d_%F.ctl';
" >> $rmanfilea

i=1
j=0
while [ $j -le $parallel ]; do

    while IFS= read -r ip; do
    
        ip=`echo $ip | xargs echo -n`    	
	echo "Check whether IP $ip can be connected"
	echo "Check whether IP $ip can be connected" >> $runlog
	if [[ -n $ip ]]; then
	   return=`/bin/ping $ip -c 2`

#           echo "return is $return"
           if echo $return | grep -q error; then
	      echo "error: IP $ip can't be connected. It may not be a valid IP. Skip this IP"
	      echo "error: IP $ip can't be connected. It may not be a valid IP. Skip this IP" >> $runlog
           else
	      echo "IP $ip can be connected"
	      echo "IP $ip can be connected" >> $runlog
	      if [[ $i -eq 1 ]]; then
	         echo "CONFIGURE CHANNEL DEVICE TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,gflag-name=sbt_use_grpc,gflag-value=true)';" >> $rmanfiled
#	         echo "Delete obsolete;" >> $rmanfiled
	         echo "RUN {" >> $rmanfiled
	         echo "RUN {" >> $rmanfilea
	      fi
	   
	
              if [[ $j -lt $parallel ]]; then
	        allocate_database[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,gflag-name=sbt_use_grpc,gflag-value=true)' format '%d__%T_%U.bdf';"
   	        allocate_archive[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,gflag-name=sbt_use_grpc,gflag-value=true)' format '%d_%T_%U.blf';"
	        unallocate[j]="release channel c$j;"
              fi
              i=$[$i+1]
              j=$[$j+1]
	   fi
        fi
     
    done < $vipfile

done


for (( i=0; i < ${#allocate_database[@]}; i++ )); do
   echo ${allocate_database[$i]} >> $rmanfiled
done

for (( i=0; i < ${#allocate_archive[@]}; i++ )); do
   echo ${allocate_archive[$i]} >> $rmanfilea
done

#echo "crosscheck backup;" >> $rmanfiled
#echo "delete noprompt expired backup;" >> $rmanfiled

if [[ -z $sectionsize ]]; then
   echo "backup INCREMENTAL LEVEL $level CUMULATIVE database filesperset 1;" >> $rmanfiled
else
   echo "backup INCREMENTAL LEVEL $level CUMULATIVE database section size ${sectionsize}G filesperset 1;" >> $rmanfiled
fi
echo "sql 'alter system switch logfile';" >> $rmanfiled
if [[ $archretday -eq 0 ]]; then
   echo "backup archivelog all format '%d_%T_%U.bdf' delete input;" >> $rmanfilea
else
   echo "backup archivelog all archivelog until time 'sysdate-$archretday' delete input;" >> $rmanfilea
fi

for (( i=0; i < ${#unallocate[@]}; i++ )); do
   echo ${unallocate[$i]} >> $rmanfiled
   echo ${unallocate[$i]} >> $rmanfilea
done

echo "}" >> $rmanfiled
echo "}" >> $rmanfilea
echo "exit;" >> $rmanfiled
echo "exit;" >> $rmanfilea

echo "finished creating rman file" >> $runlog
echo "finished creating rman file"
}

function create_rmanfile_archive {

echo "Create rman file" >> $runrlog

echo "
CONFIGURE DEFAULT DEVICE TYPE TO sbt_tape;
CONFIGURE CONTROLFILE AUTOBACKUP ON;

RUN {
" > $rmanfilear

i=1
j=0
while [ $j -le $parallel ]; do

    while IFS= read -r ip; do
    
        ip=`echo $ip | xargs echo -n`    	
	echo "Check whether IP $ip can be connected"
	echo "Check whether IP $ip can be connected" >> $runrlog
	if [[ -n $ip ]]; then
	   return=`/bin/ping $ip -c 2`

#           echo "return is $return"
           if echo $return | grep -q error; then
              echo "error: IP $ip can't be connected. It may not be a valid IP. Skip this IP"
	      echo "error: IP $ip can't be connected. It may not be a valid IP. Skip this IP" >> $runrlog
           else
	      echo "IP $ip can be connected"
	      echo "IP $ip can be connected" >> $runrlog
	        
	
              if [[ $j -lt $parallel ]]; then
	         allocate_archive[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,gflag-name=sbt_use_grpc,gflag-value=true)' format '%d_%T_%U.blf';"
	         unallocate[j]="release channel c$j;"  
              fi
              i=$[$i+1]
              j=$[$j+1]
	   fi
	fi
     
    done < $vipfile

done

for (( i=0; i < ${#allocate_archive[@]}; i++ )); do
   echo ${allocate_archive[$i]} >> $rmanfilear
done

if [[ $archretday -eq 0 ]]; then
   echo "backup archivelog all format '%d_%T_%U.bdf' delete input;" >> $rmanfilear
else
   echo "backup archivelog all archivelog until time 'sysdate-$archretday' delete input;" >> $rmanfilear
fi

for (( i=0; i < ${#unallocate[@]}; i++ )); do
   echo ${unallocate[$i]} >> $rmanfilear
done

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
  while IFS= read -r ip
  do
    echo $ip
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

setup

echo host is $host
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
  echo "backup database plus archive logs"
  create_rmanfile_all
  if [[ $preview = "yes" || $preview = "Yes" || $preview = "YES" ]]; then
    echo "   "
    echo ORACLE ARCHIVE LOG BACKUP RMAN SCRIPT
    echo " "
    echo "---------------"
    cat $rmanfilea
    echo "---------------"
    echo " "
    echo ORACLE DATABASE BACKUP RMAN SCRIPT
    echo " "
    echo "---------------"
    cat $rmanfiled
    echo "---------------"
  else
    backup
    archive
  fi

  grep -i error $runlog

  if [ $? -eq 0 ]; then
    echo "Backup is successful. However there are IPs in $vipfile not correct"
    exit 1
  fi
fi

