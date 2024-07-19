#!/bin/bash
#
# Name:         restore-ora-cohesityadapter.bash
#
# Function: 	This script will call Brian's phython script to restore Oracle database.
#				If the database that should be restored to is up running. This script will drop the database first
#
# Show Usage: run the command to show the usage
#
# Changes:
# 12/08/23 Diana Yang   New script
#
#################################################################

umask 036

function show_usage {
echo "usage: restore-ora-cohesityadapter.bash -b <restoreOracle-v2.py script with input> -f <yes/no> -d <yes/no>"
echo " "
echo " Required Parameters"
echo " -b : restoreOracle-v2.py script with input. ( example: \"/home/oracle1/scripts/brian/python/restoreOracle-v2.py -v cohesity -u ora -i -ss oracle1 -ts oracle2 -sd cohcdbt -td restore1 -oh /u01/app/oracle1/product/19.3.0/dbhome_1 -ob /u01/app/oracle1 -od '+DATA1'\" ) "
echo " "
echo " Optional Parameters"
echo " -f : yes means the script will execute restoreOracle-v2.py script with input, the default is no"
echo " -d : yes means the database which needs to be refreshed can be dropped first without prompting, the default is no"
echo " "
}

while getopts ":b:f:d:" opt; do
  case $opt in
    b ) pycom=$OPTARG;;
    f ) execute=$OPTARG;;
    d ) dropdb=$OPTARG;;
  esac
done

if [[ -z $pycom ]]; then
  show_usage 
  exit 1
fi

echo " "
echo "python script is"
echo " "
echo $pycom
echo " "

pyscript=`echo $pycom | awk '{print $1}'`

if [[ ! -f $pyscript ]]; then
   echo "python script $pyscript doesn't exist. Exit"
   exit 1
fi

pydir=`echo $pyscript | awk 'BEGIN{FS=OFS="/"}{NF--; print}'`

if [[ ! -f ${pydir}/pyhesity.py ]]; then
   echo "file ${pydir}/pyhesity.py doesn't exist. exit"
   exit 1
fi

DATE_SUFFIX=`/bin/date '+%Y%m%d%H%M%S'`

function setup {
if test $host
then
  hostdefinded=yes
else
  host=`hostname -s`
fi

sqllogin="sqlplus / as sysdba"
rmanlogin="rman target /"

dbname=`echo $pycom | awk -F "-td" '{print $2}' | awk -F "-" '{print $1}'`
dbname=`echo $dbname | xargs`

origdbname=`echo $pycom | awk -F "-sd" '{print $2}' | awk -F "-" '{print $1}'`
origdbname=`echo $origdbname | xargs`

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

logdir=$DIR/log/$host
runlog=$DIR/log/$host/$dbname.$DATE_SUFFIX.log
oratabsave=$DIR/log/$host/oratab.save.$DATE_SUFFIX
oratabtemp=$DIR/log/$host/oratabtemp.$DATE_SUFFIX
droplog=$DIR/log/$host/$dbname.drop.$DATE_SUFFIX.log

#trim log directory
touch $DIR/log/$host/${dbname}.$DATE_SUFFIX.jobstart
find $DIR/log/$host/${dbname}* -type f -mtime +7 -exec /bin/rm {} \;
find $DIR/log/$host/* -type f -mtime +14 -exec /bin/rm {} \;

echo "python script is 

$pycom

" >> $runlog

# get Oracle home from pycom
oraclehome=`echo $pycom | awk -F "-oh" '{print $2}' | awk -F "-" '{print $1}'`
oraclehome=`echo $oraclehome | xargs`
export ORACLE_HOME=$oraclehome
export PATH=$PATH:$ORACLE_HOME/bin
export NLS_DATE_FORMAT='DD:MM:YYYY-HH24:MI:SS'

# get Oracle sid
oraclesid=$dbname
export ORACLE_SID=$oraclesid
}

function drop_database {

j=0
echo "check whether the database is up"
runoid=`ps -ef | grep pmon | awk 'NF>1{print $NF}' | grep -i $oraclesid | awk -F "pmon_" '{print $2}'`

if [[ ${runoid} != ${oraclesid} ]]; then
   echo "The database is not up"
   echo "The database is not up" >> $runlog
   if [[ $k -eq 1 ]]; then
      echo "The database information is in /etc/oratab. Will try to drop this database"
      echo "The database information is in /etc/oratab. Will try to drop this database" >> $runlog
      j=1
      echo "Oracle database $oraclesid is not up"
      echo "Oracle database $oraclesid is not up" >> $runlog
      echo "start the database in nomount, restore spfile, and restart the database in nomount at " `/bin/date '+%Y%m%d%H%M%S'`
      echo "start the database in nomount, restore spfile, and restart the database in nomount at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog
      $sqllogin << EOF
        startup mount exclusive;
        Alter system enable restricted session;
EOF
    else
      echo "The database information is also not in /etc/oratab. Will restore database next"
    fi
else
   j=1
   echo "Oracle database $oraclesid is up"
   echo "shutdown the database first"
   echo "start the database in nomount, restore spfile, and restart the database in nomount"
   $sqllogin << EOF
   shutdown immediate;
   startup mount exclusive;
   Alter system enable restricted session; 
EOF
fi

if [[ $j -eq 1 ]]; then
   echo "drop database $oraclesid started at " `/bin/date '+%Y%m%d%H%M%S'`
   echo "drop database $oraclesid started at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog
   $rmanlogin log $droplog << EOF > /dev/null
   drop database including backups noprompt; 
EOF

   if [ $? -ne 0 ]; then
      echo "Drop database $oraclesid failed at " `/bin/date '+%Y%m%d%H%M%S'`
      echo "Drop database $oraclesid failed at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog
      while IFS= read -r line
      do
         echo $line
      done < $droplog
      exit 1
   else
      echo "Drop database $oraclesid finished at " `/bin/date '+%Y%m%d%H%M%S'`
      echo "Drop database $oraclesid finished at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog 
   fi
fi

}

function clean_oratab {

# check whether this database $dbanme is in /etc/oratab. If it isn't, the script will not drop the database
oratabinfo=`grep -i $dbname /etc/oratab`

arrinfo=($oratabinfo)
leninfo=${#arrinfo[@]}

k=0
for (( i=0; i<$leninfo; i++))
do
  orasidintab=`echo ${arrinfo[$i]} | awk -F ":" '{print $1}'`
  
  if [[ $orasidintab == ${dbname} ]]; then    
     echo "The database information is in /etc/oratab. Will remove the line that has this database information."
     echo "we assume it is up running. The scrip will drop it before refreashing it"
     k=1
  fi
done

if [[ $k -eq 1 ]]; then
# save old oratab
  echo "save /etc/oratab to $oratabsave"
  cp /etc/oratab $oratabsave

  if [ $? -ne 0 ]; then
     echo "copy /etc/oratab file failed "
     exit 1
  fi

# create new oratab

  while IFS= read -r line
  do
     orasidintab=`echo $line | awk -F ":" '{print $1}'`
     if [[ $orasidintab != ${dbname} ]]; then
        echo $line >> $oratabtemp
     fi
  done < /etc/oratab

  cp $oratabtemp /etc/oratab

  if [ $? -ne 0 ]; then
     echo "copy $oratabtemp to /etc/oratab failed"
     exit 1
  fi
  
  echo "Removing the line that has this database information in /etc/oratab is successful"
fi

}

setup
if [[ $execute != [Yy]* ]]; then
   echo "python command to do the database restore"
   echo " "
   echo $pycom
   echo " "
else
   clean_oratab
   if [[ $dropdb == [Yy]* ]]; then
      drop_database
   else
      echo " "
      echo "Please use -d yes as the input option of the script if this is a scheduled job"
      echo " "
      read -p "Please type yes if you want to drop database $oraclesid if it exists?  " answer1
      if [[ $answer1 != [Yy]* ]]; then
         echo " "
         echo "The answer is no. The database $oraclesid won't be dropped. The restore will not happen "
         echo " "
         exit
      else
         drop_database
      fi
   fi
         
   sleep 60 
   echo "Clean up is done. Will restore database $oraclesid from the backup of database $origdbname" 
   echo "Clean up is done. Will restore database $oraclesid from the backup of database $origdbname"  >> $runlog
   $pycom

   if [ $? -ne 0 ]; then
     echo "python script failed at " `/bin/date '+%Y%m%d%H%M%S'`
     echo "python script failed at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog
     echo "Restore database $oraclesid from the backup of database $origdbname failed" 
     echo "Restore database $oraclesid from the backup of database $origdbname failed" >> $runlog
     exit 1
   else
     echo "python script finished at " `/bin/date '+%Y%m%d%H%M%S'`
     echo "python script finished at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog
     echo "Restoring database $oraclesid from the backup of database $origdbname is successful"
     echo "Restoring database $oraclesid from the backup of database $origdbname is successful" >> $runlog
   fi
fi
