#!/bin/bash
#
# Name:         aix-restore-ora-coh-nfs.bash
#
# Function:     This script restore Oracle database from Oracle backup 
#               using incremental merge backup script backup-ora-coh-nfs.bash or backup-ora-coh-oim.bash.
# Warning:      Restore can overwrite the existing database. This script needs to be used in caution.
#               The author accepts no liability for damages resulting from its use.
#
#
# Show Usage: run the command to show the usage
#
# Changes:
# 07/25/20 Diana Yang   New script (restore using target database)
# 08/06/20 Diana Yang   Add controlfile restore
# 05/19/21 Diana Yang   Add set newname during restore
# 05/19/21 Diana Yang   Add an option to use recovery catalog for restore
# 12/08/21 Diana Yang   Add an option to automatically restore the database on other server in DR situation
# 12/08/21 Diana Yang   Add support when the source server and target server are in different time zone
# 12/08/21 Diana Yang   Change gawk to /opt/freeware/bin/gawk, date to /opt/freeware/bin/date
#
#################################################################

function show_usage {
echo "usage: aix-restore-ora-coh-nfs.bash -h <backup host> -c <Catalog connection> -i <Oracle instance name> -d <Oracle_DB_Name> -b <file contain restore settting> -t <point-in-time> -l <yes/no> -m <mount-prefix> -n <number of mounts> -p <number of channels> -o <ORACLE_HOME> -f <yes/no> -w <yes/no>"
echo " "
echo " Required Parameters"
echo " -i : Oracle instance name. If it is not RAC, it is the same as DB name. If it is RAC, it is the instance name like cohcdba2"
echo " -d : Oracle database name. only required for RAC. If it is RAC, it is the database name like cohcdba"
echo " -m : mount-prefix (like /coh/ora)"
echo " -n : number of mounts"
echo " -f : yes means force. It will restore Oracle database. Without it, it will just run RMAN validate (Optional)"
echo " "
echo " Optional Parameters"
echo " -h : Oracle database host that the backup was run."
echo " -c : Catalog connection (example: \"<dbuser>/<dbpass>@<catalog connection string>\", optional)"
echo " -b : File contains restore location setting, example: set newname for database to '/oradata/restore/orcl/%b'; "
echo " -t : Point in Time (format example: "2019-01-27 13:00:00"), the time should be based on source server timezone, optional"
echo " -l : yes means complete restore including control file, no means not restoring controlfile"
echo " -p : number of channels (Optional, default is same as the number of mounts4)"
echo " -o : ORACLE_HOME (Optional, default is current environment)"
echo " -w : yes means preview rman backup scripts"
}

while getopts ":h:c:i:d:b:t:l:m:n:p:o:f:w:" opt; do
  case $opt in
    h ) shost=$OPTARG;;
    c ) catalogc=$OPTARG;;
    i ) oraclesid=$OPTARG;;
    d ) dbname=$OPTARG;;
    b ) ora_pfile=$OPTARG;;
    t ) itime=$OPTARG;;
    l ) full=$OPTARG;;
    m ) mount=$OPTARG;;
    n ) num=$OPTARG;;
    p ) parallel=$OPTARG;;
    o ) oracle_home=$OPTARG;;
    f ) force=$OPTARG;;
    w ) preview=$OPTARG;;
  esac
done

echo $oraclesid, $mount, $shost, $num

# Check required parameters
#if test $shost && test $dbname && test $mount && test $numm
if test $oraclesid && test $mount && test $num
then
  :
else
  show_usage 
  exit 1
fi


function setup {
host=`hostname -s`
if test $shost
then
  :
else
  shost=$host
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
  echo "no input for parallel, set parallel to be $num."
  parallel=4
fi

if [[ -n $force ]]; then
  if [[ $force != [Yy]* ]]; then
     echo "yes needs to be provided after -f in syntax, other answer is not valid"
	 exit 2
  fi
fi

if [[ -n $full ]]; then
  if [[ $full != [Yy]* ]]; then
     echo "yes needs to be provided after -l in syntax, other answer is not valid"
	 exit 2
  fi
fi

if [[ -n $preview ]]; then
  if [[ $preview != [Yy]* ]]; then
     echo "yes needs to be provided after -w in syntax, other answer is not valid"
	 exit 2
  fi
fi

if [[ -n $itime ]]; then
  if [[ $itime == *\"* ]]; then
     echo "There should not be \ after -t in syntax. It should be -t \"date time\", example like \"2019-01-27 13:00:00\" "
	 exit 2
  fi
fi

rmanlogin="rman target /"
echo "rman login command is $rmanlogin"

targetc="/"
sqllogin="sqlplus / as sysdba"

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
  oracle_home=`env | grep ORACLE_HOME | /opt/freeware/bin/gawk -F "=" '{print $2}'`
  if [[ -z $oracle_home ]]; then
     echo " is not defined. Need to specify ORACLE_HOME"
     exit 1
  fi   
fi
export NLS_DATE_FORMAT='DD:MM:YYYY-HH24:MI:SS'

if [[ -n $ora_pfile ]]; then
   if [[ ! -f $ora_pfile ]]; then
      echo "there is no $ora_pfile. It is file defined by -l plugin"
      exit 1
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


if [[ ! -d $DIR/log/$host ]]; then
  echo " $DIR/log/$host does not exist, create it"
  mkdir -p $DIR/log/$host
  
  if [ $? -ne 0 ]; then
    echo "create log directory $DIR/log/$host failed. There is a permission issue"
    exit 1
  fi
fi

if [[ ! -d "${mount}1/$shost/$dbname/controlfile" ]]; then
   echo "Directory ${mount}1/$shost/$dbname/controlfile does not exist, no backup files"
   echo "If this server is different from the backup server, the backup server needs to be provided using -h option"
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
   db_location=`grep -i newname $ora_pfile | /opt/freeware/bin/gawk -F "'" '{print $2}' | /opt/freeware/bin/gawk -F "%" '{print $1}'`
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

if [[ $host != $shost ]]; then
# find source server timezone difference from UTC time
   if [[ -f ${mount}1/$shost/$dbname/spfile/timezoneoffset-file ]]; then
      stimezoneoffset=`cat ${mount}1/$shost/$dbname/spfile/timezoneoffset-file`
   else
      echo "Cannot find the file timezoneoffset-file, may need to download the latest backup script"
      ((stimezoneoffset=0))
   fi

# find current server timezone difference from UTC time
  ((ttimezoneoffset=`/opt/freeware/bin/date -u '+%Y%m%d%H%M%S'`-`/opt/freeware/bin/date '+%Y%m%d%H%M%S'`))
else
  ((ttimezoneoffset=0))
  ((stimezoneoffset=0))
fi

# covert the time to numeric
if [[ -z $itime ]]; then
  ((ptime=`/opt/freeware/bin/date '+%Y%m%d%H%M%S'`+$ttimezoneoffset-$stimezoneoffset))
  echo "current time is `/opt/freeware/bin/date`,  point-in-time restore time $ptime"
else   
  ptime=`/opt/freeware/bin/date -d "$itime" '+%Y%m%d%H%M%S'`
  echo "itime is $itime,  point-in-time restore time $ptime"
fi

#echo ${mount}1/$shost/$dbname/archivelog

#echo $shost  $mount $num

#trim log directory
find $DIR/log/$host -type f -mtime +7 -exec /bin/rm {} \;

if [ $? -ne 0 ]; then
  echo "del old logs in $DIR/log/$host failed"
  exit 2
fi

# test catalog connection
if [[ -n $catalogc ]]; then
   echo "catalog connection is $catalogc"
   catar=`rman << EOF
   connect catalog '${catalogc}'
   exit;
EOF`

   echo $catar | grep -i connected
   
   if [ $? -ne 0 ]; then
      echo "rman connection using $catalogc is incorrect
           "
      echo $catar
      echo "
           catalogc syntax can be like \"/\" or
          \"<catalog dd user>/<password>@<catalog database connect string>\""
      exit 1
   else
      echo "rman catalog connect is successful. Continue"
   fi
fi	  


export ORACLE_SID=$oraclesid
}

function create_rman_restore_controlfile_nocatalog {

# find the right controlfile backup
if [[ ! -d "${mount}1/$shost/$dbname/controlfile" ]]; then
   echo "Directory ${mount}1/$shost/$dbname/controlfile does not exist, no controlfiles backup"
   exit 1
fi
cd ${mount}1/$shost/$dbname/controlfile

echo "get point-in-time controlfile"

for bfile in ${dbname^^}_c-*.ctl; do
   bitime=`ls -l $bfile | /opt/freeware/bin/gawk '{print $6 " " $7 " " $8}'`
   if [ $? -ne 0 ]; then
  	  echo "the directory ${mount} provided is incorrect"
      exit 3
   fi
   ((btime=`/opt/freeware/bin/date -d "$bitime" '+%Y%m%d%H%M%S'`+$ttimezoneoffset-$stimezoneoffset))
#     echo file time $btime
#     echo ptime $ptime
   if [[ $ptime -lt $btime ]]; then
     controlfile=${mount}1/$shost/$dbname/controlfile/$bfile
	 oribtime=${btime::${#btime}-2}
     break
   else
     controlfile1=${mount}1/$shost/$dbname/controlfile/$bfile
	 oribtime1=${btime::${#btime}-2}
   fi
done
cd ${DIR}

if [[ -z $controlfile ]]; then
   if [[ -z $controlfile1 ]]; then
     echo "The cnntrolfile for database $dbname at $ptime is not found"
     exit 1
   else
     controlfile=$controlfile1
	 oribtime=$oribtime1
   fi
fi

echo "The controlfile is $controlfile"

# get DBID
dbid=`echo $controlfile | /opt/freeware/bin/gawk -F "-" '{print $2}'`
echo "dbid of this database is $dbid"
}

function create_rman_restore_controlfile_catalog {

# find DBID

echo "need to get DBID"

read -p "Enter the DBID of this database: " dbid

}


function reset_incarnation_afterrestore {

echo "incarnation after restore"
$rmanlogin log $incarnation << EOF
list incarnation of database;
exit;
EOF

incar_num2=`grep -i $dbname  $incarnation | grep -i CURRENT | /opt/freeware/bin/gawk '{print $2}'`
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

incar_num3=`grep -i $dbname  $incarnation | grep -i CURRENT | /opt/freeware/bin/gawk '{print $2}'`
echo "Oracle database incarnation is $incar_num3"

}

function create_rman_restore_database_file {

echo "Create rman restore database file"
echo "RUN {" >> $restore_rmanfile

i=1
j=0
while [ $i -le $num ]; do

  mountstatus=`mount | grep -i  "${mount}${i}"`
  if [[ -n $mountstatus ]]; then

#    echo "
#        $mount${i} is mount point
#    "

    if [[ $j -lt $parallel ]]; then
      allocate_database[$j]="allocate channel fs$j device type disk;"
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


function restore_controlfile {

echo "will restore controlfile"
echo "check whether the database is up"
runoid=`ps -ef | grep pmon | /opt/freeware/bin/gawk 'NF>1{print $NF}' | grep -i $oraclesid | /opt/freeware/bin/gawk -F "_" '{print $3}'`

if [[ ${runoid} != ${oraclesid} ]]; then
   echo "Oracle database $oraclesid is not up"
   echo "start the database in nomount, restore spfile, and restart the database in nomount"
   $sqllogin << EOF
   startup nomount;
EOF
   echo controlfile is $controlfile
   echo "spfile restore started at " `/opt/freeware/bin/date '+%Y%m%d%H%M%S'`
   if [[ -z $catalogc ]]; then
      rman log $spfile_rmanlog << EOF
      connect target '${targetc}'
      set dbid $dbid;
      restore spfile from '$controlfile';
EOF
   else
      rman log $spfile_rmanlog << EOF
      connect target '${targetc}'
      connect catalog '${catalogc}'
      set dbid $dbid;
      restore spfile FROM AUTOBACKUP;
EOF
   fi
   
   $sqllogin << EOF
   shutdown immediate;
   startup nomount
EOF
else
   echo "Oracle database $oraclesid is up"
   echo "shutdown the database first"
   echo "start the database in nomount, restore spfile, and restart the database in nomount"
   $sqllogin << EOF
   shutdown immediate;
   startup nomount;
EOF
   echo controlfile is $controlfile
   echo "spfile restore started at " `/opt/freeware/bin/date '+%Y%m%d%H%M%S'`
   if [[ -z $catalogc ]]; then
      rman log $spfile_rmanlog << EOF
      connect target '${targetc}'
      set dbid $dbid;
      restore spfile from '$controlfile';
EOF
   else
      rman log $spfile_rmanlog << EOF
      connect target '${targetc}'
      connect catalog '${catalogc}'
      set dbid $dbid;
      restore spfile FROM AUTOBACKUP;;
EOF
   fi
   
   $sqllogin << EOF
   shutdown immediate;
   startup nomount
EOF
fi

echo "The database should be up. If not, exit"
runoid=`ps -ef | grep pmon | /opt/freeware/bin/gawk 'NF>1{print $NF}' | grep -i $oraclesid | /opt/freeware/bin/gawk -F "_" '{print $3}'`
echo $runoid
if [[ ${runoid} != ${oraclesid} ]]; then
   echo "Oracle database $oraclesid is not up"
   exit 1 
fi

echo "restore controlfile $controlfile"
echo "shutdown the database and start it in mount mode"

if [[ -z $catalogc ]]; then
   rman log $controlfile_rmanlog << EOF
   connect target '${targetc}'
   RESTORE CONTROLFILE FROM '$controlfile';
EOF
else
   rman log $controlfile_rmanlog << EOF
   connect target '${targetc}'
   connect catalog '${catalogc}'
   RESTORE CONTROLFILE FROM AUTOBACKUP;;
EOF
fi

if [ $? -ne 0 ]; then
  echo "   "
  echo "restore controlfile $controlfile failed at " `/opt/freeware/bin/date '+%Y%m%d%H%M%S'`
  ls -l ${ORACLE_HOME}/dbs/spfile*
  echo "The last 10 line of rman log output"
  echo " "
  echo "rmanlog file is $controlfile_rmanlog"
  tail $controlfile_rmanlog
  exit 1
else
  echo "  "
  echo "restore controlfile finished at " `/opt/freeware/bin/date '+%Y%m%d%H%M%S'`
fi

$sqllogin << EOF 
shutdown immediate
startup mount
EOF

echo "incarnation after new controlfile"
$rmanlogin log $incarnation << EOF
list incarnation of database;
exit;
EOF

incar_num1=`grep -i $dbname  $incarnation | grep -i CURRENT | /opt/freeware/bin/gawk '{print $2}'`
echo "Oracle database incarnation is $incar_num1"

grep -i error $controlfile_rmanlog
  
if [ $? -eq 0 ]; then
   echo "Controlfile restore failed"
   exit 1
fi

}

function restore_database_validate {

echo "Database restore started at " `/opt/freeware/bin/date '+%Y%m%d%H%M%S'`
echo "ORACLE SID is $oraclesid"


if [[ -z $catalogc ]]; then
    rman log $restore_rmanlog << EOF
    connect target '${targetc}'
    @$restore_rmanfile
EOF
else
    rman log $restore_rmanlog << EOF
    connect target '${targetc}'
    connect catalog '${catalogc}'
    @$restore_rmanfile
EOF
fi

if [ $? -ne 0 ]; then
    echo "   "
    echo "Database restore validate failed at " `/opt/freeware/bin/date '+%Y%m%d%H%M%S'`
    ls -l ${ORACLE_HOME}/dbs/spfile*
	echo "The last 10 line of rman log output"
    echo " "
    echo "rmanlog file is $restore_rmanlog"
    tail $restore_rmanlog
    exit 1
else
    echo "  "
    echo "Database restore validate finished at " `/opt/freeware/bin/date '+%Y%m%d%H%M%S'`
fi

}


function restore_database {

echo "Database restore started at " `/opt/freeware/bin/date '+%Y%m%d%H%M%S'`
echo "ORACLE SID is $oraclesid"
runoid=`ps -ef | grep pmon | /opt/freeware/bin/gawk 'NF>1{print $NF}' | grep -i $oraclesid | /opt/freeware/bin/gawk -F "_" '{print $3}'`

if [[ ${runoid} != ${oraclesid} ]]; then
   echo "Oracle database $oraclesid is not up"
   echo "start the database in mount mode"
   $rmanlogin << EOF
   startup mount;
EOF

   if [[ -z $catalogc ]]; then
      rman log $restore_rmanlog << EOF
      connect target '${targetc}'
      @$restore_rmanfile
EOF
   else
      rman log $restore_rmanlog << EOF
      connect target '${targetc}'
      connect catalog '${catalogc}'
      @$restore_rmanfile
EOF
   fi

   if [ $? -ne 0 ]; then
     echo "   "
     echo "Database restore failed at " `/opt/freeware/bin/date '+%Y%m%d%H%M%S'`
     ls -l ${ORACLE_HOME}/dbs/spfile*
     echo "The last 10 line of rman log output"
     echo " "
     echo "rmanlog file is $restore_rmanlog"
     tail $restore_rmanlog
     exit 1
   else
     echo "  "
     echo "Database restore finished at " `/opt/freeware/bin/date '+%Y%m%d%H%M%S'`
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

     $sqllogin << EOF
     shutdown immediate;
     startup mount
EOF
     if [[ -z $catalogc ]]; then
        rman log $restore_rmanlog << EOF
        connect target '${targetc}'
        @$restore_rmanfile
EOF
     else
        rman log $restore_rmanlog << EOF
        connect target '${targetc}'
        connect catalog '${catalogc}'
        @$restore_rmanfile
EOF
     fi

     if [ $? -ne 0 ]; then
       echo "   "
       echo "Database restore failed at " `/opt/freeware/bin/date '+%Y%m%d%H%M%S'`
       ls -l ${ORACLE_HOME}/dbs/spfile*
       echo "The last 10 line of rman log output"
       echo " "
       echo "rmanlog file is $restore_rmanlog"
       tail $restore_rmanlog
       exit 1
     else
       echo "  "
       echo "Database restore finished at " `/opt/freeware/bin/date '+%Y%m%d%H%M%S'`
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
   restore_database_validate
   echo "restore validate time is in rman log " $restore_rmanlog
   echo "check the start time and Finished restore time"
   exit
fi

if [[ $full = [Yy]* ]]; then
   echo "The following procedure will restore spfile, controlfiles, and datafiles"
   if [[ $host == $shost ]]; then
      read -p "Have all original spfile, controlfile, and datafiles been removed? " answer2
      if [[ $answer2 = [Yy]* ]]; then
         if [[ -z $catalogc ]]; then      
            create_rman_restore_controlfile_nocatalog
         fi
         restore_controlfile      
      else
         echo "need to delete the orignal spfile, controlfiles, and datafiles first"
         exit 1
      fi
   else
      echo "This server is not production server."
      if [[ -z $catalogc ]]; then      
         create_rman_restore_controlfile_nocatalog
      fi
      restore_controlfile
   fi	  
fi
create_rman_restore_database_file
restore_database
echo "restore time is in rman log " $restore_rmanlog
echo "check the start time and Finished recover time"

# set the controlfile time backup to the original time
if [[ -n $oribtime ]]; then
  touch -a -m -t $oribtime $controlfile
fi
