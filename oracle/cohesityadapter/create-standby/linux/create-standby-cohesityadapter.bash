#!/bin/bash
#
# Name:         create-standby-cohesityadapter.bash
#
# Function:     This script creates an Oracle Standby database using the backups taken by 
#		Cohesity Oracle adapter. Before running this script, a recovery view using 
#		Coehesity oracle recovery fundtion from Cohesity GUI or rest API needs to be created first.
# Warning:      Restore can overwrite the existing database. This script needs to be used in caution.
#               The author accepts no liability for damages resulting from its use.
#
#
# Show Usage: run the command to show the usage
#
# Changes:
# 03/06/2024 Diana Yang   New script
#
#################################################################

function show_usage {
echo "usage: create-standby-cohesityadapter.bash -i <Standby_instance_name> -d <db_name> -m <mount-prefix> -n <number of mounts> -p <number of channels> -o <ORACLE_HOME> -f <yes/no> -s <noresume> -w <yes/no>" 
echo " "
echo " Required Parameters"
echo " -i : Standby instance name" 
echo " -d : Oracle_DB_Name (database backup was taken). It is DB name, not instance name"
echo " -m : mount-prefix (like /coh/ora)"
echo " -n : number of mounts"
echo " "
echo " Optional Parameters"
echo " -p : number of channels (Optional, default is same as the number of mounts4)"
echo " -o : ORACLE_HOME (Optional, default is current environment)"
echo " -f : yes means force. It will refresh the target database without prompt"
echo " -s : yes mean Oracle duplicate use noresume, default is no"
echo " -w : yes means preview rman duplicate scripts"
echo "
"
}

while getopts ":i:d:m:n:p:o:f:s:w:" opt; do
  case $opt in
    d ) sdbname=$OPTARG;;
    i ) toraclesid=$OPTARG;;
    m ) mount=$OPTARG;;
    n ) num=$OPTARG;;
    p ) parallel=$OPTARG;;
    o ) oracle_home=$OPTARG;;
    f ) force=$OPTARG;;
    s ) noresume=$OPTARG;;
    w ) preview=$OPTARG;;
  esac
done

#echo $rmanlogin $sdbname, $mount, $num

# Check required parameters
# check whether "\" is in front of "
fullcommand=($@)
lencommand=${#fullcommand[@]}
#echo $lencommand
i=0
for (( i=0; i<$lencommand; i++ ))
do
   if [[ ${fullcommand[$i]} == *\"* ]]; then
      echo " \ shouldn't be part of input. Please remove \."
      exit 2 
   fi
done

#if test $sdbname && test $toraclesid && test $tdbdir && test $mount && test $num
if test $toraclesid && test $mount && test $num
then
  :
else
  show_usage 
  exit 1
fi

if [[ -z $sdbname ]]; then
   echo "Please enter the Source Oracle_DB_Name (database backup was taken) after -d in syntax. It is DB name, not instance name."
   exit 2
fi

# check some input syntax
i=0
for (( i=0; i<$lencommand; i++ ))
do
   if [[ ${fullcommand[$i]} == -f ]]; then
      forceset=yes
   fi
done
if [[ -n $forceset ]]; then
   if [[ -z $force ]]; then
      echo "Please enter 'yes' as the argument for -f. It may be empty or not all options are given an argument. All options should be given an arguments"
      exit 2
   else
      if [[ $force != [Yy]* ]]; then
         echo "'yes' should be provided after -f in syntax, other answer is not valid"
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

function setup {
if test $thost
then
  :
else
  thost=`hostname -s`
fi

if test $parallel
then
  :
else
  echo "no input for parallel, set parallel to be $num."
  parallel=$num
fi

for (( i=0; i<$lencommand; i++ ))
do
   if [[ ${fullcommand[$i]} == -s ]]; then
      noresumeset=yes
   fi
done
if [[ -n $noresumeset ]]; then
   if [[ -z $noresume ]]; then
      echo "Please enter yes or no as the argument for -s. It may be empty or not all options are given an argument. All options should be given an arguments"
      exit 2
   else
      if [[ $noresume != [Yy]* && $noresume != [Nn]* ]]; then
         echo "'yes' or 'no' should be provided after -s in syntax, other answer is not valid"
	 exit 2
      fi
   fi 
fi

sqllogin="sqlplus / as sysdba"

if test $oracle_home; then
#  echo *auxiliary*
  echo "ORACLE_HOME is $oracle_home"
  ORACLE_HOME=$oracle_home
  export ORACLE_HOME=$oracle_home
  export PATH=$PATH:$ORACLE_HOME/bin
else
  oracle_home=`env | grep ORACLE_HOME | awk -F "=" '{print $2}'`
  if [[ -z $oracle_home ]]; then
     echo " is not defined. Need to specify ORACLE_HOME"
     exit 1
  fi   
fi
export NLS_DATE_FORMAT='DD:MM:YYYY-HH24:MI:SS'

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

if [[ ! -d $DIR/log/$thost ]]; then
  echo " $DIR/log/$thost doesn't exist, create it"
  mkdir -p $DIR/log/$thost
  
  if [ $? -ne 0 ]; then
    echo "create log directory $DIR/log/$thost failed. There is a permission issue"
    exit 1
  fi
fi

stdout=$DIR/log/$thost/$toraclesid.$DATE_SUFFIX.std
drmanlog=$DIR/log/$thost/$toraclesid.rman-duplicate.$DATE_SUFFIX.log
drmanfiled=$DIR/log/$thost/$toraclesid.rman-duplicate.$DATE_SUFFIX.rcv
linklist=$DIR/log/$thost/$toraclesid.linklist.$DATE_SUFFIX.log


export ORACLE_SID=$toraclesid

}

function check_oracle_init_file {

dbpfile=${ORACLE_HOME}/dbs/init${toraclesid}.ora
dbspfile=${ORACLE_HOME}/dbs/spfile${toraclesid}.ora

if [[ ! -f ${dbpfile} ]]; then
    echo "The oracle pfile $ORACLE_HOME/dbs/init${toraclesid}.ora doesn't exist. Please check the instance name or create the pfile first.
          "
    exit 2
fi

echo "The following Oracle parameters should be in ${dbpfile}. 
If they are not, please exit the program. After these parameters are added to ${dbpfile}, you can run the same command again

*.DB_UNIQUE_NAME=$toraclesid
*.INSTANCE_NAME=$toraclesid
*.DB_NAME=$sdbname
*.FAL_CLIENT='$toraclesid'
*.FAL_SERVER='$sdbname'
*.LOG_ARCHIVE_CONFIG='DG_CONFIG=($sdbname,$toraclesid)'
*.LOG_ARCHIVE_DEST_2='SERVICE=$sdbname LGWR ASYNC NOAFFIRM VALID_FOR=(ONLINE_LOGFILE,PRIMARY_ROLE) DB_UNIQUE_NAME=$sdbname'


"

if [[ $preview != [Yy]* ]]; then
   if [[ $force != [Yy]* ]]; then
      read -p "Do you want to continue the standby database instantiate " answer1
   
      if [[ $answer1 != [Yy]* ]]; then
         exit
      fi
   fi
fi

}

function duplicate_prepare {

if [[ ! -d "${mount}0" ]]; then
   echo "
   Directory ${mount}0 doesn't exist, no backup files. Check the arguments for -m"
   exit 1
fi

# get adump directory from dbpfile and create it if the directory doesn't exist
adump_directory=`grep -i audit_file_dest $dbpfile | awk -F "'" '{print $2}' | awk -F "%" '{print $1}'`
# remove all space in $adump_directory variable
adump_directory=`echo $adump_directory | xargs`
if [[ -n ${adump_directory} ]]; then
   echo "check adump directory. Create it if it doesn't exist
   "
   if [[ ! -d ${adump_directory} ]]; then
      echo "${adump_directory} doesn't exist, create it"
      mkdir -p ${adump_directory}

      if [ $? -ne 0 ]; then
         echo "create new directory ${adump_directory} failed"
         exit 1
      fi
   fi
fi

# test whether duplicate database is open or not. 
# If it is open, needs to shutdown it down and start the duplicate database in nomount mode
# If it is not open, start the duplicate database in nomount mode
runoid=`ps -ef | grep pmon | awk 'NF>1{print $NF}' | grep -i $toraclesid | awk -F "pmon_" '{print $2}'`

if [[ ${runoid} != ${toraclesid} ]]; then
   echo "Oracle database $toraclesid is not up"
   echo "start the database in nomount mode
   "
   $sqllogin << EOF
   startup nomount pfile=${dbpfile}
EOF
else
   if [[ $force = [Yy]* ]]; then
      echo "Oracle database is up. Will shut it down and start in nomount mode
      "
      $sqllogin << EOF
      ALTER DATABASE RECOVER MANAGED STANDBY DATABASE CANCEL;
      shutdown immediate;
      startup nomount pfile=${dbpfile}
EOF
   else
      read -p "Oracle Standby database is up, Should this database be refreshed with new data? " answer2
      if [[ $answer2 = [Nn]* ]]; then
         exit	 
      else
         $sqllogin << EOF
         ALTER DATABASE RECOVER MANAGED STANDBY DATABASE CANCEL;
         shutdown immediate;
         startup nomount pfile=${dbpfile}
EOF
      fi
   fi
fi

}

function create_softlink {

if [[ ! -d "${mount}0" ]]; then
   echo "Directory ${mount}0 doesn't exist, no backup files. Check the arguments for -m"
   exit 1
fi

# setup backup location
echo "create link location if it doesn't exist"
backup_location=/tmp/orarestore/$toraclesid
echo backup_location is $backup_location

if [[ ! -d ${backup_location} ]]; then
   mkdir -vp ${backup_location}
else
   touch ${backup_location}/tempfile
   /bin/rm ${backup_location}/*
   rmdir ${backup_location}
   mkdir -vp ${backup_location}
fi

#create softlink of the backup files

cd ${mount}0

num_dfile=`ls | wc -l`
dfile=(`ls`)
i=0
j=0
while [ $i -lt $num ]; do
   mountstatus=`mount | grep -i  "${mount}${i}"`
   if [[ -n $mountstatus ]]; then
#      echo "$mount${i} is mount point"
#      echo " "
	
      if [[ $j -lt $num_dfile ]]; then
         ln -s ${mount}${i}/${dfile[$j]} $backup_location/${dfile[$j]}
      fi

      i=$[$i+1]
      j=$[$j+1]


      if [[ $i -ge $num && $j -le $num_dfile ]]; then 
         i=0
      fi
   else
      echo "$mount${i} is not a mount point. duplicate will not start"
      echo "The mount prefix may not be correct or"
      echo "The input of the number of mount points $num may exceed the actuall number of mount points"
      df -h ${mount}*
      exit 1
   fi
done

ls -lR $backup_location > $linklist
}

function create_rman_duplicate_file_localdisk {

echo "
Create rman duplicate file"
echo "RUN {" >> $drmanfiled

i=1
j=0
while [ $i -lt $num ]; do

  if [[ $j -lt $parallel ]]; then
     allocate_database[$j]="allocate auxiliary channel fs$j device type disk;"
     unallocate[j]="release channel fs$j;"
  fi

  i=$[$i+1]
  j=$[$j+1]


  if [[ $i -ge $num && $j -le $parallel ]]; then 
     i=1
  fi
done

for (( i=0; i < ${#allocate_database[@]}; i++ )); do
   echo ${allocate_database[$i]} >> $drmanfiled
done

if [[ $noresume = [Yy]* ]]; then
   echo "DUPLICATE DATABASE FOR STANDBY BACKUP LOCATION '$backup_location' noresume;" >> $drmanfiled
else
   echo "DUPLICATE DATABASE FOR STANDBY BACKUP LOCATION '$backup_location';" >> $drmanfiled
fi

for (( i=0; i < ${#unallocate[@]}; i++ )); do
   echo ${unallocate[$i]} >> $drmanfiled
done

echo "}" >> $drmanfiled
echo "exit;" >> $drmanfiled
echo "finished creating rman instantiate standby database file"

#echo " 
#May need to run the following steps manually on the standby database
#
#create spfile from pfile; 
#shutdown immediate
#startup mount standby database;
#alter system set LOG_ARCHIVE_DEST_STATE_2=enable scope=both; 
#ALTER DATABASE RECOVER MANAGED STANDBY DATABASE USING CURRENT LOGFILE DISCONNECT FROM SESSION;
#ALTER SYSTEM SET dg_broker_start=true;
#"

#echo "
#May need to run the following steps manually on the primary database
#
#alter system set LOG_ARCHIVE_DEST_STATE_2=enable scope=both;
#"

}


function duplicate {

echo "
Instantiate standby database started at " `/bin/date '+%Y%m%d%H%M%S'`
echo "ORACLE SID is $ORACLE_SID"

rman log $drmanlog APPEND << EOF
connect AUXILIARY /
set echo on;
@$drmanfiled
EOF


if [[ `grep -i error ${drmanlog}` ]]; then
   if [[ `grep -i "fs0 not allocated" $drmanlog` ]]; then
      echo "Database duplicate finished at " `/bin/date '+%Y%m%d%H%M%S'`
      echo clean the softlink
   else
      echo "Database duplicatep failed at " `/bin/date '+%Y%m%d%H%M%S'`
      echo clean the softlink
      echo "spfile is"
      ls -l ${oracle_home}/dbs/spfile${toraclesid}.ora
      echo "Check rmanlog file $drmanlog"
      echo "The last 10 line of rman log output"
      echo " "
      tail $drmanlog 
      echo " "
      echo "Once the error is identified and corrected, you can rerun the duplicate command. 
	  "
      exit 1
   fi
else
  echo "Database duplicate finished at " `/bin/date '+%Y%m%d%H%M%S'`
  echo clean the softlink
fi

if [[ -d ${backup_location} ]]; then
   /bin/rm ${backup_location}/*
   rmdir ${backup_location}
fi

echo " 
May need to run the following steps manually on the standby database

create spfile from pfile; 
alter system set LOG_ARCHIVE_DEST_STATE_2=enable scope=both; 
ALTER DATABASE RECOVER MANAGED STANDBY DATABASE USING CURRENT LOGFILE DISCONNECT FROM SESSION;
ALTER SYSTEM SET dg_broker_start=true;
"

echo "
May need to run the following steps manually on the primary database

alter system set LOG_ARCHIVE_DEST_STATE_2=enable scope=both;
"

}

echo "
This script will instantiate a Data Guard Physical Standby Database by using Cohesity Oracle Recovery View function.
Cohesity recovery view and NFS mounts need to done before running this script.
Also it doesn't change the configuration in the Primary database. All the necessary Data Guard preparation steps 
should be completed before running this script.  

"

setup
echo " "
echo prepare duplication
check_oracle_init_file
create_softlink
create_rman_duplicate_file_localdisk
if [[ $preview = [Yy]* ]]; then
   echo " "
   echo ORACLE DATABASE DUPLICATE SCRIPT
   echo " "
   echo "the standby instantiate RMAN commands are in $drmanfiled"
else
   if [[ $force = [Yy]* ]]; then
      duplicate_prepare
   else
      duplicate_prepare
      echo " "
      read -p "It is reommended to clean up the the files associated with database $toraclesid first. Do you want to continue? " answer3
      if [[ $answer3 != [Yy]* ]]; then
         exit
      fi
   fi
   duplicate
fi
