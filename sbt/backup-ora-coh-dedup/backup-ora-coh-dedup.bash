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
# 04/04/20 Diana Yang   Allow Oracle sid name has "_" symbol
# 04/04/20 Diana Yang   Better support for RAC database
# 07/21/20 Diana Yang   Improve the code
# 07/21/20 Diana Yang   Add Oracle section size option option
# 07/22/20 Diana Yang   Add option to be able to backup database remotely
#
#################################################################

function show_usage {
echo "usage: backup-ora-coh-dedup.bash -r <RMAN login> -h <host> -o <Oracle_DB_Name> -a <archive only> -i <incremental level> -f <vip file> -v <view> -s <sbt home> -p <number of channels> -e <retention> -l <archive log keep days> -z <section size> -w <yes/no>"
echo " -r : RMAN login (example: \"rman target /\", optional)"
echo " -h : host (optional)" 
echo " -o : ORACLE_DB_NAME (if it is standard alone, it is the same as ORACLE_SID)" 
echo " -a : arch (archivelog backup only, optional. default is database backup)"
echo " -i : Incremental level"
echo " -f : file that has vip list"
echo " -v : Cohesity view"
echo " -s : Cohesity SBT library home"
echo " -p : number of channels (Optional, default is 4)"
echo " -e : Retention time (days to retain the backups)"
echo " -l : Archive logs retain days (days to retain the local archivelogs before deleting them. default is 1 day)"
echo " -z : section size in GB (Optional, default is no section size)"
echo " -w : yes means preview rman backup scripts"
}

while getopts ":r:h:o:a:i:f:v:s:p:e:l:z:w:" opt; do
  case $opt in
    r ) rmanlogin=$OPTARG;;
    h ) host=$OPTARG;;
    o ) dbname=$OPTARG;;
    a ) arch=$OPTARG;;
    i ) level=$OPTARG;;
    f ) vipfile=$OPTARG;;
    v ) view=$OPTARG;;
    s ) sbthome=$OPTARG;;
    p ) parallel=$OPTARG;;
    e ) retday=$OPTARG;;
    l ) archretday=$OPTARG;;
    z ) sectionsize=$OPTARG;;
    w ) preview=$OPTARG;;
  esac
done

#echo $dbname, $vipfile, $host, $view

# Check required parameters
if test $vipfile && test $dbname && test $view && test $retday && test $sbthome && test $arch
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
else
  remote="yes"
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

if test -f $vipfile; then
   echo "file $vipfile provided exist, script continue"
else
   vipfile=${DIR}/${vipfile}
   if test -f $vipfile; then
      echo "file $vipfile provided exist, script continue"
   else
      echo "file $vipfile provided does not exist"
      exit 1
   fi
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
            echo "Oracle database $dbname is up on $host. Backup can start"
            yes_oracle_sid=$oracle_sid
    	    j=1
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

echo "get ORACLE_HOME"
oratabinfo=`grep -i $dbname /etc/oratab`

if [[ -z $oratabinfo ]]; then
  oratabinfo1=`grep -i ${dbname::-1} /etc/oratab`
  if [[ -z ${oratabinfo1} ]]; then
     echo "No Oracle sid $yes_oracle_sid information in /etc/oratab. Cannot determine ORACLE_HOME"
     exit 2
  else
     oratabinfo=$oratabinfo1 
     lasth=${dbname: -1}
  fi
fi 

#echo oratabinfo is $oratabinfo

arrinfo=($oratabinfo)
leninfo=${#arrinfo[@]}

k=0
for (( i=0; i<$leninfo; i++))
do
   orasidintab=`echo ${arrinfo[$i]} | awk -F ":" '{print $1}'`
   orahomeintab=`echo ${arrinfo[$i]} | awk -F ":" '{print $2}'`
   if [[ $lasth =~ ^[0-9]+$ ]]; then 
      if [[ $orasidintab == ${dbname::-1} ]]; then
         oracle_home=$orahomeintab
         export ORACLE_HOME=$oracle_home
         export PATH=$PATH:$ORACLE_HOME/bin
         k=1
      fi 
   else 
      if [[ $orasidintab == ${dbname} ]]; then    
         oracle_home=$orahomeintab
         export ORACLE_HOME=$oracle_home
         export PATH=$PATH:$ORACLE_HOME/bin
         k=1
      fi
   fi
#   echo orasidintab is $orasidintab
done
export NLS_DATE_FORMAT='DD:MM:YYYY-HH24:MI:SS'


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

echo "CONFIGURE DEFAULT DEVICE TYPE TO sbt_tape;" >> $rmanfiled
echo "CONFIGURE DEFAULT DEVICE TYPE TO sbt_tape;" >> $rmanfilea
echo "CONFIGURE CONTROLFILE AUTOBACKUP ON;" >> $rmanfiled
echo "CONFIGURE CONTROLFILE AUTOBACKUP ON;" >> $rmanfilea
echo "CONFIGURE CONTROLFILE AUTOBACKUP FORMAT FOR DEVICE TYPE sbt_tape TO '%d_%F.ctl';" >> $rmanfiled
echo "CONFIGURE retention policy to recovery window of $retday days;" >> $rmanfiled
echo "   " >> $rmanfiled
echo "   " >> $rmanfilea

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
	         echo "CONFIGURE CHANNEL DEVICE TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbthome/libsbt_6_and_7_linux-x86_64.so,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip)';" >> $rmanfiled
#	         echo "Delete obsolete;" >> $rmanfiled
	         echo "RUN {" >> $rmanfiled
	         echo "RUN {" >> $rmanfilea
	      fi
	   
	
          if [[ $j -lt $parallel ]]; then
		     allocate_database[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbthome/libsbt_6_and_7_linux-x86_64.so,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip)' format '%d__%T_%U.bdf';"
			 allocate_archive[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbthome/libsbt_6_and_7_linux-x86_64.so,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip)' format '%d_%T_%U.blf';"
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

echo "crosscheck backup;" >> $rmanfiled
echo "delete noprompt expired backup;" >> $rmanfiled

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

echo "CONFIGURE DEFAULT DEVICE TYPE TO sbt_tape;" >> $rmanfilear
echo "CONFIGURE CONTROLFILE AUTOBACKUP ON;" >> $rmanfilear
echo "   " >> $rmanfilear
echo "RUN {" >> $rmanfilear

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
		     allocate_archive[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbthome/libsbt_6_and_7_linux-x86_64.so,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip)' format '%d_%T_%U.blf';"
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
if [[ $archivelogonly = "yes" ]]; then
  echo "archive logs backup only"
  create_rmanfile_archive
  if [[ $preview = "yes" || $preview = "Yes" || $preview = "YES" ]]; then
    echo ORACLE ARCHIVE LOG BACKUP RMAN SCRIPT 
    echo " "
    cat $rmanfilear
  else
    archiver
  fi
else
  echo "backup database plus archive logs"
  create_rmanfile_all
  if [[ $preview = "yes" || $preview = "Yes" || $preview = "YES" ]]; then
    echo ORACLE DATABASE BACKUP RMAN SCRIPT
    echo " "
    cat $rmanfilea
	echo " "
	echo ORACLE ARCHIVE LOG BACKUP RMAN SCRIPT
    echo " "
    cat $rmanfiled
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

