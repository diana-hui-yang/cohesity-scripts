#!/bin/bash
#
# Name:         sun-list-del-ora-agedfile.bash
#
# Function:     This script will delete data older than specifed days  
#
#
# Changes:
# 11/28/16 Diana Yang   New script
# 08/17/17 Diana Yang   Eliminate the need to specify the script directory
# 07/17/18 Diana Yang   change description and add more messages
# 06/20/19 Diana Yang   the script will only list files without -f option 
# 04/29/20 Diana Yang   Allow deletion at database level
# 04/20/21 Diana Yang   Change match to prefix
# 04/20/21 Diana Yang   Change find to gfind and awk to gawk
#################################################################


function show_usage {
echo "usage: sun-list-del-ora-agedfile.bash -h <host> -a <yes/no> -s <matching pattern> -d <Backup Files Directory> -r <specified day> -f <yes/no>" 
echo "  -h : host (optional)"
echo "  -a : yes/no (yes means all databases, no means individual database)"
echo "  -s : Search pattern"
echo "  -d : Backup Files Directory, NFS mount from Cohesity"
echo "  -r : specified day" 
echo "  -f : yes/no (yes means expired files will be deleted, no means list only)"
}


while getopts ":h:a:s:d:r:f:" opt; do
  case $opt in
    h ) host=$OPTARG;;
    a ) all=$OPTARG;;
    s ) match=$OPTARG;;
    d ) backupdir=$OPTARG;;
    r ) ret=$OPTARG;;
    f ) confirm=$OPTARG;;
  esac
done

# Check required parameters
if test $all && test $backupdir && test $ret 
then
  :
else
  show_usage
  exit 1
fi

echo "#the script will list of delete the files in $backupdir longer than the specified retention $ret"

if [[ $all = "all" || $all = "all" || $all = "all" || $all = "yes" || $all = "Yes" || $all = "YES" ]]; then
  echo "User all backup files older than $ret days to be listed or deleted instead of specific database"
  allfile=yes
else
  echo "User chooses specific database files older than $ret days to be listed or deleted"

  if test $match
  then
    :
  else
    echo "Search pattern is not provided"
    echo " "
    show_usage 
    exit 1
  fi
fi

function setup {
if test $host
then
  :
else
  host=`hostname -s`
fi

DATE_SUFFIX=`/bin/date '+%Y%m%d%H%M%S'`
#echo $DATE_SUFFIX

DIRcurrent=$0
DIR=`echo $DIRcurrent |  gawk 'BEGIN{FS=OFS="/"}{NF--; print}'`
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

if [[ $allfile = "yes" ]]; then
   runlog=$DIR/log/$host/delete-ora-expired.all.$DATE_SUFFIX.log
   filelist=$DIR/log/$host/files.all.$DATE_SUFFIX
else 
   runlog=$DIR/log/$host/delete-ora-expired.${match}.$DATE_SUFFIX.log
   filelist=$DIR/log/$host/files.${match}.$DATE_SUFFIX
fi

echo $host $match

#trim log directory
gfind $DIR/log/$host -type f -mtime +7 -exec /bin/rm {} \;

if [ $? -ne 0 ]; then
  echo "del old logs in $DIR/log/$host failed" >> $runlog
  echo "del old logs in $DIR/log/$host failed"
  exit 2
fi


if [[ ! -d $backupdir ]]; then
    echo "Directory $backupdir does not exist"
    exit 1
fi
  
#match=${match^^}
}

function listfiles {

   echo "List backup files started at " `/bin/date '+%Y%m%d%H%M%S'`
   echo "List backup files started at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog


   if [[ $allfile = "yes" ]]; then
      echo "All backup files older than $ret days are listed below"
	  echo "All backup files older than $ret days are listed below" >> $runlog
      echo "  "
      echo "--------------------"

      gfind $backupdir -type f -mtime +$ret |  grep -v "snapshot" > $filelist

   else
      echo ${match} "backup files older than $ret days are listed below"
	  echo ${match} "backup files older than $ret days are listed below" >> $runlog
      echo "  "
      echo "--------------------"

echo      gfind $backupdir -type f -mtime +$ret -name *${match}* |  grep -v "snapshot"
      gfind $backupdir -type f -mtime +$ret -name *${match}* |  grep -v "snapshot" > $filelist

   fi
      
   #ls $filelist
   filenum=`wc -l ${filelist} | gawk '{print $1}'`
  
   
   while IFS= read -r line
   do
       /bin/ls -l $line
   done < $filelist
 
   
   echo "List backup files finished at " `/bin/date '+%Y%m%d%H%M%S'`
   echo "List backup files finished at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog 
   echo "The number of backup files that are older than $ret days is " ${filenum}
}

function deletefiles {

   echo "Delete backup files started at " `/bin/date '+%Y%m%d%H%M%S'`
   echo "Delete backup files started at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog
   
   if [[ $allfile = "yes" ]]; then
      echo "Delete all backup files older than $ret days"
	  echo "Delete all backup files older than $ret days" >> $runlog
      echo "  "
      echo "--------------------"

      gfind $backupdir -type f -mtime +$ret |  grep -v "snapshot" > $filelist

   else
      echo "delete " ${match} "backup files older than $ret days"
	  echo "delete " ${match} "backup files older than $ret days" >> $runlog
      echo "  "
      echo "--------------------"

      gfind $backupdir -type f -mtime +$ret -name *${match}* |  grep -v "snapshot" > $filelist

   fi
   
   #ls $filelist
   filenum=`wc -l ${filelist} | gawk '{print $1}'`
   
   while IFS= read -r line
   do
      /bin/rm $line

       if [ $? -ne 0 ]; then
	      echo "Delete backup files $line failed"
          echo "Delete backup files $line failed" >> $runlog 
          exit 1
       fi
   done < $filelist
 
   echo "Delete backup files finished at " `/bin/date '+%Y%m%d%H%M%S'`
   echo "Delete backup files finished at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog 
   echo "The number of backup files that are deleted is " ${filenum}
   echo "The number of backup files that are deleted is " ${filenum} >> $runlog

   gfind $backkupdir -type d -empty -delete
}

setup
if [[ $confirm = "yes" || $confirm = "Yes" || $confirm = "YES" ]] 
then
   deletefiles
else
   listfiles
   echo "This option only lists the backup files older $ret days. "-f yes" option will truly delete these files"
fi

