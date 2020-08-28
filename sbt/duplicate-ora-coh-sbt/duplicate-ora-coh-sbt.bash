#!/bin/bash
#
# Name:         duplicate-ora-coh-sbt.bash
#
# Function:     This script duplicate Oracle database from Oracle backup 
#               using backup-ora-coh-sbt.bash. This script needs recovery database or 
#				source database to run duplication since this backup uses sbt
#
#
# Show Usage: run the command to show the usage
#
# Changes:
# 08/07/2020 Diana Yang   New script (duplicate using target database)
# 08/21/2020 Diana Yang   Add more conditions
#
#################################################################

function show_usage {
echo "usage: duplicate-ora-coh-sbt.bash -r <RMAN login> -b <backup host> -a <target host> -d <Source Oracle_DB_Name> -t <Target Oracle instance name> -f <file contain duplicate settting> -i <file contain setting to new spfile> -j <vip file> -v <view> -s <sbt file name> -p <number of channels> -o <ORACLE_HOME> -c <source PDB> -w <yes/no>" 
echo " -r : RMAN login (example: \"rman auxiliary / target <user>/<password>@<source db connection> or rman auxiliary / catalog <user>/<password>@<catalog>\")"
echo " -b : backup host" 
echo " -a : target host (Optional, default is localhost)"
echo " -d : Source Oracle_DB_Name, If Source is not a RAC database, it is the same as Instance name. If it is RAC, it is DB name, not instance name" 
echo " -t : Target Oracle instance name. If it is not RAC, it is the same as DB name. If it is RAC, it is the instance name like cohcdba2"
echo " -f : File contains duplicate setting, example: set newname for database to '/oradata/restore/orcl/%b'; "
echo " -i : File contains new setting to spfile. example: SET DB_CREATE_FILE_DEST +DGROUP3"
echo " -j : file that has vip list"
echo " -v : Cohesity view"
echo " -s : Cohesity SBT library home"
echo " -p : number of channels (default is 4), optional"
echo " -o : ORACLE_HOME (default is current environment), optional"
echo " -c : Source pluggable database (if this input is empty, it is standardalone or CDB database restore)"
echo " -w : yes means preview rman duplicate scripts"
}

while getopts ":r:b:a:d:t:f:i:j:v:s:p:o:c:w:" opt; do
  case $opt in
    r ) rmanlogin=$OPTARG;;
    b ) shost=$OPTARG;;
    a ) thost=$OPTARG;;
    d ) sdbname=$OPTARG;;
    t ) toraclesid=$OPTARG;;
    f ) ora_pfile=$OPTARG;;
    i ) ora_spfile=$OPTARG;;
    j ) vipfile=$OPTARG;;
    v ) view=$OPTARG;;
    s ) sbtname=$OPTARG;;
    p ) parallel=$OPTARG;;
    o ) oracle_home=$OPTARG;;
    c ) spdbname=$OPTARG;;
    w ) preview=$OPTARG;;
  esac
done

echo $rmanlogin, $shost, $sdbname, $toraclesid, $view, $vipfile
echo "  "
echo "  "

# Check required parameters
#if test $shost && test $sdbname && test $toraclesid && test $tdbdir && test $mount && test $num
#if test $rmanlogin && test $shost && test $sdbname && test $toraclesid && test $view && test $vipfile
if test $shost && test $sdbname && test $toraclesid && test $view && test $vipfile
then
  :
else
  show_usage 
  exit 1
fi


function setup {
if test $thost
then
  :
else
  thost=`hostname -s`
fi

if [[ $shost = $thost ]]; then
#   echo $shost is the same as $thost
#   echo ora_pfile is ${ora_pfile}
   
   if [[ -z $spdbname ]]; then
      if [[ -z ${ora_pfile} ]]; then
        echo "new database files location needs to be defined in a file which is defined by -f option, example as the following"
        echo "set newname for database to '+DATAR';"
        exit 1
      else
        if [[ -z `grep -i newname $ora_pfile` ]]; then
          echo "new database files location needs to be defined in a file which is defined by -f option, example as the following"
          echo "set newname for database to '+DATAR';"
          exit 1
        fi
      fi
   fi
fi

if test $parallel
then
  :
else
  echo "no input for parallel, set parallel to be 4"
  parallel=4
fi

echo $rmanlogin
if [[ -z $rmanlogin ]]; then
  echo "  "
  echo "rmanlogin should be provided in input with -r option 
  syntax should be \"rman auxiliary / target <user>/<password>@<source db connection> or rman auxiliary / catalog <user>/<password>@<catalog>\""
  echo "  "
  echo "  "
  show_usage
  exit 1
fi


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
  echo " $DIR/log/$thost does not exist, create it"
  mkdir -p $DIR/log/$thost
  
  if [ $? -ne 0 ]; then
    echo "create log directory $DIR/log/$thost failed. There is a permission issue"
    exit 1
  fi
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

drmanlog=$DIR/log/$thost/$toraclesid.rman-duplicate.$DATE_SUFFIX.log
drmanfiled=$DIR/log/$thost/$toraclesid.rman-duplicate.$DATE_SUFFIX.rcv

# setup restore location
# get restore location from $ora_pfile
if [[ -z $spdbname ]]; then
  if [[ ! -z $ora_pfile ]]; then
    echo "ora_pfile is $ora_pfile"
    db_location=`grep -i newname $ora_pfile | awk -F "'" '{print $2}' | awk -F "%" '{print $1}'` 
# remove all space in $db_location
    db_location=`echo $db_location | xargs echo -n`
    echo new db_location is ${db_location}
# check whether it is ASM or dirctory
    if [[ ${db_location:0:1} != "+" ]]; then 
      echo "new db_location is a directory"
      if [[ ! -d ${db_location}data ]]; then
         echo "${db_location}/data does not exist, create it"
         mkdir -p ${db_location}data
      fi
      if [[ ! -d ${db_location}fra ]]; then
         echo "${db_location}/fra does not exist, create it"
         mkdir -p ${db_location}fra

         if [ $? -ne 0 ]; then
            echo "create new directory ${db_location} failed"
            exit 1
         fi
      fi
    fi 
  else
    echo "there is no ora_pfile"
  fi
fi

# get restore locaton from $ora_spfile
if [[ ! -z $ora_spfile ]]; then
   echo "ora_spfile is $ora_spfile"
# check db_create_file_dest location
   db_create_location=`grep -i db_create_file_dest $ora_spfile | awk -F "'" '{print $2}' | awk -F "%" '{print $1}'`
   if [[ -n $db_create_location ]]; then
     echo db_create_location is $db_create_location
# remove all space in $db_location variable
     db_create_location=`echo $db_create_location | xargs echo -n`
     echo db_create_location is $db_create_location
# check whether it is ASM or dirctory
     if [[ ${db_create_location:0:1} != "+" ]]; then
       echo "new db_create_location is a directory"
       if [[ ! -d ${db_create_location}/data ]]; then
         echo "${db_create_location}/data does not exist, create it"
         mkdir -p ${db_create_location}/data
       fi
       if [[ ! -d ${db_create_location}/fra ]]; then
         echo "${db_create_location}/fra does not exist, create it"
         mkdir -p ${db_create_location}/fra

         if [ $? -ne 0 ]; then
            echo "create new directory ${db_create_location}/fra failed"
            exit 1
         fi
       fi
     fi
   fi
else
   echo "there is no ora_spfile"
fi

#trim log directory
find $DIR/log/$thost -type f -mtime +7 -exec /bin/rm {} \;

if [ $? -ne 0 ]; then
  echo "del old logs in $DIR/log/$thost failed"
  exit 2
fi

export ORACLE_SID=$toraclesid
}

function create_rman_duplicate_file {

echo "Create rman duplicate file"
echo "RUN {" >> $drmanfiled

i=1
j=0
while [ $j -le $parallel ]; do

   while IFS= read -r ip; do
    
      ip=`echo $ip | xargs echo -n`    	
      echo "Check whether IP $ip can be connected"
      if [[ -n $ip ]]; then
         return=`/bin/ping $ip -c 2`

#           echo "return is $return"
         if echo $return | grep -q error; then
            echo "error: IP $ip can't be connected. It may not be a valid IP. Skip this IP"
         else
            echo "IP $ip can be connected"
	      	
            if [[ $j -lt $parallel ]]; then
              allocate_database[$j]="allocate auxiliary CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,gflag-name=sbt_use_grpc,gflag-value=true)';"
              unallocate[$j]="release channel c$j;"
            fi
            i=$[$i+1]
            j=$[$j+1]
	 fi
      fi
   done < $vipfile
done

for (( i=0; i < ${#allocate_database[@]}; i++ )); do
   echo ${allocate_database[$i]} >> $drmanfiled
done

#echo "ora_pfile is $ora_pfile"
#more $ora_pfile
if [[ ! -z $ora_pfile ]]; then
  if test -f $ora_pfile; then
    grep -v "^#" < $ora_pfile | { while IFS= read -r para; do
       para=`echo $para | xargs echo -n`
       echo $para >> $drmanfiled
    done }
  else
    echo "$ora_pfile does not exist"
    exit 1
  fi
fi

if [[ ! -z $ora_spfile ]]; then
  if test -f $ora_spfile; then
    if [[ -z $spdbname ]]; then
       echo "duplicate database $sdbname to $toraclesid" >> $drmanfiled
    else
       echo "duplicate database $sdbname to $toraclesid pluggable database $spdbname" >> $drmanfiled
    fi
    echo "SPFILE" >> $drmanfiled
    grep -v "^#" < $ora_spfile | { while IFS= read -r spara; do
       para=`echo $spara | xargs echo -n`
       echo $spara >> $drmanfiled
    done }
    echo "nofilenamecheck;" >> $drmanfiled
  else
     echo "$ora_spfile does not exist"
     exit 1
  fi
else
  if [[ -z $spdbname ]]; then
     echo "duplicate database $sdbname to $toraclesid nofilenamecheck;" >> $drmanfiled
  else
     echo "duplicate database $sdbname to $toraclesid pluggable database $spdbname nofilenamecheck;" >> $drmanfiled
  fi
fi  

for (( i=0; i < ${#unallocate[@]}; i++ )); do
   echo ${unallocate[$i]} >> $drmanfiled
done

echo "
}
exit;
" >> $drmanfiled

echo "finished creating rman duplicate file"
}


function duplicate {

echo "Database duplicate started at " `/bin/date '+%Y%m%d%H%M%S'`
echo "ORACLE SID is $ORACLE_SID"

$rmanlogin log $drmanlog @$drmanfiled

if [ $? -ne 0 ]; then
  echo "Database duplicatep failed at " `/bin/date '+%Y%m%d%H%M%S'`
  echo "If Oracle duplicate job fails, Check whether Oracle database $toraclesid started in nomount mode"
  echo "If Oracle duplicate job fails and it is PDB restore, Check whether Oracle database $toraclesid is started"
  echo "We have seen that Oracle reports failure, but the duplication is actually successful."
  ls -l ${oracle_home}/dbs/spfile*
  echo "The last 10 line of rman log output"
  echo " "
  echo "rmanlog file is $drmanlog"
  tail $drmanlog 
  exit 1
else
  echo "Database duplicate finished at " `/bin/date '+%Y%m%d%H%M%S'`
fi

}

setup
create_rman_duplicate_file
if [[ $preview = "yes" || $preview = "Yes" || $preview = "YES" ]]; then
   echo ORACLE DATABASE DUPLICATE SCRIPT
   echo " "
   cat $drmanfiled
else
   duplicate
fi
