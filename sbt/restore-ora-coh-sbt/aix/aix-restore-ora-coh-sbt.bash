#!/bin/bash
#
# Name:         aix-restore-ora-coh-sbt.bash
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
# 03/13/21 Diana Yang   Add an option to use recovery catalog for restore
#
#################################################################

function show_usage {
echo "usage: aix-restore-ora-coh-sbt.bash -h <backup host> -i <Oracle instance name> -c <Catalog connection> -d <Oracle_DB_Name> -y <Cohesity-cluster> -b <file contain restore settting> -t <point-in-time> -l <yes/no> -j <vip file> -v <view> -s <sbt file name> -p <number of channels> -o <ORACLE_HOME> -f <yes/no> -w <yes/no>"
echo " "
echo " Required Parameters"
echo " -i : Oracle instance name. If it is not RAC, it is the same as DB name. If it is RAC, it is the instance name like cohcdba2"
echo " -d : Source Oracle_DB_Name, only required if it is RAC. It is DB name, not instance name"
echo " -y : Cohesity Cluster DNS name"
echo " -v : Cohesity view"
echo " -f : yes means force. It will restore Oracle database. Without it, it will just run RMAN validate (Optional)"
echo " "
echo " Optional Parameters"
echo " -h : Oracle database host that the backup was run. (default is current host), optional"
echo " -c : Catalog connection (example: \"<dbuser>/<dbpass>@<catalog connection string>\", optional)"
echo " -b : File contains restore location setting, example: set newname for database to '/oradata/restore/orcl/%b'; "
echo " -t : Point in Time (format example: \"2019-01-27 13:00:00\"), optional"
echo " -l : yes means complete restore including control file, no means not restoring controlfile"
echo " -p : number of channels (default is 4), optional"
echo " -j : The file lists Cohesity Cluster VIPs (default name is vip-list and default directory is config)"
echo " -s : Cohesity SBT library name including directoy or just directory (default name is libsbt_aix_powerpc.so, default directory is lib) "
echo " -o :  ORACLE_HOME (default is current environment), optional"
echo " -w : yes means preview rman backup scripts"
}

while getopts ":h:c:i:d:b:t:y:l:j:v:s:p:o:f:w:" opt; do
  case $opt in
    h ) host=$OPTARG;;
    c ) catalogc=$OPTARG;;
    i ) oraclesid=$OPTARG;;
    d ) dbname=$OPTARG;;
    b ) ora_pfile=$OPTARG;;
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

fullcommand=($@)
lencommand=${#fullcommand[@]}
#echo $lencommand
i=0
for (( i=0; i<$lencommand; i++ ))
do
   if [[ ${fullcommand[$i]} == -f ]]; then
      forceset=yes
   fi
done
if [[ -n $forceset ]]; then
   if [[ -z $force ]]; then
      echo "yes should be provided after -f in syntax, it may be empty or not all options are given an argument. All options should be given an arguments"
      exit 2
   else
      if [[ $force != [Yy]* ]]; then
         echo "yes should be provided rovided after -f in syntax, other answer is not valid"
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
      echo "yes should be provided after -w in syntax, it may be empty or not all options are given an argument. All options should be given an arguments"
      exit 2
   else
      if [[ $preview != [Yy]* ]]; then
         echo "yes should be provided after -w in syntax, other answer is not valid"
	 exit 2
      fi 
   fi
fi

i=0
for (( i=0; i<$lencommand; i++ ))
do
   if [[ ${fullcommand[$i]} == -l ]]; then
      fullset=yes
   fi
done
if [[ -n $fullset ]]; then
   if [[ -z $full ]]; then
      echo "yes should be provided after -l in syntax, it may be empty or not all options are given an argument. All options should be given an arguments"
      exit 2
   else
      if [[ $full != [Yy]* ]]; then
         echo "yes should be provided after -l in syntax, other answer is not valid"
	 exit 2
      fi
   fi 
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

if [[ -n $grpctype ]]; then
  if [[ $grpctype != [Yy]* && $grpctype != [Nn]* ]]; then
     echo "yes needs to be provided after -x in syntax, other answer is not valid"
     exit 2
  fi
fi

if [[ -n $itime ]]; then
  if [[ $itime == *\"* ]]; then
     echo "There should not be \ after -t in syntax. It should be -t \"date time\", example like \"2019-01-27 13:00:00\" "
     exit 2
  fi
fi

#if [[ -n $itime && $full != [Yy]* ]]; then
#  echo "Point in time restore requires restore controlfile The option -l should be yes"
#  exit 1
#fi

rmanlogin="rman target /"
echo "rman login command is $rmanlogin"

targetc="/"
sqllogin="sqlplus / as sysdba"

if test $oracle_home; then
#  echo *target*
  echo "ORACLE_HOME is $oracle_home"
  ORACLE_HOME=$oracle_home
  export ORACLE_HOME=$oracle_home
  export PATH=$PATH:$ORACLE_HOME/bin
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
  vipfile=${DIR}/config/${oraclesid}-vip-list
  echo "Cohesity Cluster name is $cohesityname. VIPS will be collected and stored in $vipfile"
  nslookup $cohesityname | grep -i address | tail -n +2 | /opt/freeware/bin/gawk '{print $2}' > $vipfile
  
  if [[ ! -s $vipfile ]]; then
     echo "Cohesity Cluster name $cohesityname provided here is not in DNS"
     exit 1
  fi
  
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

#check whether sbt library is in $DIR/lib
if [ ! -f $sbtname ]; then
#check whether sbt library is in /opt/cohesity/plugins/sbt/lib
   sbtname=/opt/cohesity/plugins/sbt/lib/libsbt_aix_powerpc.so
   if [ ! -f $sbtname ]; then
      echo "file $sbtname does not exist. exit"
      exit 1
   fi
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
  ptime=`/opt/freeware/bin/date -d "$itime" '+%Y%m%d%H%M%S'`
  echo "itime is $itime,  point-in-time restore time $ptime"
fi

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

echo "need to get the correct controlfile backup file, either the file name or mount points that has the controlfile"

while true; do
  read -p "Do you know the correct controlfile backup file name: choose yes or no. If no, choose the directory that has the controlfile next: " yn
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
    
	ls ${dbname^^}_c-*.ctl > /dev/null
	if [ $? -ne 0 ]; then
  	echo "the directory ${mount} provided is incorrect"
        exit 3
    fi
	
    for bfile in ${dbname^^}_c-*.ctl; do
      bitime=`ls -l $bfile | /opt/freeware/bin/gawk '{print $6 " " $7 " " $8}'`       
      btime=`/opt/freeware/bin/date -d "$bitime" '+%Y%m%d%H%M%S'`
#     echo file time $btime
#     echo ptime $ptime
      if [[ $ptime -lt $btime ]]; then
        controlfile=$bfile
		oribtime=${btime::${#btime}-2}
        break
      else 
        controlfile1=$bfile
		oribtime1=${btime::${#btime}-2}
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
     oribtime=$oribtime1
   fi
fi

echo "The controlfile is $controlfile"

# get DBID
dbid=`echo $controlfile | /opt/freeware/bin/gawk -F "-" '{print $2}'`
echo "dbid of this database is $dbid"


# Check Cohesity IP connection
i=1
while IFS= read -r ip; do
    
   ip=`echo $ip | xargs`    	
   echo "Check whether IP $ip can be connected"
   if [[ -n $ip ]]; then      
      break   
   else
      i=$[$i+1]
   fi 
done < $vipfile

echo "will create spfile rman backup script"
echo controlfile backup file is $controlfile
echo "
run {
set dbid $dbid;
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

function create_rman_restore_controlfile_catalog {

# find DBID

echo "need to get DBID"

read -p "Enter the DBID of this database: " dbid
  
# Check Cohesity IP connection
i=1
while IFS= read -r ip; do
    
   ip=`echo $ip | xargs`    	
   echo "Check whether IP $ip can be connected"
   if [[ -n $ip ]]; then      
      break   
   else
      i=$[$i+1]
   fi 
done < $vipfile

echo "will create spfile rman backup script"
echo "
run {
set dbid $dbid;
allocate CHANNEL c1 TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,gflag-name=sbt_use_grpc,gflag-value=true)';
restore spfile FROM AUTOBACKUP;
release CHANNEL c1;
}
" >> $spfile_rmanfile

echo "will create controlfile rman backup script"
echo "
run {
allocate CHANNEL c1 TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,gflag-name=sbt_use_grpc,gflag-value=true)';
restore CONTROLFILE FROM AUTOBACKUP;
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

j=0
while [ $j -lt $parallel ]; do

   while IFS= read -r ip; do
    
      ip=`echo $ip | xargs`    	      
      if [[ -n $ip ]]; then    
	  
         if [[ $j -lt $parallel ]]; then
            allocate_database[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,gflag-name=sbt_use_grpc,gflag-value=true)';"
            unallocate[$j]="release channel c$j;"
         fi
         j=$[$j+1]
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
   echo "SET UNTIL TIME \"to_date('$itime', 'YYYY/MM/DD HH24:MI:SS')\";"
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
    if [[ -n $itime ]]; then
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

   echo "spfile restore started at " `/opt/freeware/bin/date '+%Y%m%d%H%M%S'`

   if [[ -z $catalogc ]]; then
      rman log $spfile_rmanlog << EOF
      connect target '${targetc}'
      @$spfile_rmanfile
EOF
   else
      rman log $spfile_rmanlog << EOF
      connect target '${targetc}'
      connect catalog '${catalogc}'
      @$spfile_rmanfile
EOF
   fi

   $sqllogin << EOF
   shutdown abort;
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

   if [[ -z $catalogc ]]; then
      rman log $spfile_rmanlog << EOF
      connect target '${targetc}'
      @$spfile_rmanfile
EOF
   else
      rman log $spfile_rmanlog << EOF
      connect target '${targetc}'
      connect catalog '${catalogc}'
      @$spfile_rmanfile
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
   @$controlfile_rmanfile
EOF
else
   rman log $controlfile_rmanlog << EOF
   connect target '${targetc}'
   connect catalog '${catalogc}'
   @$controlfile_rmanfile
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

echo "Database restore validate started at " `/bin/date '+%Y%m%d%H%M%S'`
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
    echo "Database restore validate failed at " `/bin/date '+%Y%m%d%H%M%S'`
    ls -l ${ORACLE_HOME}/dbs/spfile*
	echo "The last 10 line of rman log output"
    echo " "
    echo "rmanlog file is $restore_rmanlog"
    tail $restore_rmanlog
    exit 1
else
    echo "  "
    echo "Database restore validate finished at " `/bin/date '+%Y%m%d%H%M%S'`
fi

}

function restore_database {

echo "Database restore started at " `/bin/date '+%Y%m%d%H%M%S'`
echo "ORACLE SID is $oraclesid"
runoid=`ps -ef | grep pmon | /opt/freeware/bin/gawk 'NF>1{print $NF}' | grep -i $oraclesid | /opt/freeware/bin/gawk -F "_" '{print $3}'`

if [[ ${runoid} != ${oraclesid} ]]; then
   echo "Oracle database $oraclesid is not up"
   echo "start the database in mount mode"
   $sqllogin << EOF
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
      if [[ -n $catalogc ]]; then
         create_rman_restore_controlfile_catalog
      else
         create_rman_restore_controlfile_nocatalog
      fi
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
   restore_database_validate
   echo "restore validate time is in rman log " $restore_rmanlog
   echo "check the start time and Finished restore time"
   exit
fi

if [[ $full = [Yy]* ]]; then
   echo "The following procedure will restore spfile, controlfiles, and datafiles"
   read -p "Have all original spfile, controlfile, and datafiles been removed? " answer2
   if [[ $answer2 = [Yy]* ]]; then
      if [[ -n $catalogc ]]; then
         create_rman_restore_controlfile_catalog
      else
         create_rman_restore_controlfile_nocatalog
      fi 
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

# set the controlfile time backup to the original time
if [[ -n $oribtime ]]; then
  cd ${mount}
  touch -a -m -t $oribtime $controlfile
  cd ${DIR}
fi
