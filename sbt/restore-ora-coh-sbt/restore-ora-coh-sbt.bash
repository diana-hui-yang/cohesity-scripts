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
# 07/25/2020 Diana Yang   New script (restore to target database)
# 07/31/2020 Diana Yang   Add controlfile restore
# 08/06/2020 Diana Yang   Rename this file from restore-ora-coh-dedup.bash to restore-ora-coh-sbt.bash
#
#################################################################

function show_usage {
echo "usage: restore-ora-coh-sbt.bash -r <RMAN login> -h <backup host> -i <Oracle instance name> -d <Oracle_DB_Name> -t <point-in-time> -l <yes/no> -j <vip file> -v <view> -s <sbt file name> -p <number of channels> -o <ORACLE_HOME> -f <yes/no> -w <yes/no>"
echo " -r : RMAN login (example: \"rman target / \"), optional"
echo " -h : backup host (default is current host), optional"
echo " -i : Oracle instance name. If it is not RAC, it is the same as DB name. If it is RAC, it is the instance name like cohcdba2"
echo " -d : Oracle database name. only required for RAC. If it is RAC, it is the database name like cohcdba"
echo " -t : Point in Time (format example: \"2019-01-27 13:00:00\"), optional"
echo " -l : yes means complete restore including control file, no means not restoring controlfile"
echo " -j : file that has vip list"
echo " -v : Cohesity view"
echo " -s : Cohesity SBT library home"
echo " -p : number of channels (default is 4), optional"
echo " -o :  ORACLE_HOME (default is current environment), optional"
echo " -f : yes means force. It will restore Oracle database. Without it, it will just run RMAN validate (Optional)"
echo " -w : yes means preview rman backup scripts"
}

while getopts ":r:h:i:d:t:l:j:v:s:p:o:f:w:" opt; do
  case $opt in
    r ) rmanlogin=$OPTARG;;
    h ) host=$OPTARG;;
    i ) oraclesid=$OPTARG;;
    d ) dbname=$OPTARG;;
    t ) itime=$OPTARG;;
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
if test $oraclesid  && test $view && test $vipfile
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

echo $rmanlogin
if [[ -z $rmanlogin ]]; then
  rmanlogin="rman target /"
  echo "rman login command is $rmanlogin"
else 
  if [[ $rmanlogin = *target* ]]; then
#  echo *target*
    echo "rman login command is $rmanlogin"
  else
    echo "rmanlogin syntax should be \"rman target / \""
    exit 1
  fi
fi

if test $oracle_home; then
#  echo *target*
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
if [[ $DIR = '.' ]]; then
  DIR=`pwd`
fi

if [[ ! -d $DIR/log/$host ]]; then
  echo " $DIR/log/$host does not exist, create it"
  mkdir -p $DIR/log/$host
  
  if [ $? -ne 0 ]; then
    echo "create log directory $DIR/log/$host failed. There is a permission issue"
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

if test -f $vipfile; then
   echo "file $vipfile provided exists, script continue"
else
   vipfile=${DIR}/${vipfile}
   if test -f $vipfile; then
      echo "file $vipfile provided exists, script continue"
   else
      echo "file $vipfile provided does not exist"
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


# covert the time to numeric 
if [[ -z $itime ]]; then
  itime=`/bin/date '+%Y%m%d%H%M%S'`
  echo itime is $itime
  ptime=$itime
  echo "itime is $itime,  point-in-time restore time $ptime"  
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
  read -p "Do you know the correct controlfile backup file name: choose yes or no. If no, choose the mount point that has the controlfile next " yn
  case $yn in
    [Yy]* ) read -p "Enter the file name: " controlfile; break;;
    [Nn]* ) read -p "Do you know the mount points that has the controlfile: " answer; break;;
    * ) echo "Please answer yes or no.";;
  esac
done

if [[ -z $controlfile ]]; then
  if [[ $answer = [Yy]* ]]; then
    read -p "Enter the mount point that has the database backup: " mount
  
    cd ${mount}
    if [ $? -ne 0 ]; then
       echo "the mount ${mount} provided is incorrect"
       exit 3
    fi

    echo "get point-in-time controlfile"

    for bfile in ${dbname^^}_c-*.ctl; do
      bitime=`ls -l $bfile | awk '{print $6 " " $7 " " $8}'`
      if [ $? -ne 0 ]; then
  	echo "the mount ${mount} provided is incorrect"
        exit 3
      fi 
      btime=`/bin/date -d "$bitime" '+%Y%m%d%H%M%S'`
#     echo file time $btime
#     echo ptime $ptime
      if [[ $ptime -lt $btime ]]; then
        break
      else
        controlfile=$bfile
      fi
    done
  else
     echo "Can not determine the controlfile backup location. exit the script"
	 exit
  fi
fi
echo "The controlfile is $controlfile"

# get cohesity cluster VIP
i=1
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

incar_num2=`grep -i $oraclesid  $incarnation | grep -i CURRENT | awk '{print $2}'`
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

incar_num3=`grep -i $oraclesid  $incarnation | grep -i CURRENT | awk '{print $2}'`
echo "Oracle database incarnation is $incar_num3"

}

function create_rman_restore_database_file {

echo "Create rman restore database file"
echo "RUN {" >> $restore_rmanfile

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
	       allocate_database[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,gflag-name=sbt_use_grpc,gflag-value=true)';"
               unallocate[$j]="release channel c$j;"
            fi
            i=$[$i+1]
            j=$[$j+1]
	 fi
      fi
   done < $vipfile
done


for (( i=0; i < ${#allocate_database[@]}; i++ )); do
   echo ${allocate_database[$i]} >> $restore_rmanfile
done


if [[ ! -z $itime ]]; then
   echo "Oracle recovery point-in-time is define. Set recover time until $itime"
   echo "SET UNTIL TIME \"to_date('$itime', ''YYYY/MM/DD HH24:MI:SS')\";"
   echo "set until time \"to_date('$itime','YYYY/MM/DD HH24:MI:SS')\";" >> $restore_rmanfile
fi

if [[ -z $force ]]; then
   echo "restore database validate;" >> $restore_rmanfile
else
   echo "restore database;" >> $restore_rmanfile
fi


for (( i=0; i < ${#unallocate[@]}; i++ )); do
   echo ${unallocate[$i]} >> $restore_rmanfile
done

echo "
}
exit;
" >> $restore_rmanfile

echo "finished creating rman restore database file"
}

function create_rman_recover_database_file {

echo "Create rman recover database file"
echo "RUN {" >> $recover_rmanfile

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
               allocate_database[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,gflag-name=sbt_use_grpc,gflag-value=true)';"
               unallocate[$j]="release channel c$j;"
            fi
            i=$[$i+1]
            j=$[$j+1]
	 fi
      fi
   done < $vipfile
done

for (( i=0; i < ${#allocate_database[@]}; i++ )); do
   echo ${allocate_database[$i]} >> $recover_rmanfile
done


if [[ ! -z $itime ]]; then
   echo "Oracle recovery point-in-time is define. Set recover time until $itime"
   echo "SET UNTIL TIME \"to_date('$itime', ''YYYY/MM/DD HH24:MI:SS')\";"
   echo "set until time \"to_date('$itime','YYYY/MM/DD HH24:MI:SS')\";" >> $recover_rmanfile
fi
echo "recover database;" >> $recover_rmanfile


for (( i=0; i < ${#unallocate[@]}; i++ )); do
   echo ${unallocate[$i]} >> $recover_rmanfile
done

echo "}" >> $recover_rmanfile
#echo "alter database disable BLOCK CHANGE TRACKING;" >> $recover_rmanfile
echo "
alter database open resetlogs;
exit;
" >> $recover_rmanfile

echo "finished creating rman database recover file"
}

function restore_controlfile {
	
echo "will restore controlfile"
echo "check whether the database is up"
runoid=`ps -ef | grep pmon | awk '{print $8}' | grep -i $oraclesid | awk -F "_" '{print $3}'`

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
runoid=`ps -ef | grep pmon | awk '{print $8}' | grep -i $oraclesid | awk -F "_" '{print $3}'`
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

incar_num1=`grep -i $oraclesid  $incarnation | grep -i CURRENT | awk '{print $2}'`
echo "Oracle database incarnation is $incar_num1"

grep -i error $controlfile_rmanlog
  
if [ $? -eq 0 ]; then
   echo "Controlfile restore failed"
   exit 1
fi

}

function reset_incarnation_afterrestore {

echo "incarnation after restore"
$rmanlogin log $incarnation << EOF
list incarnation of database;
exit;
EOF

incar_num2=`grep -i $oraclesid  $incarnation | grep -i CURRENT | awk '{print $2}'`
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

incar_num3=`grep -i $oraclesid  $incarnation | grep -i CURRENT | awk '{print $2}'`
echo "Oracle database incarnation is $incar_num3"


}

function restore_database {

echo "Database restore started at " `/bin/date '+%Y%m%d%H%M%S'`
echo "ORACLE SID is $oraclesid"
runoid=`ps -ef | grep pmon | awk '{print $8}' | grep -i $oraclesid | awk -F "_" '{print $3}'`

if [[ ${runoid} != ${oraclesid} ]]; then
   echo "Oracle database $oraclesid is not up"
   echo "start the database in mount mode"
   $rmanlogin << EOF
   startup mount;
EOF
fi

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


}

function recover_database {

echo "Database recover started at " `/bin/date '+%Y%m%d%H%M%S'`
echo "ORACLE SID is $oraclesid"
runoid=`ps -ef | grep pmon | awk '{print $8}' | grep -i $oraclesid | awk -F "_" '{print $3}'`

if [[ ${runoid} != ${oraclesid} ]]; then
   echo "Oracle database $oraclesid is not up"
   echo "start the database in mount mode"
   $rmanlogin << EOF
   startup mount;
EOF
fi


$rmanlogin log $recover_rmanlog @$recover_rmanfile

if [ $? -ne 0 ]; then
  echo "   "
  echo "Database recover failed at " `/bin/date '+%Y%m%d%H%M%S'`
  echo "If missing archivelog logs, run the script with -c yes option"
  echo "We have seen that Oracle reports failure, but the recover is actually successful."
  ls -l ${ORACLE_HOME}/dbs/spfile*
  echo "The last 10 line of rman log output"
  echo " "
  echo "rmanlog file is $recover_rmanlog"
  tail $recover_rmanlog
  exit 1
else
  echo "  "
  echo "Database recover finished at " `/bin/date '+%Y%m%d%H%M%S'`
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
   create_rman_recover_database_file
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
   cat $recover_rmanfile
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
echo "check the start time and Finished restore time"
if [[ $full = "yes" || $rull = "Yes" || $full = "YES" || $full = "full" || $full = "Full" || $full = "FULL" ]]; then
   reset_incarnation_afterrestore
fi
exit
create_rman_recover_database_file
recover_database
echo "recover time is in rman log " $recover_rmanlog
echo "check the start time and Finished recover time"
