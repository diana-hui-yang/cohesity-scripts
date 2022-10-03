#!/bin/bash
#
# Name:         aix-backup-db2-coh-nfs-mount.bash
#
# Function:     This script backup db2 using nfs mount.
# Show Usage: run the command to show the usage
#
# Changes:
# 09/18/22 Diana Yang   New script
# 09/20/22 Diana Yang   Add mount/umount option
# 09/21/22 Diana Yang   Change "awk" to "/opt/freeware/bin/gawk", change "find" to "/opt/freeware/bin/find",
# 09/21/22 Diana Yang	change "/bin/rm" to "/opt/freeware/bin/rm"
#
#################################################################

function show_usage {
echo "usage: aix-backup-db2-coh-nfs-mount.bash -d <database name> -t <full or incremental> -l <offline or online> -y <Cohesity-cluster> -v <view> -m <mount-prefix> -n <number of mounts> -p <number of sessions> -e <retention> -w <yes/no>"
echo " "
echo " Required Parameters"
echo " -d : database name"
echo " -t : backup type. full means database backup full, incre means database backup incremental"
echo " -y : Cohesity Cluster DNS name"
echo " -v : Cohesity View that is configured to be the target for Oracle backup"
echo " -m : mount-prefix (like /coh/db2)"
echo " -n : number of mounts (only 1 is supported currently)"
echo " -e : Retention time (days to retain the backups)"
echo " "
echo " Optional Parameters"
echo " -l : offline backup or online backup. off means offline backup. default is online backup"
echo " -p : number of stripes (Optional, only 1 is supported currently)"
echo " -w : yes means preview db2 backup scripts"
echo "
"
}

while getopts ":d:t:l:y:v:m:n:e:p:w:" opt; do
  case $opt in
    l ) dbstage=$OPTARG;;
    d ) dbname=$OPTARG;;
    t ) backuptype=$OPTARG;;
    y ) cohesityname=$OPTARG;;
    v ) view=$OPTARG;;
    m ) mount=$OPTARG;;
    n ) num=$OPTARG;;
    p ) parallel=$OPTARG;;
    e ) retday=$OPTARG;;
    w ) preview=$OPTARG;;
  esac
done

#echo "check whether gnu utilities /opt/freeware/bin/gawk, /opt/freeware/bin/find, and /opt/freeware/bin/rm exist on this AIX server"
if [[ ! -f /opt/freeware/bin/gawk ]]; then
    echo "gnu untility /opt/freeware/bin/gawk is not on this AIX server, please download it from 
	
	https://www.ibm.com/support/pages/aix-toolbox-open-source-software-downloads-alpha
	
	yum commands to download the three utilities are
	yum install gawk-5.1.1-1
	yum install findutils-4.6.0-2
	yum install coreutils-8.32-1.ppc
	"
	exit 1
fi

if [[ ! -f /opt/freeware/bin/find ]]; then
    echo "gnu untility /opt/freeware/bin/find is not on this AIX server, please download it from 
	
	https://www.ibm.com/support/pages/aix-toolbox-open-source-software-downloads-alpha
	
	yum commands to download the three utilities are
	yum install gawk-5.1.1-1
	yum install findutils-4.6.0-2
	yum install coreutils-8.32-1.ppc
	"
	exit 1
fi

if [[ ! -f /opt/freeware/bin/rm ]]; then
    echo "gnu untility /opt/freeware/bin/rm is not on this AIX server, please download it from 
	
	https://www.ibm.com/support/pages/aix-toolbox-open-source-software-downloads-alpha
	
	yum commands to download the three utilities are
	yum install gawk-5.1.1-1
	yum install findutils-4.6.0-2
	yum install coreutils-8.32-1.ppc
	"
	exit 1
fi

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

DATE_SUFFIX=`/bin/date '+%Y%m%d%H%M%S'`
#echo $DATE_SUFFIX

DIRcurrent=$0
DIR=`echo $DIRcurrent |  /opt/freeware/bin/gawk 'BEGIN{FS=OFS="/"}{NF--; print}'`
if [[ ${DIR::1} != "/" ]]; then
  if [[ $DIR = '.' ]]; then
    DIR=`pwd`
  else
    DIR=`pwd`/${DIR}
  fi
fi

if test $view || test $num
then
  :
else
  show_usage 
  exit 1
fi

if [[ -n $view ]]; then
   if [[ -z $cohesityname ]]; then
      echo "Cohesity name is not provided. Check vip-list file" 
      if [[ ! -f $DIR/config/vip-list ]]; then
        echo "can't find $DIR/config/vip-list file. Please provide cohesity name or populate $DIR/config/vip-list with Cohesity VIPs"
        echo " "
        show_usage
        exit 1
      fi
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
/opt/freeware/bin/find $DIR/log/$dbname/${dbname}* -type f -mtime +7 -exec /opt/freeware/bin/rm {} \;
/opt/freeware/bin/find $DIR/log/$dbname -type f -mtime +14 -exec /opt/freeware/bin/rm {} \;

db2user=`id | awk -P '{print $1}' | awk -F "(" -P '{ print $2 }' | awk -F ")" -P '{ print $1}'`
db2group=`id | awk -P '{print $2}' | awk -F "(" -P '{ print $2 }' | awk -F ")" -P '{ print $1}'`

}

function create_vipfile {

if [[ ! -d $DIR/config ]]; then
  echo " $DIR/config does not exist, create it"
  mkdir -p $DIR/config
  
  if [ $? -ne 0 ]; then
    echo "create log directory $DIR/config failed. There is a permission issue"
    exit 1
  fi
   
fi

if [[ -z $cohesityname ]]; then
  echo "Cohesity Cluster name is not provided, we will use vipfile"
  vipfile=${DIR}/config/vip-list
else
  vipfile=${DIR}/config/${dbname}-vip-list
  echo "Cohesity Cluster name is $cohesityname. VIPS will be collected and stored in $vipfile"
  nslookup $cohesityname | grep -i address | tail -n +2 | /opt/freeware/bin/gawk '{print $2}' > $vipfile
  
  if [[ ! -s $vipfile ]]; then
    echo "Cohesity Cluster name $cohesityname provided here is not in DNS"
    exit 1
  fi

fi

if [[ -z $num ]]; then
  num=`grep -v -e '^$' $vipfile | wc -l | /opt/freeware/bin/gawk '{print $1}'`
else
  numnode=`grep -v -e '^$' $vipfile | wc -l | /opt/freeware/bin/gawk '{print $1}'`
  if [[ $num -ge $numnode ]]; then
     num=$numnode
  fi
fi

}

function mount_coh {

echo "mount Cohesity view if they are not mounted yet"
j=1
while IFS= read -r ip; do
    
   ip=`echo $ip | xargs`   
	  
   if [[ $j -le $num ]]; then
# check whether mountpoint exist

     if [[ ! -d ${mount}$j ]]; then
       echo "Directory ${mount}${j} does not exist, create it"
       if sudo mkdir -p ${mount}${j}; then
         echo "directory ${mount}${j} is created"
       else
         echo "creating directory ${mount}${j}. There is a permission issue"
         exit 1
       fi
     fi

# check whether this mount point is being used

     mount_cnt=`df -h ${mount}$j | grep -wc "${mount}$j$"`

# If not mounted, mount this IP	to the mountpoint
     if [ "$mount_cnt" -lt 1 ]; then
       echo "== "
       echo "mount point ${mount}$j is not mounted. Mount it at" `/bin/date '+%Y%m%d%H%M%S'`
       if sudo mount -o intr,hard,rsize=1048576,wsize=1048576,proto=tcp,vers=3,nolock $ip:/${view} ${mount}$j; then
          echo "mount ${mount}${j} is sucessfull at " `/bin/date '+%Y%m%d%H%M%S'`
	  sudo chown ${db2user}:${db2group} ${mount}${j}
#		  sudo chmod 777 ${mount}$j
       else
          echo "mount ${mount}${j} failed at " `/bin/date '+%Y%m%d%H%M%S'`
          exit 1
       fi  
     else      
       echo "== "
       echo "mount point ${mount}$j is already mounted"	   
     fi
     j=$[$j+1]
   fi
     
done < $vipfile   

}

function umount_coh {

# check whether any backup using this script is running 
#ps -ef | grep -w ${script_name}
status=`ps -ef | grep -w ${script_name} |wc -l`
echo "status=$status"
if [ "$status" -gt 3 ]; then
   echo "== "
   echo " ${script_name} is still running at " `/bin/date '+%Y%m%d%H%M%S'`
   echo " will not run umount"
else
   echo "== "
   echo " will umount Cohesity NFS mountpoint"
   j=1
   while IFS= read -r ip; do
    
     ip=`echo $ip | xargs`
	 
	  
     if [[ $j -le $num ]]; then
	 
        mount_cnt=`df -h ${mount}$j | grep -wc "${mount}$j$"`

# If mounted, umount this IP	to the mountpoint
        if [ "$mount_cnt" -ge 1 ]; then
           echo "== "
	   echo "mount point ${mount}$j is mounted. umount it at" `/bin/date '+%Y%m%d%H%M%S'`
           if sudo umount ${mount}$j; then
              echo "umount ${mount}${j} is sucessfull at " `/bin/date '+%Y%m%d%H%M%S'`
           else
              echo "umount ${mount}${j} failed at " `/bin/date '+%Y%m%d%H%M%S'`	 
           fi
        else
           echo "mount point ${mount}$j is not mounted"
        fi	
        j=$[$j+1]		
     fi
   done < $vipfile
fi

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
    /opt/freeware/bin/find ${mount}1/backup/$dbname -type f -mtime +$retnewday -exec /opt/freeware/bin/rm -fv {} \; >> $runlog
    /opt/freeware/bin/find ${mount}1/backup/$dbname -depth -type d -empty -exec rmdir -v {} \; >> $runlog
  fi
  echo "Clean backup files older than $retnewday finished at " `/bin/date '+%Y%m%d%H%M%S'`
  echo "Clean backup files older than $retnewday finished at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog 
fi

}

setup

if [[ -n $view ]]; then
   create_vipfile
   mount_coh
fi

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

if [[ -n $view && -n $vipfile ]]; then
   sleep 5 
   umount_coh
fi
