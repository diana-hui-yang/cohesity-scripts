#!/bin/bash
#
# Name:         duplicate-ora-coh-oim.bash
#
# Function:     This script duplicate Oracle database from Oracle backup 
#               in nfs mount.
#
#
# Show Usage: run the command to show the usage
#
# Changes:
# 06/16/2020 Diana Yang   New script
#
#################################################################

function show_usage {
echo "usage: duplicate-ora-coh-oim.bash -r <RMAN login> -b <backup host> -a <target host> -s <Source Oracle database> -t <Target Oracle database> -f <file contain duplicate settting> -i <file contain setting to new pfile> -m <mount-prefix> -n <number of mounts> -p <number of channels> -c <yes or no>" 
echo " -r : RMAN login (example: \"rman auxiliary / target sys/<password>@<database connect string>\", optional)"
echo " -b : backup host" 
echo " -a : target host (Optional, default is localhost)"
echo " -s : Source Oracle database" 
echo " -t : Target Oracle database"
echo " -f : File contains duplicate settting, example: set newname for database to '/oradata/restore/orcl/%b'; "
echo " -i : File contains new setting to spfile. example: SET DB_CREATE_FILE_DEST +DGROUP3"
echo " -m : mount-prefix (like /coh/ora)"
echo " -n : number of mounts"
echo " -p : number of channels (Optional, default is same as the number of mounts4)"
echo " -c : Yes means Pluggable database (Optional. Default is none Pluggable database"
}

while getopts ":r:b:a:s:t:f:m:n:p:i:c:" opt; do
  case $opt in
    r ) rmanlogin=$OPTARG;;
    b ) shost=$OPTARG;;
    a ) thost=$OPTARG;;
    s ) sdbname=$OPTARG;;
    t ) tdbname=$OPTARG;;
    f ) ora-pfile=$OPTARG;;
	i ) ora-sfile=$OPTARG;;
    m ) mount=$OPTARG;;
    n ) num=$OPTARG;;
    p ) parallel=$OPTARG;;
    c ) plug=$OPTARG;;
  esac
done

#echo $rmanlogin $sdbname, $mount, $shost, $num

# Check required parameters
#if test $shost && test $sdbname && test $tdbname && test $tdbdir && test $mount && test $num
if test $shost && test $sdbname && test $tdbname && test $mount && test $num
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

if test $parallel
then
  :
else
  echo "no input for parallel, set parallel to be $num."
  parallel=$num
fi

echo $rmanlogin
if [[ $rmanlogin = *auxiliary* && $rmanlogin = *target* ]]; then
#if [[ $rmanlogin = *auxiliary* ]]; then
  echo *auxiliary*
  echo "rman login command is $rmanlogin"
else
  echo "rmanlogin syntax should be \"rman auxiliary / target sys/<password>@<database connect string> catalog <user>/<password>@<catalog>\""
  exit 1
fi

DATE_SUFFIX=`/bin/date '+%Y%m%d%H%M%S'`
#echo $DATE_SUFFIX

DIRcurrent=$0
DIR=`echo $DIRcurrent |  awk 'BEGIN{FS=OFS="/"}{NF--; print}'`
if [[ $DIR = '.' ]]; then
  DIR=`pwd`
fi

if [[ ! -d $DIR/log/$thost ]]; then
  echo " $DIR/log/$thost does not exist, create it"
  mkdir -p $DIR/log/$thost
  
  if [ $? -ne 0 ]; then
    echo "create log directory $DIR/log/$thost failed. There is a permission issue"
    exit 1
  fi
fi

drmanlog=$DIR/log/$thost/$tdbname.rman-duplicate.$DATE_SUFFIX.log
drmanfiled=$DIR/log/$thost/$tdbname.rman-duplicate.$DATE_SUFFIX.rcv
drmanfiled_b=$DIR/log/$thost/$tdbname.rman-duplicate_b.$DATE_SUFFIX.rcv
drmanfiled_e=$DIR/log/$thost/$tdbname.rman-duplicate_e.$DATE_SUFFIX.rcv


#echo $thost $oracle_sid $mount $num

#trim log directory
find $DIR/log/$thost -type f -mtime +7 -exec /bin/rm {} \;

if [ $? -ne 0 ]; then
  echo "del old logs in $DIR/log/$thost failed"
  exit 2
fi

export ORACLE_SID=$tdbname
}

function create_rman_duplicate_file {

echo "Create rman duplicate file"
echo "RUN {" >> $drmanfiled_b

i=1
j=1
while [ $i -le $num ]; do
  if mountpoint -q "${mount}${i}"; then
    echo "$mount${i} is mount point"
    echo " "
	
    if [[ ! -d "${mount}${i}/$shost/$sdbname/datafile" ]]; then
       echo "Directory ${mount}${i}/$shost/$sdbname/datafile does not exist, no backup files"
	   exit 1
    fi
	

    if [[ $j -le $parallel ]]; then
       echo "allocate auxiliary channel fs$j device type disk format = '$mount$i/$shost/$sdbname/datafile/%d_%T_%U';" >> $drmanfiled_b
       echo "release channel fs$j;" >> $drmanfiled_e
    fi

    i=$[$i+1]
    j=$[$j+1]


    if [[ $i -gt $num && $j -le $parallel ]]; then 
       i=1
    fi
  else
    echo "$mount${i} is not a mount point. duplicate will not start"
    echo "The mount prefix may not be correct or"
    echo "The input of the number of mount points may exceed the actuall number of mount points"
    exit 1
  fi
done

if [[ ! -z $ora-pfile ]]; then
   if test -f $ora-pfile; then
       grep -v "^#" < $ora-pfile | {while IFS= read -r para; do
	      para=`echo $para | xargs echo -n`
          echo $para >> $drmanfiled_b
       done }
   else
	   echo "$ora-pfile does not exist"
	   exit 1
   fi
fi

if [[ ! -z $ora-sfile ]]; then
   if test -f $ora-sfile; then
       echo "duplicate target database to $tdbname" >> $drmanfiled_b
	   echo "spfile" >> $drmanfiled_b
       grep -v "^#" < $ora-sfile | {while IFS= read -r spara; do
	      para=`echo $spara | xargs echo -n`
          echo $spara >> $drmanfiled_b
       done }
	   echo "nofilenamecheck;" >> $drmanfiled_b
   else
	   echo "$ora-sfile does not exist"
	   exit 1
   fi
else
   echo "duplicate target database to $tdbname nofilenamecheck;" >> $drmanfiled_b
fi  

cat $drmanfiled_b $drmanfiled_e > $drmanfiled

echo "}" >> $drmanfiled
echo "exit;" >> $drmanfiled

echo "finished creating rman duplicate file"
}


function duplicate {

echo "Database duplicate started at " `/bin/date '+%Y%m%d%H%M%S'`
echo "ORACLE SID is $ORACLE_SID"

$rmanlogin log $drmanlog @$drmanfiled

if [ $? -ne 0 ]; then
  echo "Database duplicate failed at " `/bin/date '+%Y%m%d%H%M%S'`
   exit 1
else
  echo "Database duplicate finished at " `/bin/date '+%Y%m%d%H%M%S'`
fi

}

setup
create_rman_duplicate_file
duplicate
