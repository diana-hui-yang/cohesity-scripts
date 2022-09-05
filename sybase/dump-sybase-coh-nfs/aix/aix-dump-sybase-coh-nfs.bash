#!/bin/bash
#
# Name:         aix-dump-sybase-coh-nfs.bash
#
# Function:     This script dump sybase using nfs mount.
# Show Usage: run the command to show the usage
#
# Changes:
# 06/15/22 Diana Yang   New script
# 08/15/22 Diana Yang   Add dump striping to the script
# 08/30/22 Diana Yang   change "awk" to "/opt/freeware/bin/gawk" 
# 08/30/22 Diana Yang   change "find" to "/opt/freeware/bin/find"
# 08/30/22 Diana Yang   change "/bin/rm" to "/opt/freeware/bin/rm"
#
#################################################################

function show_usage {
echo "usage: dump-sybase-coh-nfs.bash -U <sybase sa user> -P <password> -k <key> -S <service name> -d <database name> -t <db or log> -m <mount-prefix> -n <number of mounts> -p <number of stripes> -e <retention> -X <yes/no> -w <yes/no>"
echo " "
echo " Required Parameters"
echo " -k : sybase login key"
echo " -d : database name"
echo " -t : dump type. db means database dump, log means transactional dump"
echo " -m : mount-prefix (like /coh/sybase)"
echo " -n : number of mounts (only 1 is supported currently)"
echo " -e : Retention time (days to retain the dumps)"
echo " "
echo " Optional Parameters"
echo " -U : sybase user. It is not needed when using key"
echo " -P : sybase password. It is not needed when using key"
echo " -S : Service name. It is not needed when using key"
echo " -X : yes means Sybase -X is used. The default is no"
echo " -p : number of stripes (Optional, only 1 is supported currently)"
echo " -w : yes means preview sybase dump scripts"
echo "
"
}

while getopts ":k:U:P:S:X:d:t:m:n:e:p:w:" opt; do
  case $opt in
    k ) key=$OPTARG;;
    U ) user=$OPTARG;;
    d ) dbname=$OPTARG;;
    P ) password=$OPTARG;;
    S ) servicename=$OPTARG;;
    t ) dumptype=$OPTARG;;
    m ) mount=$OPTARG;;
    n ) num=$OPTARG;;
    p ) parallel=$OPTARG;;
    e ) retday=$OPTARG;;
    X ) xparam=$OPTARG;;
    w ) preview=$OPTARG;;
  esac
done

#echo $password $parallel
echo "check whether gnu utilities /opt/freeware/bin/gawk, /opt/freeware/bin/find, and /opt/freeware/bin/rm exist on this AIX server"
if [[ ! -f /opt/freeware/bin/gawk ]]; then
    echo "gnu untility /opt/freeware/bin/gawk is not on this AIX server, please download it from 
	https://www.ibm.com/support/pages/aix-toolbox-open-source-software-downloads-alpha
	yum commands to download the three utilities are
	yum install gawk-5.1.1-1
	yum install findutils-4.6.0-2
	yum install coreutils-8.32-1.ppc
	"
fi

if [[ ! -f /opt/freeware/bin/find ]]; then
    echo "gnu untility /opt/freeware/bin/gawk is not on this AIX server, please download it from 
	https://www.ibm.com/support/pages/aix-toolbox-open-source-software-downloads-alpha
	yum commands to download the three utilities are
	yum install gawk-5.1.1-1
	yum install findutils-4.6.0-2
	yum install coreutils-8.32-1.ppc
	"
fi

if [[ ! -f /opt/freeware/bin/rm ]]; then
    echo "gnu untility /opt/freeware/bin/gawk is not on this AIX server, please download it from 
	https://www.ibm.com/support/pages/aix-toolbox-open-source-software-downloads-alpha
	yum commands to download the three utilities are
	yum install gawk-5.1.1-1
	yum install findutils-4.6.0-2
	yum install coreutils-8.32-1.ppc
	"
fi

# Check required parameters
fullcommand=($@)
lencommand=${#fullcommand[@]}
#echo $lencommand

# Check required parameters
if test $mount && test $dbname && test $num && test $retday && test $dumptype
then
  :
else
  show_usage 
  exit 1
fi

function setup {

if test $key
then
   :
else
   if test $user && test $password && test $servicename
   then
      :
   else
      echo "user information needs to be provided"
      show_usage 
      exit 1
   fi
fi

i=0
for (( i=0; i<$lencommand; i++ ))
do
   if [[ ${fullcommand[$i]} == -t ]]; then
      typeset=yes
   fi
done
if [[ -n $typeset ]]; then
   if [[ $dumptype != "db" && $dumptype != "log" ]]; then
      echo "'db' or 'log' should be provided after -t in syntax, other answer is not valid"
      exit 2
   fi
fi

i=0
for (( i=0; i<$lencommand; i++ ))
do
   if [[ ${fullcommand[$i]} == -X ]]; then
      xparamset=yes
   fi
done
if [[ -n $xparamset ]]; then
   if [[ -z $xparam ]]; then
      echo "Please enter 'yes' as the argument for -X. It may be empty or not all options are given an argument. All options should be given an arguments"
      exit 2
   else
      if [[ $xparam != [Yy]* && $xparam != [Nn]* ]]; then
         echo "'yes' or "no" should be provided after -X in syntax, other answer is not valid"
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

if [[ ! -d $DIR/log/$servicename ]]; then
  echo " $DIR/log/$servicename does not exist, create it"
  mkdir -p $DIR/log/$servicename
  
  if [ $? -ne 0 ]; then
    echo "create log directory $DIR/log/$servicename failed. There is a permission issue"
    exit 1
  fi
fi

runlog=$DIR/log/$servicename/$dbname.$DATE_SUFFIX.log
runrlog=$DIR/log/$servicename/${dbname}.r.$DATE_SUFFIX.log
stdout=$DIR/log/$servicename/${dbname}.$DATE_SUFFIX.std
sybasedb=$DIR/log/$servicename/$dbname.db.$DATE_SUFFIX.sql
sybasedb_cmd=$DIR/log/$servicename/$dbname.db.$DATE_SUFFIX.bash
sybaselog=$DIR/log/$servicename/$dbname.log.$DATE_SUFFIX.sql
sybaselog_cmd=$DIR/log/$servicename/$dbname.log.$DATE_SUFFIX.bash

#trim log directory
/opt/freeware/bin/find $DIR/log/$servicename/${dbname}* -type f -mtime +7 -exec /opt/freeware/bin/rm {} \;
/opt/freeware/bin/find $DIR/log/$servicename -type f -mtime +14 -exec /opt/freeware/bin/rm {} \;

}

function create_sybase_db {

i=1
j=1
while [ $i -le $num ]; do
#  echo i is $i
#  echo j is $j
  mountstatus=`mount | grep -i  "${mount}${i}"`
  if [[ -n $mountstatus ]]; then
#    echo "$mount${i} is mount point"
#    echo " "
    if [[ ! -d "${mount}${i}/${servicename}/${dbname}" ]]; then
       echo "Directory ${mount}${i}/${servicename}/${dbname} does not exist, create it"
       if mkdir -p ${mount}${i}/${servicename}/${dbname}; then
          echo "${mount}${i}/${servicename}/${dbname} is created"
       else
          echo "creating ${mount}${i}/${servicename}/${dbname} failed. There is a permission issue"
          exit 1
       fi
    fi

    echo "Create sybase db dump file" >> $runlog
    if [[ $j -eq 1 ]]; then
       echo "dump database $dbname to '${mount}${i}/${servicename}/${dbname}/full_${dbname}_$j.${DATE_SUFFIX}.dmp' " >> ${sybasedb}
    elif [[ $j -le $parallel ]]; then
       echo "stripe on '${mount}${i}/${servicename}/${dbname}/full_${dbname}_$j.${DATE_SUFFIX}.dmp' " >> ${sybasedb}
    fi

    if [[ $i -ge $num && $j -lt $parallel ]]; then 
       i=0
    fi
 
    i=$[$i+1]
    j=$[$j+1]
 
  else
    echo "$mount${i} is not a mount point. dump will not start
    The mount prefix may not be correct or
    The input of the number of mount points may exceed the actuall number of mount points"
    exit 1
  fi	
done
  
echo go >> ${sybasedb}

if [[ -n $key ]]; then
   if [[ $xparam = [Yy]* ]]; then
      echo "isql64 -k $key -X -i $sybasedb" > ${sybasedb_cmd}
   else
      echo "isql64 -k $key -i $sybasedb" > ${sybasedb_cmd}
   fi
else
   if [[ $xparam = [Yy]* ]]; then
      echo "isql64 -U $user -P '${password}' -S $servicename -X -i $sybasedb" > ${sybasedb_cmd}
   else   
      echo "isql64 -U $user -P '${password}' -S $servicename -i $sybasedb" > ${sybasedb_cmd}
   fi
fi
chmod 750 ${sybasedb_cmd}

}

function create_sybase_log {

num=1
echo "Create sybase transactional log dump file" >> $runlog
echo "dump tran $dbname to \"${mount}${num}/${servicename}/${dbname}/log_${dbname}.${DATE_SUFFIX}.dmp\"
go
" > ${sybaselog}

if [[ -n $key ]]; then
   if [[ $xparam = [Yy]* ]]; then
      echo "isql64 -k $key -X -i $sybaselog" > ${sybaselog_cmd}
   else
      echo "isql64 -k $key -i $sybaselog" > ${sybaselog_cmd}
   fi
else
   if [[ $xparam = [Yy]* ]]; then
      echo "isql64 -U $user -P '${password}' -S $servicename -X -i $sybaselog" > ${sybaselog_cmd}
   else   
      echo "isql64 -U $user -P '${password}' -S $servicename -i $sybaselog" > ${sybaselog_cmd}
   fi
fi
chmod 750 ${sybaselog_cmd}

}

function dump_sybase_db {

${sybasedb_cmd}

if [ $? -ne 0 ]; then
  echo "
  Database dump failed at " `/bin/date '+%Y%m%d%H%M%S'`
  echo "
  Database dump failed at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog
  exit 1
else
  echo "
  Database dump finished at " `/bin/date '+%Y%m%d%H%M%S'`
  echo "
  Database dump finished at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog 
fi

}

function dump_sybase_log {

${sybaselog_cmd}

if [ $? -ne 0 ]; then
  echo "
  Transactional log dump failed at " `/bin/date '+%Y%m%d%H%M%S'`
  echo "
  Transactional log dump failed at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog
  exit 1
else
  echo "
  Transactional log dump finished at " `/bin/date '+%Y%m%d%H%M%S'`
  echo "
  Transactional log dump finished at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog 
fi

}

function delete_expired {

if ! [[ "$retday" =~ ^[0-9]+$ ]]; then
  echo "$retday is not an integer. No data expiration after this dump"
  exit 1
  echo "Need to change the parameter after -e to be an integer"
else
  let retnewday=$retday+1
  echo "Clean dump files older than $retnewday started at " `/bin/date '+%Y%m%d%H%M%S'`
  echo "Clean dump files older than $retnewday started at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog
  echo "only delete old expired dump during database dump" >> $runlog
  if [[ -d "${mount}1/$servicename/$dbname" ]]; then
    /opt/freeware/bin/find ${mount}1/$servicename/$dbname -type f -mtime +$retnewday -exec /opt/freeware/bin/rm -f {} \;
    /opt/freeware/bin/find ${mount}1/$servicename/$dbname -depth -type d -empty -exec rmdir {} \;
  fi
  echo "Clean dump files older than $retnewday finished at " `/bin/date '+%Y%m%d%H%M%S'`
  echo "Clean dump files older than $retnewday finished at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog 
fi

}

setup

if [[ $dumptype = "db" ]]; then
   echo "database dump"
   create_sybase_db
   if [[ $preview = "yes" || $preview = "Yes" || $preview = "YES" ]]; then
      echo " "
      echo SYBASE DATABASE DUMP SCRIPT
      echo " "
      echo "---------------"
      cat $sybasedb
      echo "---------------"
      echo CMD
      echo " "
      echo "---------------"
      cat $sybasedb_cmd
      echo "---------------"
   else
      dump_sybase_db
      delete_expired
   fi
elif [[ $dumptype = "log" ]]; then
   echo "Transactional log dump"
   create_sybase_log
   if [[ $preview = "yes" || $preview = "Yes" || $preview = "YES" ]]; then
      echo " "
      echo SYBASE Transactional log DUMP SCRIPT
      echo " "
      echo "---------------"
      cat $sybaselog
      echo "---------------"
      echo CMD
      echo " "
      echo "---------------"
      cat $sybaselog_cmd
      echo "---------------"
   else
      dump_sybase_log
   fi
fi
