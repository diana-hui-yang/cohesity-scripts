#!/bin/bash
#
# Name:         restore-ora-coh-oim.bash
#
# Function:     This script restore Oracle database from Oracle backup 
#               using incremental merge backup script backup-ora-coh-oim.bash.
#
#
# Show Usage: run the command to show the usage
#
# Changes:
# 07/25/2020 Diana Yang   New script (restore using target database)
# 08/06/2020 Diana Yang   Add controlfile restore
#
#################################################################

function show_usage {
echo "usage: restore-ora-coh-oim.bash -r <RMAN login> -h <backup host> -i <Oracle instance name> -d <Oracle_DB_Name> -c <file contain restore settting> -t <point-in-time> -l <yes/no> -m <mount-prefix> -n <number of mounts> -p <number of channels> -o <ORACLE_HOME> -f <yes/no> -g <yes/no> -w <yes/no>"
echo " -r : RMAN login (example: \"rman target / \", optional)"
echo " -h : backup host" 
echo " -i : Oracle instance name. If it is not RAC, it is the same as DB name. If it is RAC, it is the instance name like cohcdba2"
echo " -d : Oracle database name. only required for RAC. If it is RAC, it is the database name like cohcdba"
echo " -c : File contains restore location setting, example: set newname for database to '/oradata/restore/orcl/%b'; "
echo " -t : Point in Time (format example: "2019-01-27 13:00:00"), optional"
echo " -l : yes means complete restore including control file, no means not restoring controlfile"
echo " -m : mount-prefix (like /coh/ora)"
echo " -n : number of mounts"
echo " -p : number of channels (Optional, default is same as the number of mounts4)"
echo " -o : ORACLE_HOME (Optional, default is current environment)"
echo " -f : yes means force. It will restore Oracle database. Without it, it will just run RMAN validate (Optional)"
echo " -g : yes means this script will catalog archivelogs before recovery"
echo " -w : yes means preview rman backup scripts"
}

while getopts ":r:h:i:d:c:t:l:m:n:p:o:f:g:w:" opt; do
  case $opt in
    r ) rmanlogin=$OPTARG;;
    h ) bhost=$OPTARG;;
    i ) oraclesid=$OPTARG;;
    d ) dbname=$OPTARG;;
    c ) ora_pfile=$OPTARG;;
    t ) itime=$OPTARG;;
    l ) full=$OPTARG;;
    m ) mount=$OPTARG;;
    n ) num=$OPTARG;;
    p ) parallel=$OPTARG;;
    o ) oracle_home=$OPTARG;;
    f ) force=$OPTARG;;
    g ) catarc=$OPTARG;;
    w ) preview=$OPTARG;;
  esac
done

echo $rmanlogin $oraclesid, $mount, $bhost, $num

# Check required parameters
#if test $bhost && test $dbname && test $mount && test $numm
if test $bhost && test $oraclesid && test $mount && test $num
then
  :
else
  show_usage 
  exit 1
fi


function setup {
host=`hostname -s`

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
  echo "no input for parallel, set parallel to be $num."
  parallel=$num
fi

echo $rmanlogin
if [[ -z $rmanlogin ]]; then
  rmanlogin="rman target /"
  echo "rman login command is $rmanlogin"
else 
  if [[ $rmanlogin = *target* ]]; then
#  echo *target*
    echo "rman login command is $rmanlogin"
  else
    echo "rmanlogin syntax should be \"rman target / \" or \"rman target / catalog <user>/<pass>@<recover catalog>"
    exit 1
  fi
fi

if test $oracle_home; then
#  echo *target*
  echo "ORACLE_HOME is $oracle_home"
  ORACLE_HOME=$oracle_home
  if [[ `ls $ORACLE_HOME/bin/rman` ]]; then
    export ORACLE_HOME=$oracle_home
    export PATH=$PATH:$ORACLE_HOME/bin
  else
    echo "ORACLE_HOME \"$ORACLE_HOME\" provided in input is incorrect"
    exit 1
  fi
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


if [[ ! -d $DIR/log/$host ]]; then
  echo " $DIR/log/$host does not exist, create it"
  mkdir -p $DIR/log/$host
  
  if [ $? -ne 0 ]; then
    echo "create log directory $DIR/log/$host failed. There is a permission issue"
    exit 1
  fi
fi

if [[ ! -d "${mount}1/$bhost/$dbname/datafile" ]]; then
   echo "Directory ${mount}1/$bhost/$dbname/datafile does not exist, no backup files"
   exit 1
fi

restore_rmanlog=$DIR/log/$host/$dbname.rman-restore.$DATE_SUFFIX.log
restore_rmanfile=$DIR/log/$host/$dbname.rman-restore.$DATE_SUFFIX.rcv
recover_rmanlog=$DIR/log/$host/$dbname.rman-recover.$DATE_SUFFIX.log
recover_rmanfile=$DIR/log/$host/$dbname.rman-recover.$DATE_SUFFIX.rcv
catalog_bash=$DIR/log/$host/${dbname}.catalog-archivelogs.$DATE_SUFFIX.bash
catalog_log=$DIR/log/$host/${dbname}.catalog-archivelogs.$DATE_SUFFIX.log
incarnation=$DIR/log/$host/$dbname.incar_list

# setup restore location
# get restore location from $ora_pfile
if [[ ! -z $ora_pfile ]]; then
   echo "ora_pfile is $ora_pfile"
   db_location=`grep -i newname $ora_pfile | awk -F "'" '{print $2}' | awk -F "%" '{print $1}'`
# remove all space in $db_location
   db_location=`echo $db_location | xargs echo -n`
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

# find the right controlfile backup
if [[ ! -d "${mount}1/$bhost/$dbname/controlfile" ]]; then
   echo "Directory ${mount}1/$bhost/$dbname/controlfile does not exist, no controlfiles backup"
   exit 1
fi
cd ${mount}1/$bhost/$dbname/controlfile

echo "get point-in-time controlfile"

for bfile in *c-*.ctl; do
   bitime=`ls -l $bfile | awk '{print $6 " " $7 " " $8}'`
   btime=`/bin/date -d "$bitime" '+%Y%m%d%H%M%S'`
#     echo file time $btime
#     echo ptime $ptime
   if [[ $ptime -lt $btime ]]; then
     controlfile=${mount}1/$bhost/$dbname/controlfile/$bfile
     break
   else
     controlfile1=${mount}1/$bhost/$dbname/controlfile/$bfile
   fi
done

if [[ -z $controlfile ]]; then
   if [[ -z $controlfile1 ]]; then
     echo "The cnntrolfile for database $dbname at $ptime is not found"
     exit 1
   else
     controlfile=$controlfile1
   fi
fi

echo "The controlfile is $controlfile"
	
#echo ${mount}1/$bhost/$dbname/datafile

#echo $bhost  $mount $num

#trim log directory
find $DIR/log/$host -type f -mtime +7 -exec /bin/rm {} \;

if [ $? -ne 0 ]; then
  echo "del old logs in $DIR/log/$host failed"
  exit 2
fi

export ORACLE_SID=$oraclesid
}

function restore_controlfile {

echo "will restore controlfile"
echo "check whether the database is up"
runoid=`ps -ef | grep pmon | awk 'NF>1{print $NF}' | grep -i $oraclesid | awk -F "_" '{print $3}'`

if [[ ${runoid} != ${oraclesid} ]]; then
   echo "Oracle database $oraclesid is not up"
   echo "start the database in nomount, restore spfile, and restart the database in nomount"
echo controlfile is $controlfile
   $rmanlogin << EOF
   startup nomount;
   restore spfile from '$controlfile';
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
   restore spfile from '$controlfile';
   shutdown immediate;
   startup nomount
EOF
fi

echo "The database should be up. If not, exit"
runoid=`ps -ef | grep pmon | awk 'NF>1{print $NF}' | grep -i $oraclesid | awk -F "_" '{print $3}'`
echo $runoid
if [[ ${runoid} != ${oraclesid} ]]; then
   echo "Oracle database $oraclesid is not up"
   exit 1 
fi

echo "restore controlfile $controlfile"
echo "shutdown the database and start it in mount mode"
$rmanlogin << EOF
run {
    RESTORE CONTROLFILE FROM '$controlfile';
} 
shutdown immediate
startup mount
EOF

echo "incarnation after new controlfile"
$rmanlogin log $incarnation << EOF
list incarnation of database;
exit;
EOF

incar_num1=`grep -i $dbname  $incarnation | grep -i CURRENT | awk '{print $2}'`
echo "Oracle database incarnation is $incar_num1"

}

function reset_incarnation_afterrestore {

echo "incarnation after restore"
$rmanlogin log $incarnation << EOF
list incarnation of database;
exit;
EOF

incar_num2=`grep -i $dbname  $incarnation | grep -i CURRENT | awk '{print $2}'`
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

incar_num3=`grep -i $dbname  $incarnation | grep -i CURRENT | awk '{print $2}'`
echo "Oracle database incarnation is $incar_num3"

}

function catalog_archivelogs {

#create a bash script that will catalog the baskup files created by Cohesity snapshot
echo "
#!/bin/bash

echo Catalog the archivelogs started at  \`/bin/date '+%Y%m%d%H%M%S'\`
export ORACLE_HOME=$oracle_home
export PATH=$PATH
export NLS_DATE_FORMAT='DD:MM:YYYY-HH24:MI:SS'
export ORACLE_SID=$oraclesid
$rmanlogin log $catalog_log << EOF
" > $catalog_bash
#cd ${mount}1/$bhost/$dbname/datafile.$DATE_SUFFIX
cd ${mount}1/$bhost/$dbname/archivelog
	 
num_arcfile=`ls *.blf | wc -l`
echo $num_arcfile
arcfile=(`ls *.blf`)
i=1
j=0
while [ $i -le $num ]; do
  	
  if [[ $j -lt $num_arcfile ]]; then
	 echo "CATALOG backuppiece '${mount}${i}/$bhost/$dbname/archivelog/${arcfile[$j]}';" >> $catalog_bash
  fi

  i=$[$i+1]
  j=$[$j+1]


  if [[ $i -gt $num && $j -le $num_arcfile ]]; then 
     i=1
  fi
  
done

echo "
exit;
EOF


if [[ ! -z \`grep -i error" $catalog_log"\` ]]; then
  echo catalog the archivelogs failed at  \`/bin/date '+%Y%m%d%H%M%S'\`
  exit 1
else
  echo Catalog the archivelogs finished at   \`/bin/date '+%Y%m%d%H%M%S'\`
fi
" >> $catalog_bash
    
chmod 750 $catalog_bash

}


function create_rman_restore_database_file {

echo "Create rman restore database file"
echo "RUN {" >> $restore_rmanfile

i=1
j=0
while [ $i -le $num ]; do

  mountstatus=`mount | grep -i  "${mount}${i}"`
  if [[ -n $mountstatus ]]; then
    echo "
        $mount${i} is mount point
    "

    if [[ $j -lt $parallel ]]; then
      allocate_database[$j]="allocate channel fs$j device type disk format = '$mount$i/$bhost/$dbname/datafile/%d_%T_%U';"
      unallocate[j]="release channel fs$j;"
    fi

    i=$[$i+1]
    j=$[$j+1]


    if [[ $i -gt $num && $j -le $parallel ]]; then 
      i=1
    fi
  else
    echo "$mount${i} is not a mount point. Restore will not start
    The mount prefix may not be correct or
    The input of the number of mount points may exceed the actuall number of mount points"
    exit 1
  fi
done

for (( i=0; i < ${#allocate_database[@]}; i++ )); do
   echo ${allocate_database[$i]} >> $restore_rmanfile
done

if [[ -n $ora_pfile ]]; then
  if test -f $ora_pfile; then
    grep -v "^#" < $ora_pfile | { while IFS= read -r para; do
       para=`echo $para | xargs echo -n`
       echo $para >> $restore_rmanfile
    done }
  else
    echo "$ora_pfile does not exist"
    exit 1
  fi
fi



if [[ ! -z $itime ]]; then
   echo "Oracle recovery point-in-time is define. Set recover time until $itime"
   echo "SET UNTIL TIME \"to_date('$itime', ''YYYY/MM/DD HH24:MI:SS')\";"
   echo "set until time \"to_date('$itime','YYYY/MM/DD HH24:MI:SS')\";" >> $restore_rmanfile
fi

if [[ -z $force ]]; then
   echo "restore database validate;" >> $restore_rmanfile
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

function restore_database {

echo "Database restore started at " `/bin/date '+%Y%m%d%H%M%S'`
echo "ORACLE SID is $oraclesid"
runoid=`ps -ef | grep pmon | awk 'NF>1{print $NF}' | grep -i $oraclesid | awk -F "_" '{print $3}'`

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
       read -p "should we start to do restore? " answer3
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
  
   create_rman_restore_database_file
   echo "   "
   echo ORACLE restore RMAN SCRIPT 
   echo " "
   echo "---------------"
   cat $restore_rmanfile
   echo "---------------"
   echo " "
   echo ORACLE restore RMAN SCRIPT 
   echo " "
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

