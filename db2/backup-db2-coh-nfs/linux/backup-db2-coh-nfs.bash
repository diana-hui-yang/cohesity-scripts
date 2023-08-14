#!/bin/bash
#
# Name:         backup-db2-coh-nfs.bash
#
# Function:     This script backup db2 using nfs mount.
# Show Usage: run the command to show the usage
#
# Changes:
# 09/18/22 Diana Yang   New script
# 08/14/23 Diana Yang   Add db2profile option
#
#################################################################

function show_usage {
echo "usage: backup-db2-coh-nfs.bash -d <database name> -t <full or incremental> -l <offline or online> -m <mount-prefix> -n <number of mounts> -p <number of sessions> -e <retention> -f <DB2 profile> -w <yes/no>"
echo " "
echo " Required Parameters"
echo " -d : database name"
echo " -t : backup type. full means database backup full, incre means database backup incremental"
echo " -m : mount-prefix (like /coh/db2)"
echo " -n : number of mounts "
echo " -e : Retention time (days to retain the backups)"
echo " "
echo " Optional Parameters"
echo " -f : DB2 profile path. The default is /home/db2inst1/sqllib/db2profile"
echo " -l : offline backup or online backup. off means offline backup. default is online backup"
echo " -p : number of stripes"
echo " -w : yes means preview db2 backup scripts"
echo "
"
}

while getopts ":d:t:f:l:m:n:e:p:w:" opt; do
  case $opt in
    l ) dbstage=$OPTARG;;
    d ) dbname=$OPTARG;;
    t ) backuptype=$OPTARG;;
    m ) mount=$OPTARG;;
    n ) num=$OPTARG;;
    p ) parallel=$OPTARG;;
    f ) db2profile=$OPTARG;;
    e ) retday=$OPTARG;;
    w ) preview=$OPTARG;;
  esac
done

#echo $password

# Check required parameters
fullcommand=($@)
lencommand=${#fullcommand[@]}
#echo $lencommand

# Check required parameters
if test $mount && test $dbname && test $num && test $retday
then
  :
else
  show_usage 
  exit 1
fi

function setup {

i=0
for (( i=0; i<$lencommand; i++ ))
do
   if [[ ${fullcommand[$i]} == -t ]]; then
      backuptypeset=yes
   fi
done
if [[ -n $backuptypeset ]]; then
   if [[ -z $backuptype ]]; then
      echo "Please enter 'full' or 'incre' as the argument for -t. It may be empty or not all options are given an argument. All options should be given an arguments"
      exit 2
   else
      if [[ $backuptype != [FfIi]* ]]; then
         echo "'full' or 'incre' should be provided after -t in syntax, other answer is not valid"
         exit 2
      fi
   fi
fi

i=0
for (( i=0; i<$lencommand; i++ ))
do
   if [[ ${fullcommand[$i]} == -l ]]; then
      dbstageset=yes
   fi
done
if [[ -n $dbstageset ]]; then
   if [[ -z $dbstage ]]; then
      echo "Please enter 'offline' or 'online' as the argument for -l. It may be empty or not all options are given an argument. All options should be given an arguments"
      exit 2
   else
      if [[ $dbstage != 'offline' && $dbstage != 'online' ]]; then
         echo "'offline' or 'online' should be provided after -l in syntax, other answer is not valid"
	 exit 2
      fi
   fi 
fi

i=0
for (( i=0; i<$lencommand; i++ ))
do
   if [[ ${fullcommand[$i]} == -w ]]; then
      previewset=yes
   fi
done
if [[ -n $previewset ]]; then
   echo preview is $preview
   if [[ -z $preview ]]; then
      echo "Please enter 'yes' as the argument for -w. It may be empty or not all options are given an argument. All options should be given an arguments"
      exit 2
   else
      if [[ $preview != [Yy]* ]]; then
         echo "'yes' should be provided after -w in syntax, other answer is not valid"
	 exit 2
      fi 
   fi
fi

if test $parallel
then
  :
else
  echo "no input for parallel, set parallel to be 4."
  parallel=4
fi

if [[ $num -gt $parallel ]]; then
   echo "The argument for -n should be less than the argument for -p"
   exit 1
fi

if [[ -n $db2profile ]]; then
   if [[ -f $db2profile ]]; then
      echo "we will use the db2profile provided $db2profile"
   else  
      echo "$db2profile is not a file. It may be a directory"
      db2profile=${db2profile}/db2profile
      if [[ ! -f $db2profile ]]; then
         echo "db2profile is not found using the argument provided to -f. Please enter the correct db2profile path"
	 exit 1
      fi
   fi
else
#    assume the sbt library is in $DIR/lib"
   db2profile=/home/db2inst1/sqllib/db2profile
   if [[ ! -f $db2profile ]]; then
      echo "$db2profile doesn't exist. Please enter the correct db2profile path using -f option"
      exit 1
   fi
fi

. $db2profile

which db2
if [ $? -ne 0 ]; then
  echo "Can't find db2 command. Check db2profile"
  exit 1
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

if [[ ! -d $DIR/log/$dbname ]]; then
  echo " $DIR/log/$dbname does not exist, create it"
  mkdir -p $DIR/log/$dbname
  
  if [ $? -ne 0 ]; then
    echo "create log directory $DIR/log/$dbname failed. There is a permission issue"
    exit 1
  fi
fi

runlog=$DIR/log/$dbname/$dbname.$DATE_SUFFIX.log
db2db_cmd=$DIR/log/$dbname/$dbname.db.$DATE_SUFFIX.bash


#trim log directory
find $DIR/log/$dbname/${dbname}* -type f -mtime +7 -exec /bin/rm {} \;
find $DIR/log/$dbname -type f -mtime +14 -exec /bin/rm {} \;

}

function create_db2backup {

i=1
j=1
while [ $i -le $num ]; do
  mountstatus=`mount | grep -i  "${mount}${i}"`
  if [[ -n $mountstatus ]]; then
#    echo "$mount${i} is mount point"
    echo " "
    if [[ ! -d "${mount}${i}/backup/${dbname}" ]]; then
       echo "Directory ${mount}${i}/backup/${dbname} does not exist, create it"
       if mkdir -p ${mount}${i}/backup/${dbname}; then
          echo "${mount}${i}/backup/${dbname} is created"
       else
          echo "creating ${mount}${i}/backup/${dbname} failed. There is a permission issue"
          exit 1
       fi
    fi

    echo "Create db2 db backup file" >> $runlog
    if [[ $j -eq 1 ]]; then
       if [[ $dbstage == offline ]]; then
          echo "db2 \"backup db $dbname ON ALL DBPARTITIONNUMS to ${mount}${i}/backup/${dbname}," >> ${db2db_cmd}
       else
          if [[ $type == [Ff]* ]]; then
	     echo "db2 \"backup db $dbname ON ALL DBPARTITIONNUMS online to ${mount}${i}/backup/${dbname}," >> ${db2db_cmd}
	  else
	     echo "db2 \"backup db $dbname ON ALL DBPARTITIONNUMS online incremental to ${mount}${i}/backup/${dbname}" >> ${db2db_cmd}
	  fi
       fi
    elif [[ $j -lt $parallel ]]; then
       echo ",${mount}${i}/backup/${dbname}" >> ${db2db_cmd}
    elif [[ $j -eq $parallel ]]; then
       echo ",${mount}${i}/backup/${dbname}\"" >> ${db2db_cmd}
    fi

    i=$[$i+1]
    j=$[$j+1]

    if [[ $i -gt $num && $j -le $parallel ]]; then 
       i=1
    fi
	
  else
    echo "$mount${i} is not a mount point. Backup will not start
    The mount prefix may not be correct or
    The input of the number of mount points may exceed the actuall number of mount points"
    exit 1
  fi	
done
 
chmod 750 ${db2db_cmd}

}


function backup_db2 {

${db2db_cmd}

if [ $? -ne 0 ]; then
  echo "
  Database backup failed at " `/bin/date '+%Y%m%d%H%M%S'`
  echo "
  Database backup failed at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog
  exit 1
else
  echo "
  Database backup finished at " `/bin/date '+%Y%m%d%H%M%S'`
  echo "
  Database backup finished at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog 
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
  if [[ -d "${mount}1/backup/$dbname" ]]; then
    find ${mount}1/backup/$dbname -type f -mtime +$retnewday -exec /bin/rm -fv {} \; >> $runlog
    find ${mount}1/backup/$dbname -depth -type d -empty -exec rmdir -v {} \; >> $runlog
  fi
  echo "Clean backup files older than $retnewday finished at " `/bin/date '+%Y%m%d%H%M%S'`
  echo "Clean backup files older than $retnewday finished at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog 
fi

}

setup

echo "database backup"
create_db2backup
if [[ $preview = "yes" || $preview = "Yes" || $preview = "YES" ]]; then
   echo " "
   echo db2 DATABASE BACKUP SCRIPT
   echo " "
   echo "---------------"
   cat $db2db_cmd
   echo "---------------"
else
   backup_db2
   delete_expired
fi
