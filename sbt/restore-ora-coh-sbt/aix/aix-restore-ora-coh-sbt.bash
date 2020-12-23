#!/bin/bash
#
# Name:         restore-ora-coh-sbt.bash
#
# Function:     This script restore Oracle database from Oracle backup 
#               using Cohesity SBT tape backup script backup-ora-coh-sbt.bash.
#
#
# Show Usage: run the command to show the usage
#
# Changes:
# 07/25/20 Diana Yang   New script (restore to target database)
# 07/31/20 Diana Yang   Add controlfile restore
# 08/06/20 Diana Yang   Rename this file from restore-ora-coh-dedup.bash to restore-ora-coh-sbt.bash
# 08/16/20 Diana Yang   All set newname during restore
# 10/30/20 Diana Yang   Standardlize name. Remove "-f" and "-s" as required parameter
# 11/11/20 Diana Yang   Remove the need to manually create vip-list file
# 12/22/20 Diana Yang   Modify it to work on AIX server
#
#################################################################

function show_usage {
echo "usage: aix-restore-ora-coh-sbt.bash -h <backup host> -i <Oracle instance name> -d <Oracle_DB_Name> -y <Cohesity-cluster> -c <file contain restore settting> -t <point-in-time> -l <yes/no> -j <vip file> -v <view> -s <sbt file name> -p <number of channels> -o <ORACLE_HOME> -f <yes/no> -w <yes/no>"
echo " "
echo " Required Parameters"
echo " -i : Oracle instance name. If it is not RAC, it is the same as DB name. If it is RAC, it is the instance name like cohcdba2"
echo " -d : Source Oracle_DB_Name, only required if it is RAC. It is DB name, not instance name"
echo " -y : Cohesity Cluster DNS name"
echo " -v : Cohesity view"
echo " -f : yes means force. It will restore Oracle database. Without it, it will just run RMAN validate (Optional)"
echo " "
echo " Optional Parameters"
echo " -h : backup host (default is current host), optional"
echo " -c : File contains restore location setting, example: set newname for database to '/oradata/restore/orcl/%b'; "
echo " -t : Point in Time (format example: \"2019-01-27 13:00:00\"), optional"
echo " -l : yes means complete restore including control file, no means not restoring controlfile"
echo " -p : number of channels (default is 4), optional"
echo " -j : The file lists Cohesity Cluster VIPs (default name is vip-list and default directory is config)"
echo " -s : Cohesity SBT library name including directoy or just directory (default name is libsbt_aix_powerpc.so, default directory is lib) "
echo " -o :  ORACLE_HOME (default is current environment), optional"
echo " -w : yes means preview rman backup scripts"
}

while getopts ":h:i:d:c:t:y:l:j:v:s:p:o:f:w:" opt; do
  case $opt in
    h ) host=$OPTARG;;
    i ) oraclesid=$OPTARG;;
    d ) dbname=$OPTARG;;
    c ) ora_pfile=$OPTARG;;
    t ) itime=$OPTARG;;
    y ) cohesityname=$OPTARG;;
    l ) full=$OPTARG;;
    j ) vipfile=$OPTARG;;
    v ) view=$OPTARG;;
    s ) sbtname=$OPTARG;;
    p ) parallel=$OPTARG;;
    o ) oracle_home=$OPTARG;;
    f ) force=$OPTARG;;
    w ) preview=$OPTARG;;
  esac
done

#echo $oraclesid  $full $view $sbtname $vipfile

# Check required parameters
#if test $host && test $dbname && test $mount && test $numm
if test $oraclesid  && test $view 
then
  :
else
  show_usage 
  exit 1
fi


function setup {
if test $host
then
  :
else
  host=`hostname -s`
fi

if test $dbname
then
  : 
else
  echo "No Oracle database name is provided. We assume this is not a RAC database" 
  dbname=$oraclesid
fi

if test $parallel
then
  :
else
  echo "no input for parallel, set parallel to be 4"
  parallel=4
fi

if [[ -n $itime && $full != [Yy]* ]]; then
  echo "Point in time restore requires restore controlfile The option -l should be yes"
  exit 1
fi

rmanlogin="rman target /"
echo "rman login command is $rmanlogin"

if test $oracle_home; then
#  echo *target*
  echo "ORACLE_HOME is $oracle_home"
  ORACLE_HOME=$oracle_home
  export ORACLE_HOME=$oracle_home
  export PATH=$PATH:$ORACLE_HOME/bin
else
  oracle_home=`env | grep ORACLE_HOME | gawk -F "=" '{print $2}'`
  if [[ -z $oracle_home ]]; then
     echo " is not defined. Need to specify ORACLE_HOME"
     exit 1
  fi   
fi
export NLS_DATE_FORMAT='DD:MM:YYYY-HH24:MI:SS'

DATE_SUFFIX=`/bin/date '+%Y%m%d%H%M%S'`
#echo $DATE_SUFFIX

DIRcurrent=$0
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

if [[ ! -d $DIR/config ]]; then
  echo " $DIR/config does not exist, create it"
  mkdir -p $DIR/config
  
  if [ $? -ne 0 ]; then
    echo "create log directory $DIR/config failed. There is a permission issue"
    exit 1
  fi
   
fi

if [[ -z $cohesityname ]]; then
  echo "Cohesity Cluster name is not provided, we will use vipfile ${DIR}/config/vip-list"
  if [[ -z $vipfile ]]; then
     vipfile=${DIR}/config/vip-list
  fi

  if test -f $vipfile; then
     echo "file $vipfile provided exists, script continue"
  else 
     echo "file $vipfile provided does not exist"
     exit 1
  fi
else
  vipfiletemp=${DIR}/config/${oraclesid}-vip-list-temp
  vipfile=${DIR}/config/${oraclesid}-vip-list
  echo "Cohesity Cluster name is $cohesityname. VIPS will be collected and stored in $vipfile"
  nslookup $cohesityname | grep -i address | tail -n +2 | gawk '{print $2}' > $vipfiletemp
  
  if [[ ! -s $vipfiletemp ]]; then
     echo "Cohesity Cluster name $cohesityname provided here is not in DNS"
     exit 1
  fi

  shuf $vipfiletemp > $vipfile
fi

if [[ -n $sbtname ]]; then
   if [[ $sbtname == *".so" ]]; then
      echo "we will use the sbt library provided $sbtname"
   else  
      echo "This may be a directory"
      sbtname=${sbtname}/libsbt_aix_powerpc.so
   fi
else
    echo "we assume the sbt library is in $DIR/../lib"
    sbtname=${DIR}/lib/libsbt_aix_powerpc.so
fi

if test -f $sbtname; then
   echo "file $sbtname exists, script continue"
else
   echo "file $sbtname does not exist. exit"
   exit 1
fi

restore_rmanlog=$DIR/log/$host/$dbname.rman-restore.$DATE_SUFFIX.log
restore_rmanfile=$DIR/log/$host/$dbname.rman-restore.$DATE_SUFFIX.rcv
recover_rmanlog=$DIR/log/$host/$dbname.rman-recover.$DATE_SUFFIX.log
recover_rmanfile=$DIR/log/$host/$dbname.rman-recover.$DATE_SUFFIX.rcv
spfile_rmanlog=$DIR/log/$host/$dbname.rman-spfile.$DATE_SUFFIX.log
spfile_rmanfile=$DIR/log/$host/$dbname.rman-spfile.$DATE_SUFFIX.rcv
controlfile_rmanlog=$DIR/log/$host/$dbname.rman-controlfile.$DATE_SUFFIX.log
controlfile_rmanfile=$DIR/log/$host/$dbname.rman-controlfile.$DATE_SUFFIX.rcv
incarnation=$DIR/log/$host/$dbname.incar_list

# setup restore location
# get restore location from $ora_pfile
if [[ ! -z $ora_pfile ]]; then
   echo "ora_pfile is $ora_pfile"
   db_location=`grep -i newname $ora_pfile | gawk -F "'" '{print $2}' | gawk -F "%" '{print $1}'` 
# remove all space in $db_location
   db_location=`echo $db_location | xargs`
   echo new db_location is ${db_location}
# check whether it is ASM or dirctory
   if [[ ${db_location:0:1} != "+" ]]; then 
      echo "new db_location is a directory"
      if [[ ! -d ${db_location}/data ]]; then
         echo "${db_location}/data does not exist, create it"
         mkdir -p ${db_location}/data
      fi
      if [[ ! -d ${db_location}/fra ]]; then
         echo "${db_location}/fra does not exist, create it"
         mkdir -p ${db_location}/fra

         if [ $? -ne 0 ]; then
            echo "create new directory ${db_location} failed"
            exit 1
         fi
      fi
   fi 
else
   echo "there is no ora_pfile"
fi

# make sure ora_pfile does not have time setting
if test $ora_pfile; then
  if [[ `grep -i time $ora_pfile` ]]; then
     echo "point-in-time setting should not be set in file $ora_pfile"
	 exit 1
  fi
fi


# covert the time to numeric 
if [[ -z $itime ]]; then
  ptime=`/bin/date '+%Y%m%d%H%M%S'`
  echo "current time is `/bin/date`,  point-in-time restore time $ptime"  
else   
  ptime=`/bin/date -d "$itime" '+%Y%m%d%H%M%S'`
  echo "itime is $itime,  point-in-time restore time $ptime"
fi

#trim log directory
find $DIR/log/$host -type f -mtime +7 -exec /bin/rm {} \;

if [ $? -ne 0 ]; then
  echo "del old logs in $DIR/log/$host failed"
  exit 2
fi

export ORACLE_SID=$oraclesid
}

function create_rman_restore_controlfile {

# find the right controlfile backup

echo "need to get the correct controlfile backup file, either the file name or mount points that has the controlfile"

while true; do
  read -p "Do you know the correct controlfile backup file name: choose yes or no. If no, choose the directory that has the controlfile next " yn
  case $yn in
    [Yy]* ) read -p "Enter the file name: " controlfile; break;;
    [Nn]* ) read -p "Do you know the directory that has the controlfile: " answer; break;;
    * ) echo "Please answer yes or no.";;
  esac
done

if [[ -z $controlfile ]]; then
  if [[ $answer = [Yy]* ]]; then
    read -p "Enter the directory that has the controlfile backup of this database: " mount
  
    cd ${mount}
    if [ $? -ne 0 ]; then
       echo "the directory ${mount} provided is incorrect"
       exit 3
    fi

    echo "get point-in-time controlfile"

    for bfile in ${dbname^^}_c-*.ctl; do
      bitime=`ls -l $bfile | gawk '{print $6 " " $7 " " $8}'`
      if [ $? -ne 0 ]; then
  	echo "the directory ${mount} provided is incorrect"
        exit 3
      fi 
      btime=`/bin/date -d "$bitime" '+%Y%m%d%H%M%S'`
#     echo file time $btime
#     echo ptime $ptime
      if [[ $ptime -lt $btime ]]; then
        controlfile=$bfile
        break
      else 
        controlfile1=$bfile
      fi
    done
    cd ${DIR}
  else
     echo "Can not determine the controlfile backup location. exit the script"
     exit
  fi
fi

if [[ -z $controlfile ]]; then
   if [[ -z $controlfile1 ]]; then
     echo "The cnntrolfile for database $dbname at $ptime is not found"
     exit 1
   else
     controlfile=$controlfile1
   fi
fi

echo "The controlfile is $controlfile"

# get cohesity cluster VIP
i=1
while IFS= read -r ip; do
    
   ip=`echo $ip | xargs`    	
   echo "Check whether IP $ip can be connected"
   if [[ -n $ip ]]; then
      return=`ping -c 2 $ip`

#           echo "return is $return"
      if echo $return | grep -q error; then
         echo "error: IP $ip can't be connected. It may not be a valid IP. Skip this IP"
      else
         echo "IP $ip can be connected"
         break   
      fi
      i=$[$i+1]
   fi 
done < $vipfile

echo "will create spfile rman backup script"
echo controlfile backup file is $controlfile
echo "
run {
allocate CHANNEL c1 TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,gflag-name=sbt_use_grpc,gflag-value=true)';
restore spfile from '$controlfile';
release CHANNEL c1;
}
" >> $spfile_rmanfile

echo "will create controlfile rman backup script"
echo "
run {
allocate CHANNEL c1 TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,gflag-name=sbt_use_grpc,gflag-value=true)';
restore CONTROLFILE from '$controlfile';
release CHANNEL c1;
}
" >> $controlfile_rmanfile

}

function reset_incarnation_afterrestore {

echo "incarnation after restore"
$rmanlogin log $incarnation << EOF
list incarnation of database;
exit;
EOF

incar_num2=`grep -i $dbname  $incarnation | grep -i CURRENT | gawk '{print $2}'`
echo "Oracle database incarnation is $incar_num2"

if [[ $incar_num1 != $incar_num2 ]]; then
   echo "reset database incarnation"
   $rmanlogin  << EOF
   reset database to incarnation $incar_num1;
   exit;
EOF
else
   echo "no need to reset database incarnation"
fi

echo "incarnation after reset"
$rmanlogin log $incarnation << EOF
list incarnation of database;
exit;
EOF

incar_num3=`grep -i $dbname  $incarnation | grep -i CURRENT | gawk '{print $2}'`
echo "Oracle database incarnation is $incar_num3"

}

function create_rman_restore_database_file {

echo "Create rman restore database file"
echo "RUN {" >> $restore_rmanfile

j=0
while [ $j -lt $parallel ]; do

   while IFS= read -r ip; do
    
      ip=`echo $ip | xargs`    	
      echo "Check whether IP $ip can be connected"
      if [[ -n $ip ]]; then
         return=`ping -c 2 $ip`

#           echo "return is $return"
         if echo $return | grep -q error; then
	    echo "error: IP $ip can't be connected. It may not be a valid IP. Skip this IP"
         else
	    echo "IP $ip can be connected"
	      	
            if [[ $j -lt $parallel ]]; then
	       allocate_database[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,gflag-name=sbt_use_grpc,gflag-value=true)';"
               unallocate[$j]="release channel c$j;"
            fi
            j=$[$j+1]
	 fi
      fi
   done < $vipfile
done


for (( i=0; i < ${#allocate_database[@]}; i++ )); do
   echo ${allocate_database[$i]} >> $restore_rmanfile
done

if [[ -n $ora_pfile ]]; then
  if test -f $ora_pfile; then
    grep -v "^#" < $ora_pfile | { while IFS= read -r para; do
       para=`echo $para | xargs`
       echo $para >> $restore_rmanfile
    done }
  else
    echo "$ora_pfile does not exist"
    exit 1
  fi
fi

if [[ -n $itime ]]; then
   echo "Oracle recovery point-in-time is define. Set recover time until $itime"
   echo "SET UNTIL TIME \"to_date('$itime', ''YYYY/MM/DD HH24:MI:SS')\";"
   echo "set until time \"to_date('$itime','YYYY/MM/DD HH24:MI:SS')\";" >> $restore_rmanfile
fi

if [[ -z $force ]]; then
   echo "restore database validate; " >> $restore_rmanfile
else
   echo "restore database;
   recover database;" >> $restore_rmanfile
fi


for (( i=0; i < ${#unallocate[@]}; i++ )); do
   echo ${unallocate[$i]} >> $restore_rmanfile
done

echo "
}
" >> $restore_rmanfile

if [[ $force != [Yy]* ]]; then
  echo "
  exit;
  " >> $restore_rmanfile
else
  if [[ $full = [Yy]* ]]; then
    echo "
    alter database open resetlogs;
    exit;
    " >> $restore_rmanfile
  else
    echo "
    alter database open;
    exit;
    " >> $restore_rmanfile 
  fi
fi

echo "finished creating rman restore database file"
}


function restore_controlfile {
	
echo "will restore controlfile"
echo "check whether the database is up"
runoid=`ps -ef | grep pmon | gawk 'NF>1{print $NF}' | grep -i $oraclesid | gawk -F "_" '{print $3}'`

if [[ ${runoid} != ${oraclesid} ]]; then
   echo "Oracle database $oraclesid is not up"
   echo "start the database in nomount, restore spfile, and restart the database in nomount"
   $rmanlogin << EOF
   startup nomount;
EOF

   echo "spfile restore started at " `/bin/date '+%Y%m%d%H%M%S'`

$rmanlogin log $spfile_rmanlog @$spfile_rmanfile

   $rmanlogin << EOF
   shutdown immediate;
   startup nomount
EOF
else
   echo "Oracle database $oraclesid is up"
   echo "shutdown the database first"
   echo "start the database in nomount, restore spfile, and restart the database in nomount"
   $rmanlogin << EOF
   shutdown immediate;
   startup nomount;
EOF
   $rmanlogin log $spfile_rmanlog @$spfile_rmanfile
   
   $rmanlogin << EOF
   shutdown immediate;
   startup nomount
EOF
fi

echo "The database should be up. If not, exit"
runoid=`ps -ef | grep pmon | gawk 'NF>1{print $NF}' | grep -i $oraclesid | gawk -F "_" '{print $3}'`
echo $runoid
if [[ ${runoid} != ${oraclesid} ]]; then
   echo "Oracle database $oraclesid is not up"
   exit 1 
fi

echo "restore controlfile $controlfile"
echo "shutdown the database and start it in mount mode"
$rmanlogin log $controlfile_rmanlog @$controlfile_rmanfile

if [ $? -ne 0 ]; then
  echo "   "
  echo "restore controlfile $controlfile failed at " `/bin/date '+%Y%m%d%H%M%S'`
  ls -l ${ORACLE_HOME}/dbs/spfile*
  echo "The last 10 line of rman log output"
  echo " "
  echo "rmanlog file is $controlfile_rmanlog"
  tail $controlfile_rmanlog
  exit 1
else
  echo "  "
  echo "restore controlfile finished at " `/bin/date '+%Y%m%d%H%M%S'`
fi

$rmanlogin << EOF
shutdown immediate
startup mount
EOF

echo "incarnation after new controlfile"
$rmanlogin log $incarnation << EOF
list incarnation of database;
exit;
EOF

incar_num1=`grep -i $dbname  $incarnation | grep -i CURRENT | gawk '{print $2}'`
echo "Oracle database incarnation is $incar_num1"

grep -i error $controlfile_rmanlog
  
if [ $? -eq 0 ]; then
   echo "Controlfile restore failed"
   exit 1
fi

}

function restore_database {

echo "Database restore started at " `/bin/date '+%Y%m%d%H%M%S'`
echo "ORACLE SID is $oraclesid"
runoid=`ps -ef | grep pmon | gawk 'NF>1{print $NF}' | grep -i $oraclesid | gawk -F "_" '{print $3}'`

if [[ ${runoid} != ${oraclesid} ]]; then
   echo "Oracle database $oraclesid is not up"
   echo "start the database in mount mode"
   $rmanlogin << EOF
   startup mount;
EOF
  $rmanlogin log $restore_rmanlog @$restore_rmanfile

   if [ $? -ne 0 ]; then
     echo "   "
     echo "Database restore failed at " `/bin/date '+%Y%m%d%H%M%S'`
     ls -l ${ORACLE_HOME}/dbs/spfile*
     echo "The last 10 line of rman log output"
     echo " "
     echo "rmanlog file is $restore_rmanlog"
     tail $restore_rmanlog
     exit 1
   else
     echo "  "
     echo "Database restore finished at " `/bin/date '+%Y%m%d%H%M%S'`
   fi
else
   echo "Oracle database $oraclesid is up running"
   if [[ $force = [Yy]* ]]; then
     if [[ $full != [Yy]* ]]; then
       read -p "should we start to do restore?" answer3
     else
       answer3=yes
     fi
   else
      answer3=yes
   fi

   if [[ $answer3 = [Yy]* ]]; then

     $rmanlogin log $restore_rmanlog @$restore_rmanfile

     if [ $? -ne 0 ]; then
       echo "   "
       echo "Database restore failed at " `/bin/date '+%Y%m%d%H%M%S'`
       ls -l ${ORACLE_HOME}/dbs/spfile*
       echo "The last 10 line of rman log output"
       echo " "
       echo "rmanlog file is $restore_rmanlog"
       tail $restore_rmanlog
       exit 1
     else
       echo "  "
       echo "Database restore finished at " `/bin/date '+%Y%m%d%H%M%S'`
     fi

   else
     echo "restore will not start at this point"
     exit 1
   fi
fi
}

setup

if [[ $preview = "yes" || $preview = "Yes" || $preview = "YES" ]]; then
   if [[ $full = [Yy]* ]]; then
      create_rman_restore_controlfile
      echo "   "
      echo ORACLE spfile restore RMAN SCRIPT 
      echo " "
      echo "---------------"
      cat $spfile_rmanfile
      echo " "
      echo ORACLE controlfile restore RMAN SCRIPT 
      echo "---------------"
      cat $controlfile_rmanfile
      echo "---------------"	  
   fi
   create_rman_restore_database_file
   echo "   "
   echo ORACLE restore RMAN SCRIPT 
   echo " "
   echo "---------------"
   cat $restore_rmanfile
   echo "---------------"
   exit
fi

if [[ $force != [Yy]* ]]; then
   create_rman_restore_database_file
   echo "run rman restore validate. It will NOT overwrite currect database" 
   echo " "
   restore_database
   echo "restore validate time is in rman log " $restore_rmanlog
   echo "check the start time and Finished restore time"
   exit
fi

if [[ $full = [Yy]* ]]; then
   echo "The following procedure will restore spfile, controlfiles, and datafiles"
   read -p "Have all original spfile, controlfile, and datafiles been removed? " answer2
   if [[ $answer2 = [Yy]* ]]; then
      create_rman_restore_controlfile
      restore_controlfile      
   else
      echo "need to delete the orignal spfile, controlfiles, and datafiles first"
      exit 1
   fi
fi
create_rman_restore_database_file
restore_database
echo "restore time is in rman log " $restore_rmanlog
echo "check the start time and Finished recover time"
