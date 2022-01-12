#!/bin/bash
#
# Name:         sbackup-ora-coh-oim.bash
#
# Function:     This script backup oracle using Oracle Incremental Merge
#               using nfs mount. It can do incremental backup and use Oracle
#               recovery catalog. It can do archive log backup only. The retention 
#               time is in days. If the retention time is unlimit, specify unlimit.
#		        It only deletes the backup files. It won't clean RMMAN catalog.
#               Oracle cleans its RMAN catalog.
#
#
# Show Usage: run the command to show the usage
#
# Changes:
# 06/11/20 Diana Yang   New script
# 07/01/20 Diana Yang   Add crosscheck
# 07/17/20 Diana Yang   Add catalog oracle datafiles created by Cohesity snapshot
# 08/26/20 Diana Yang   Add more contrains in RAC environment.
# 10/15/20 Diana Yang   Add Deletion of the expired backup using unix command
# 10/29/20 Diana Yang   make database name not case sensitive.
# 11/03/20 Diana Yang   Support backing up RAC using nodes supplied by users
# 10/12/21 Diana Yang   Add Cohesity directory snapshot capability by using Brian's cloneDirectory.py script
# 10/12/21 Diana Yang   Use gfind, gawk, and "hostname"
# 10/23/21 Diana Yang   Improve catalog performance
# 11/04/21 Diana Yang   Add Oracle section size option
# 10/11/21 Diana Yang   get ORACLE_HOME from /var/opt/oracle/oratab file
# 01/02/22 Diana Yang   Add MAX throughput limit allowed for RMAN backup 
#
#################################################################

function show_usage {
echo "usage: sbackup-ora-coh-oim.bash -r <Target connection> -c <Catalog connection> -h <host> -d <rac-node1-conn,rac-node2-conn,...> -o <Oracle_DB_Name> -t <backup type> -a <archive only> -y <Cohesity-cluster> -v <view> -u <Cohesity Oracle User> -g <AD Domain> -z <section size> -m <mount-prefix> -n <number of mounts> -p <number of channels> -e <retention> -s <python script directory> -l <archive log keep days> -b <ORACLE_HOME> -f <number of archive logs> -x <Max throughput> -w <yes/no>" 
echo " "
echo " Required Parameters"
echo " -h : host (scanname is required if it is RAC. optional if it is standalone.)"
echo " -o : ORACLE_DB_NAME (Need to have an entry of this database in /var/opt/oracle/oratab. If it is RAC, it is db_unique_name)"
echo " -t : backup type: Full or Incre"
echo " -a : yes (yes means archivelog backup only, no means database backup plus archivelog backup, no is optional)"
echo " -y : Cohesity Cluster DNS name"
echo " -v : Cohesity View that is configured to be the target for Oracle backup"
echo " -u : Cohesity Oracle User. The user should have access permission on the view"
echo " -g : Active Directory Domain of the Cohesity Oracle user. If the user is created on Cohesity, use local as the input"
echo " -m : mount-prefix (like /mnt/ora)"
echo " -n : number of mounts"
echo " -e : Retention time (days to retain the backups, apply only after uncomment \"Delete obsolete\" in this script)"
echo " "
echo " Optional Parameters"
echo " -r : Target connection (example: \"<dbuser>/<dbpass>@<target connection string> as sysbackup\", optional if it is local backup)"
echo " -c : Catalog connection (example: \"<dbuser>/<dbpass>@<catalog connection string>\", optional)"
echo " -d : Rac nodes connectons strings that will be used to do backup (example: \"<rac1-node connection string,ora2-node connection string>\")"
echo " -p : number of channels (Optional, default is 4)"
echo " -s : CloneDirectory.py directory (default directory is <current script directory>/python) "
echo " -l : Archive logs retain days (days to retain the local archivelogs before deleting them. default is 1 day)"
echo " -f : Number of times backing Archive logs (default is 1.)"
echo " -z : section size in GB (Optional, default is no section size)"
echo " -b : ORACLE_HOME (default is /var/opt/oracle/oratab, optional.)"
echo " -x : Maximum throughput (default is no limit. Unit is MB/sec. Archivelog backup throughput will be 20% of max throughput if database backup is running)"
echo " -w : yes means preview rman backup scripts"
}

while getopts ":r:c:h:d:o:a:t:y:v:u:g:z:m:n:p:s:e:l:f:b:x:w:" opt; do
  case $opt in
    r ) targetc=$OPTARG;;
    c ) catalogc=$OPTARG;;
    h ) host=$OPTARG;;
    d ) racconns=$OPTARG;;
    o ) dbname=$OPTARG;;
    a ) arch=$OPTARG;;
    t ) ttype=$OPTARG;;
    y ) cohesityname=$OPTARG;;
    v ) view=$OPTARG;;
    u ) cohesityuser=$OPTARG;;
    g ) addomain=$OPTARG;;
    z ) sectionsize=$OPTARG;;
    m ) mount=$OPTARG;;
    n ) num=$OPTARG;;
    p ) parallel=$OPTARG;;
    s ) pydir=$OPTARG;;
    e ) retday=$OPTARG;;
    l ) archretday=$OPTARG;;
    f ) archcopynum=$OPTARG;;
    b ) oracle_home=$OPTARG;;
    x ) max_throughput=$OPTARG;;
    w ) preview=$OPTARG;;
  esac
done

#echo $dbname, $mount, $host, $num

# Check required parameters
if test $mount && test $dbname && test $num && test $retday
then
  :
else
  show_usage 
  exit 1
fi

if [[ $arch = "arch" || $arch = "Arch" || $arch = "ARCH" || $arch = "yes" || $arch = "Yes" || $arch = "YES" ]]; then
  echo "Only backup archive logs"
  archivelogonly=yes
else
  echo "Will backup database backup plus archive logs"
 
  if test $cohesityname && test $view && test $cohesityuser && test $addomain
  then
    :
  else
    echo "Cohesity cluster, view, user information should be provided"
    show_usage
    exit 1
  fi

  if test $ttype
  then
    :
  else
    echo "Backup type was not specified. neet to set up parameter using -t "
    echo " "
    show_usage
    exit 1
  fi

fi

if [[ -z $archretday  ]]; then
  echo "Only retain one day local archive logs"
  archretday=1
fi

if [[ -z $archcopynum  ]]; then
  echo "The default number of the same archive log being backed up is once"
  archcopynum=1
fi

function setup {
if test $host
then
  hostdefinded=yes
else
  host=`hostname`
fi

if test $parallel
then
  :
else
  echo "no input for parallel, set parallel to be 4."
  parallel=4
fi

if test $max_throughput
then
   ((channel_thr=${max_throughput} / $parallel))
   ((arch_chan_parallel_thr=${channel_thr} / 5))
fi

if [[ -n $racconns ]]; then
  IFS=', ' read -r -a arrconns <<< "$racconns"
  if [[ -z $targetc ]]; then
    echo "RAC database connection information is missing. It is input after -r"
    exit 1
  fi
fi

if [[ -z $targetc ]]; then
  targetc="/"
  sqllogin="sqlplus / as sysdba"
else
  if [[ $targetc == "/" ]]; then
    echo "It is local backup"
    sqllogin="sqlplus / as sysdba"
  else
    remote="yes"
    cred=`echo $targetc | gawk -F @ '{print $1}'`
    conn=`echo $targetc | gawk -F @ '{print $2}' | gawk '{print $1}'`
    sysbackupy=`echo $targetc | gawk -F @ '{print $2}' | gawk 'NF>1{print $NF}'`
    if [[ -z $sysbackupy ]]; then
       sqllogin="sqlplus ${cred}@${conn} as sysdba"
    else
       sqllogin="sqlplus ${cred}@${conn} as sysbackup"
    fi
  fi
fi

echo target connection is ${targetc}

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

if [[ -n $pydir ]]; then
   echo "$pydir is python script directory"    
else
   echo "we assume the python script library is in $DIR/python"
   pydir=${DIR}/python
fi

pyname=${pydir}/cloneDirectory.py

if test -f $pyname; then
   echo "file $pyname exists, script continue"
else
   echo "file $pyname does not exist. exit"
   exit 1
fi

if test -f ${pydir}/pyhesity.py; then
   echo "file ${pydir}/pyhesity.py exists, script continue"
else
   echo "file ${pydir}/pyhesity.py does not exist. exit"
   exit 1
fi

if test -f ${pydir}/pyhesity.pyc; then
   echo "file ${pydir}/pyhesity.pyc exists, script continue"
else
   echo "file ${pydir}/pyhesity.pyc does not exist. Need to provide password for Cohesity Oracle user later"
fi

backup_dir=$host/$dbname
runlog=$DIR/log/$host/$dbname.$DATE_SUFFIX.log
runrlog=$DIR/log/$host/${dbname}.r.$DATE_SUFFIX.log
stdout=$DIR/log/$host/${dbname}.$DATE_SUFFIX.std
rmanlog1=$DIR/log/$host/$dbname.rman1.$DATE_SUFFIX.log
rmanlog2=$DIR/log/$host/$dbname.rman2.$DATE_SUFFIX.log
rmanlogs=$DIR/log/$host/$dbname.spfile.$DATE_SUFFIX.log
rmanloga=$DIR/log/$host/$dbname.archive.$DATE_SUFFIX.log
rmanlogar=$DIR/log/$host/$dbname.archive_r.$DATE_SUFFIX.log
rmanfiled1=$DIR/log/$host/$dbname.rman1.$DATE_SUFFIX.rcv
rmanfiled2=$DIR/log/$host/$dbname.rman2.$DATE_SUFFIX.rcv
rmanfilea=$DIR/log/$host/$dbname.archive.$DATE_SUFFIX.rcv
rmanfilear=$DIR/log/$host/$dbname.archive_r.$DATE_SUFFIX.rcv
catalog_bash=$DIR/log/$host/${dbname}_catalog.$DATE_SUFFIX.bash
catalog_log=$DIR/log/$host/${dbname}_catalog.$DATE_SUFFIX.log
filelist=$DIR/log/$host/${dbname}.files.all.$DATE_SUFFIX
tag=${dbname}_${DATE_SUFFIX}

#echo $host $oracle_sid $mount $num

#trim log directory
gfind $DIR/log/$host -type f -mtime +7 -exec /bin/rm {} \;

if [ $? -ne 0 ]; then
  echo "del old logs in $DIR/log/$host failed" >> $runlog
  echo "del old logs in $DIR/log/$host failed"
  exit 2
fi

if [[ $remote != "yes" ]]; then
  echo "check whether this database is up running on $host"
  runoid=`ps -ef | grep pmon | gawk 'NF>1{print $NF}' | grep -i $dbname | gawk -F "pmon" '{print $2}' | sort -t _ -k 1`

  arroid=($runoid)

  len=${#arroid[@]}

  j=0
  for (( i=0; i<$len; i++ ))
  do
    oracle_sid=${arroid[$i]}
    oracle_sid=${oracle_sid:1:${#oracle_sid}-1}
    lastc=${oracle_sid: -1}
    if [[ $oracle_sid == ${dbname} ]]; then
       echo "Oracle database $dbname is up on $host. Backup can start"
       yes_oracle_sid=$dbname
       j=1
       break
    else
       if [[ $lastc =~ ^[0-9]+$ ]]; then
         if [[ ${oracle_sid::${#oracle_sid}-1} == ${dbname} ]]; then
	    if [[ -z $hostdefinded ]]; then
   	      echo "This is RAC environment, scanname should be provided after -h option"
	      echo "  "
	      exit 2
   	    else
              echo "Oracle database $dbname is up on $host. Backup can start"
              yes_oracle_sid=$oracle_sid
    	      j=1
 	    fi
         fi
       fi 
    fi
  done

  if [[ $j -eq 0 ]]; then
    echo "Oracle database $dbname is not up on $host. Backup will not start on $host"
    exit 2
  fi
  echo ORACLE_SID is $yes_oracle_sid
  export ORACLE_SID=$yes_oracle_sid
fi

#echo yes_oracle_sid is $yes_oracle_sid

# get ORACLE_HOME in /var/opt/oracle/oratab if it is not provided in input

if [[ -z $oracle_home ]]; then

#change dbname to lowercase
#  dbname=${dbname,,}
  oratabinfo=`grep -i $dbname /var/opt/oracle/oratab`

#echo oratabinfo is $oratabinfo

  arrinfo=($oratabinfo)
  leninfo=${#arrinfo[@]}

  k=0
  for (( i=0; i<$leninfo; i++))
  do
    orasidintab=`echo ${arrinfo[$i]} | gawk -F ":" '{print $1}'`
    orasidintab=${orasidintab,,}
    orahomeintab=`echo ${arrinfo[$i]} | gawk -F ":" '{print $2}'`
  
    if [[ $orasidintab == ${dbname} ]]; then    
       oracle_home=$orahomeintab
       export ORACLE_HOME=$oracle_home
       export PATH=$PATH:$ORACLE_HOME/bin
       k=1
    fi
#   echo orasidintab is $orasidintab
  done

  if [[ $k -eq 0 ]]; then
    oratabinfo=`grep -i ${dbname::${#dbname}-1} /var/opt/oracle/oratab`
    arrinfo=($oratabinfo)
    leninfo=${#arrinfo[@]}

    j=0
    for (( i=0; i<$leninfo; i++))
    do
      orasidintab=`echo ${arrinfo[$i]} | gawk -F ":" '{print $1}'`
      orasidintab=${orasidintab,,}
      orahomeintab=`echo ${arrinfo[$i]} | gawk -F ":" '{print $2}'`

      if [[ $orasidintab == ${dbname} ]]; then
        oracle_home=$orahomeintab
        export ORACLE_HOME=$oracle_home
        export PATH=$PATH:$ORACLE_HOME/bin
        j=1
      fi
    done

    if [[ $j -eq 0 ]]; then
	  echo "No Oracle db_unique_name $dbname information in /var/opt/oracle/oratab. Will check whether ORACLE_HOME is set"
	  if [[ ! -d $ORACLE_HOME ]]; then	     
         echo "No Oracle db_unique_name $dbname information in /var/opt/oracle/oratab and ORACLE_HOME is not set"
         exit 2
	  fi
    else
      echo ORACLE_HOME is $ORACLE_HOME
    fi
 
  else
    echo ORACLE_HOME is $ORACLE_HOME
  fi

else
  export ORACLE_HOME=$oracle_home
  export PATH=$PATH:$ORACLE_HOME/bin
fi

which rman

if [ $? -ne 0 ]; then
  echo "oracle home $oracle_home provided or found in /var/opt/oracle/oratab is incorrect"
  exit 1
fi

export NLS_DATE_FORMAT='DD:MM:YYYY-HH24:MI:SS'
export ORACLE_SID=$yes_oracle_sid

echo oracle sid is $ORACLE_SID

if [[ $remote == "yes" ]]; then
echo "target connection is $targetc"
# test target connection
   rmanr=`rman << EOF
   connect target '${targetc}'
   exit;
EOF`

   echo $rmanr | grep -i connected
   
   if [ $? -ne 0 ]; then
      echo "rman connection using $targetc is incorrect
           "
      echo $rmanr
      echo "
           targetc syntax can be like \"/\" or
          \"sys/<password>@<target database connect string>\""
      exit 1
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
       echo $rmanr
       echo "
           catalogc syntax can be like \"/\" or
          \"<catalog dd user>/<password>@<catalog database connect string>\""
       exit 1
     fi
   fi
fi

# confirm dbname provided is the same as connection string
if [[ $remote == "yes" ]]; then
   dbquery=`$sqllogin << EOF
   show parameter db_name;
   exit
EOF`

   echo $dbquery | grep -i $dbname
   if [ $? -eq 0 ]; then
      echo "dbname provided is the same as connection string"
   else
      echo "dbname provided is not the same provided in connection string"
      exit 1
   fi
fi

$sqllogin << EOF
   spool $stdout
   select open_mode from v\$database;
EOF
    
grep -i "read only" $stdout
if [ $? -eq 0 ]; then
   echo "Database is in read only mode"
   dbstatus=readonly
fi
}

function create_rmanfile_all {


echo "Create rman file" >> $runlog

echo "
CONFIGURE DEFAULT DEVICE TYPE TO disk;
CONFIGURE DEVICE TYPE DISK PARALLELISM $parallel BACKUP TYPE TO BACKUPSET;
CONFIGURE CONTROLFILE AUTOBACKUP ON;
CONFIGURE CONTROLFILE AUTOBACKUP FORMAT FOR DEVICE TYPE DISK TO '${mount}1/$host/$dbname/controlfile/%d_%F.ctl';
" > $rmanfiled1

echo " 
RUN {
" >> $rmanfiled1

echo " 
RUN {
" >> $rmanfiled2

echo "
CONFIGURE DEFAULT DEVICE TYPE TO disk;
CONFIGURE DEVICE TYPE DISK PARALLELISM $parallel BACKUP TYPE TO BACKUPSET;
CONFIGURE CONTROLFILE AUTOBACKUP ON;
CONFIGURE CONTROLFILE AUTOBACKUP FORMAT FOR DEVICE TYPE DISK TO '${mount}1/$host/$dbname/controlfile/%d_%F.ctl';

RUN {
" >> $rmanfilea

i=1
j=0
k=0
while [ $i -le $num ]; do
  mountstatus=`mount | grep -i  "${mount}${i}"`
  if [[ -n $mountstatus ]]; then
#    echo "
#	$mount${i} is mount point
#    "
	
    if [[ ! -d "${mount}${i}/$host/$dbname/datafile" ]]; then
       echo "Directory ${mount}${i}/$host/$dbname/datafile does not exist, create it"
       if mkdir -p ${mount}${i}/$host/$dbname/datafile; then
          echo "${mount}${i}/$host/$dbname/datafile is created"
       else
          echo "creating ${mount}${i}/$host/$dbname/datafile failed. There is a permission issue"
          exit 1
       fi
    fi
	
    if [[ ! -d "${mount}${i}/$host/$dbname/controlfile" ]]; then
       echo "Directory ${mount}${i}/$host/$dbname/controlfile does not exist, create it"
       if mkdir -p ${mount}${i}/$host/$dbname/controlfile; then
          echo "${mount}${i}/$host/$dbname/controlfile is created"
       else
          echo "creating ${mount}${i}/$host/$dbname/controlfile failed. There is a permission issue"
          exit 1
       fi
    fi
	
    if [[ ! -d "${mount}${i}/$host/$dbname/archivelog" ]]; then
       echo "Directory ${mount}${i}/$host/$dbname/archivelog does not exist, create it"
       if mkdir -p ${mount}${i}/$host/$dbname/archivelog; then
          echo "${mount}${i}/$host/$dbname/archivelog is created"
       else
          echo "creating ${mount}${i}/$host/$dbname/archivelog failed. There is a permission issue"
          exit 1
       fi
    fi
	
	if [[ ! -d "${mount}${i}/$host/$dbname/spfile" ]]; then
       echo "Directory ${mount}${i}/$host/$dbname/spfile does not exist, create it"
       if mkdir -p ${mount}${i}/$host/$dbname/spfile; then
          echo "${mount}${i}/$host/$dbname/spfile is created"
       else
          echo "creating ${mount}${i}/$host/$dbname/spfile failed. There is a permission issue"
          exit 1
       fi
    fi
	
    if [[ -n $racconns ]]; then
       if [[ $j -lt $parallel ]]; then
	   if [[ -n $max_throughput ]]; then
	       allocate_database[$j]="allocate channel fs$j device type disk rate ${channel_thr}M connect='$cred@${arrconns[$k]}' format = '$mount$i/$host/$dbname/datafile/%d_%T_%U';"
	       allocate_archive[$j]="allocate channel fs$j device type disk rate ${channel_thr}M connect='$cred@${arrconns[$k]}' format = '$mount$i/$host/$dbname/archivelog/%d_%T_%U.blf';"
	   else
	       allocate_database[$j]="allocate channel fs$j device type disk connect='$cred@${arrconns[$k]}' format = '$mount$i/$host/$dbname/datafile/%d_%T_%U';"
	       allocate_archive[$j]="allocate channel fs$j device type disk connect='$cred@${arrconns[$k]}' format = '$mount$i/$host/$dbname/archivelog/%d_%T_%U.blf';"
           fi
	   unallocate[j]="release channel fs$j;"
       fi

       i=$[$i+1]
       j=$[$j+1]
       k=$[$k+1]

       if [[ $k -ge ${#arrconns[@]} && $j -le $parallel ]]; then 
          k=0
       fi

       if [[ $i -gt $num && $j -lt $parallel ]]; then 
          i=1
       fi
    else
       if [[ $j -lt $parallel ]]; then
	   if [[ -n $max_throughput ]]; then
	       allocate_database[$j]="allocate channel fs$j device type disk rate ${channel_thr}M format = '$mount$i/$host/$dbname/datafile/%d_%T_%U';"
	       allocate_archive[$j]="allocate channel fs$j device type disk rate ${channel_thr}M format = '$mount$i/$host/$dbname/archivelog/%d_%T_%U.blf';"
	   else
               allocate_database[$j]="allocate channel fs$j device type disk format = '$mount$i/$host/$dbname/datafile/%d_%T_%U';"
	       allocate_archive[$j]="allocate channel fs$j device type disk format = '$mount$i/$host/$dbname/archivelog/%d_%T_%U.blf';"
	   fi
           unallocate[j]="release channel fs$j;"
       fi

       i=$[$i+1]
       j=$[$j+1]


       if [[ $i -gt $num && $j -lt $parallel ]]; then 
          i=1
       fi
    fi
  else
    echo "$mount${i} is not a mount point. Backup will not start
    The mount prefix may not be correct or
    The input of the number of mount points may exceed the actuall number of mount points"
    exit 1
  fi
done

i=1
j=0
k=0
parallel_incre=$((2*parallel))
while [ $i -le $num ]; do
  mountstatus=`mount | grep -i  "${mount}${i}"`
  if [[ -n $mountstatus ]]; then
#    echo "
#	$mount${i} is mount point
#    "
	
    if [[ -n $racconns ]]; then
       if [[ $j -lt $parallel_incre ]]; then
	  allocate_database_incre[$j]="allocate channel fs$j device type disk connect='$cred@${arrconns[$k]}' format = '$mount$i/$host/$dbname/datafile/%d_%T_%U';"
          unallocate_incre[j]="release channel fs$j;"
       fi

       i=$[$i+1]
       j=$[$j+1]
       k=$[$k+1]

       if [[ $k -ge ${#arrconns[@]} && $j -le $parallel_incre ]]; then 
          k=0
       fi

       if [[ $i -gt $num && $j -lt $parallel_incre ]]; then 
          i=1
       fi
    else
       if [[ $j -lt $parallel_incre ]]; then
          allocate_database_incre[$j]="allocate channel fs$j device type disk format = '$mount$i/$host/$dbname/datafile/%d_%T_%U';"
	  unallocate_incre[j]="release channel fs$j;"
       fi

       i=$[$i+1]
       j=$[$j+1]


       if [[ $i -gt $num && $j -lt $parallel_incre ]]; then 
          i=1
       fi
    fi
  else
    echo "$mount${i} is not a mount point. Backup will not start
    The mount prefix may not be correct or
    The input of the number of mount points may exceed the actuall number of mount points"
    exit 1
  fi
done

for (( i=0; i < ${#allocate_database[@]}; i++ )); do
   echo ${allocate_database[$i]} >> $rmanfiled1
done

for (( i=0; i < ${#allocate_database_incre[@]}; i++ )); do
   echo ${allocate_database_incre[$i]} >> $rmanfiled2
done

for (( i=0; i < ${#allocate_archive[@]}; i++ )); do
   echo ${allocate_archive[$i]} >> $rmanfilea
done

if [[ $ttype = "full" || $type = "Full" || $ttype = "FULL" ]]; then
   echo "Full backup" 
   echo "Full backup" >> $runlog
   echo "
   crosscheck datafilecopy all;
   delete noprompt expired datafilecopy all;
   delete noprompt copy of database tag 'incre_update'; " >> $rmanfiled1
   
   if [[ -z $sectionsize ]]; then
      echo "backup incremental level 1 for recover of copy with tag 'incre_update' database filesperset 8; " >> $rmanfiled1
   else
      echo "backup SECTION SIZE $sectionsize incremental level 1 for recover of copy with tag 'incre_update' database filesperset 8; " >> $rmanfiled1 
   fi
   
   echo "
   recover copy of database with tag  'incre_update';
   " >> $rmanfiled2
#   echo "
#   crosscheck backup;
#   delete noprompt expired backup;
#   " >> $rmanfiled
elif [[  $ttype = "incre" || $ttype = "Incre" || $ttype = "INCRE" ]]; then
   echo "incremental merge" 
   echo "incremental merge" >> $runlog
   echo "
   crosscheck datafilecopy all;
   delete noprompt expired datafilecopy all;" >> $rmanfiled1

   if [[ -z $sectionsize ]]; then
      echo "backup incremental level 1 for recover of copy with tag 'incre_update' database filesperset 8; " >> $rmanfiled1
   else
      echo "backup SECTION SIZE $sectionsize incremental level 1 for recover of copy with tag 'incre_update' database filesperset 8; " >> $rmanfiled1 
   fi
   echo "
   recover copy of database with tag 'incre_update';
   " >> $rmanfiled2
#   echo "
#   crosscheck backup;
#   delete noprompt expired backup;
#   " >> $rmanfiled
else
   echo "backup type entered is not correct. It should be full or incre"
   echo "backup type entered is not correct. It should be full or incre" >> $runlog
   exit 1
fi
   
if [[ $archretday -eq 0 ]]; then
   echo "backup archivelog all filesperset 8 not backed up $archcopynum times delete input;" >> $rmanfilea
else
   echo "backup archivelog all filesperset 8 not backed up $archcopynum times archivelog until time 'sysdate-$archretday' delete input;" >> $rmanfilea
fi

for (( i=0; i < ${#unallocate[@]}; i++ )); do
   echo ${unallocate[$i]} >> $rmanfiled1
   echo ${unallocate[$i]} >> $rmanfilea
done

for (( i=0; i < ${#unallocate_incre[@]}; i++ )); do
   echo ${unallocate_incre[$i]} >> $rmanfiled2
done

echo " 
}
exit;
" >> $rmanfiled1
echo " 
}
exit;
" >> $rmanfiled2
echo "
}
exit;
" >> $rmanfilea

echo "finished creating rman file" >> $runlog
echo "finished creating rman file"
}

function create_rmanfile_archive {

if [[ -n $max_throughput ]]; then
#determine whether database backup is running or not
   rm $stdout
   $sqllogin << EOF
   spool $stdout
   select status from v\$RMAN_BACKUP_JOB_DETAILS where status='RUNNING';
EOF
    
   running_rman_num=`grep -i "RUNNING" $stdout | wc -l`
   if [[ $running_rman_num -gt 1 ]]; then
      echo "Database backup is in running. The archivelog throughput will be reduced"
      rman_running=yes
   fi
fi


echo "Create rman file" >> $runrlog

echo "
CONFIGURE DEFAULT DEVICE TYPE TO disk;
CONFIGURE DEVICE TYPE DISK PARALLELISM $parallel BACKUP TYPE TO BACKUPSET;
CONFIGURE CONTROLFILE AUTOBACKUP ON;
CONFIGURE CONTROLFILE AUTOBACKUP FORMAT FOR DEVICE TYPE DISK TO '${mount}1/$host/$dbname/controlfile/%d_%F.ctl';

RUN {
" >> $rmanfilear

#echo "CONFIGURE DEVICE TYPE DISK PARALLELISM $parallel BACKUP TYPE TO BACKUPSET;" >> $rmanfilear
#echo "CONFIGURE retention policy to recovery window of $retday days;" >> $rmanfilear 
#echo "Delete obsolete;" >> $rmanfilear 

i=1
j=0
while [ $i -le $num ]; do
  mountstatus=`mount | grep -i  "${mount}${i}"`
  if [[ -n $mountstatus ]]; then
#    echo "$mount${i} is mount point"
#    echo " "
	
    if [[ ! -d "${mount}${i}/$host/$dbname/archivelog" ]]; then
       echo "Directory ${mount}${i}/$host/$dbname/archivelog does not exist, create it"
       if mkdir -p ${mount}${i}/$host/$dbname/archivelog; then
          echo "${mount}${i}/$host/$dbname/archivelog is created"
       else
          echo "creating ${mount}${i}/$host/$dbname/archivelog failed. There is a permission issue"
          exit 1
       fi
    fi
	
	if [[ ! -d "${mount}${i}/$host/$dbname/controlfile" ]]; then
       echo "Directory ${mount}${i}/$host/$dbname/controlfile does not exist, create it"
       if mkdir -p ${mount}${i}/$host/$dbname/controlfile; then
          echo "${mount}${i}/$host/$dbname/controlfile is created"
       else
          echo "creating ${mount}${i}/$host/$dbname/controlfile failed. There is a permission issue"
          exit 1
       fi
    fi
	
	
    if [[ $j -lt $parallel ]]; then
       if [[ -n $max_throughput ]]; then
          if [[ -n $rman_running ]]; then
	     allocate_archive[$j]="allocate channel fs$j device type disk rate ${arch_chan_parallel_thr}M format = '$mount$i/$host/$dbname/archivelog/%d_%T_%U.blf';"
	  else
	     allocate_archive[$j]="allocate channel fs$j device type disk rate ${channel_thr}M format = '$mount$i/$host/$dbname/archivelog/%d_%T_%U.blf';" 
	  fi
       else
          allocate_archive[$j]="allocate channel fs$j device type disk format = '$mount$i/$host/$dbname/archivelog/%d_%T_%U.blf';"
       fi
       unallocate[j]="release channel fs$j;"
    fi

    i=$[$i+1]
    j=$[$j+1]


    if [[ $i -gt $num && $j -lt $parallel ]]; then 
       i=1
    fi
  else
    echo "$mount${i} is not a mount point. Backup will not start
    The mount prefix may not be correct or
    The input of the number of mount points may exceed the actuall number of mount points"
    exit 1
  fi
done

for (( i=0; i < ${#allocate_archive[@]}; i++ )); do
   echo ${allocate_archive[$i]} >> $rmanfilear
done

if [[ $archretday -eq 0 ]]; then
   echo "backup archivelog all filesperset 8 not backed up $archcopynum times delete input;" >> $rmanfilear
else
   echo "backup archivelog all filesperset 8 not backed up $archcopynum times archivelog until time 'sysdate-$archretday' delete input;" >> $rmanfilear
fi

for (( i=0; i < ${#unallocate[@]}; i++ )); do
   echo ${unallocate[$i]} >> $rmanfilear
done

echo "}
exit;" >> $rmanfilear

echo "finished creating rman file" >> $runrlog
echo "finished creating rman file"
}

function catalog_snapshot {

#create a bash script that will catalog the baskup files created by Cohesity snapshot
echo "#!/bin/bash

echo \"Catalog the snapshot files started at  \" \`/bin/date '+%Y%m%d%H%M%S'\`
export ORACLE_HOME=$oracle_home
export PATH=$PATH:$ORACLE_HOME/bin
export NLS_DATE_FORMAT='DD:MM:YYYY-HH24:MI:SS'
export ORACLE_SID=$yes_oracle_sid
" >> $catalog_bash

if [[ -z $catalogc ]]; then
echo "
rman log $catalog_log << EOF
 connect target '${targetc}'
" >> $catalog_bash
else
echo "
rman log $catalog_log << EOF
connect target '${targetc}'
connect catalog '${catalogc}'
" >> $catalog_bash
fi

echo "
CONFIGURE DEFAULT DEVICE TYPE TO disk;
CONFIGURE CONTROLFILE AUTOBACKUP ON;
CONFIGURE CONTROLFILE AUTOBACKUP FORMAT FOR DEVICE TYPE DISK TO '${mount}1/$host/$dbname/controlfile/%d_%F.ctl';
" >> $catalog_bash
#cd ${mount}1/$host/$dbname/datafile.$DATE_SUFFIX
cd ${mount}1/$host/$dbname/datafile
	 
num_dfile=`ls *_data_*| wc -l`
dfile=(`ls *_data_*`)
i=1
j=0
k=1
while [ $i -le $num ]; do
  	
  if [[ $j -lt $num_dfile ]]; then
     if [[ $k -eq 1 ]]; then
        echo "CATALOG DATAFILECOPY 	 
        '${mount}${i}/$host/$dbname/datafile.$DATE_SUFFIX/${dfile[$j]}'"  >> $catalog_bash
     else
        echo ",'${mount}${i}/$host/$dbname/datafile.$DATE_SUFFIX/${dfile[$j]}'"  >> $catalog_bash
     fi
  fi

  i=$[$i+1]
  j=$[$j+1]
  k=$[$k+1]


  if [[ $i -gt $num && $j -le $num_dfile ]]; then 
     i=1
  fi
  
  if [[ $k -ge 200 && $j -le $num_dfile ]];then
     echo " tag '${tag}';" >> $catalog_bash
     k=1
  fi
  
done

if [[ $j -ge $num_dfile ]]; then
   echo " tag '${tag}';" >> $catalog_bash
fi

echo "
backup as copy current controlfile format '${mount}1/$host/$dbname/controlfile/$dbname.ctl.$DATE_SUFFIX';
exit;
EOF

if [[ ! -f $catalog_log ]]; then
   echo \"$catalog_log does not exist. 
Catalog the snapshot files finished at  \" \`/bin/date '+%Y%m%d%H%M%S'\`
   echo \"$catalog_log does not exist. 
Catalog the snapshot files finished at  \" \`/bin/date '+%Y%m%d%H%M%S'\` >> $runlog
   exit 1
fi

if [[ ! -z \`grep -i error" $catalog_log"\` ]]; then
  echo \"
  catalog the snapshot files failed at \" \`/bin/date '+%Y%m%d%H%M%S'\`
  echo \"
  catalog the snapshot files failed at \" \`/bin/date '+%Y%m%d%H%M%S'\` >> $runlog
  exit 1
else
  echo \"
  Catalog the snapshot files finished at  \" \`/bin/date '+%Y%m%d%H%M%S'\`
  echo \"
  Catalog the snapshot files finished at  \" \`/bin/date '+%Y%m%d%H%M%S'\` >> $runlog
fi
" >> $catalog_bash

    
chmod 750 $catalog_bash

}


function backup1 {

echo "Database backup started at " `/bin/date '+%Y%m%d%H%M%S'`
echo "Database backup started at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog

# Create the latest pfile
pfile_path=${mount}1/$host/$dbname/spfile/init$dbname.$DATE_SUFFIX.ora
echo "create pfile to $pfile_path" >> $runlog
$sqllogin << EOF 2>&1
CREATE PFILE='$pfile_path' FROM MEMORY;
EOF

# backup spfile
echo "backup spfile" >> $runlog
if [[ -z $catalogc ]]; then
   rman log $rmanlogs << EOF
   connect target '${targetc}'
   BACKUP AS COPY SPFILE format '${mount}1/$host/$dbname/spfile/spfile%d.%T_%U.ora';
   alter database backup controlfile to trace as '${mount}1/$host/$dbname/spfile/controltrace.$DATE_SUFFIX.sql';
EOF
else
   rman log $rmanlogs << EOF
   connect target '${targetc}'
   connect catalog '${catalogc}'
   BACKUP AS COPY SPFILE format '${mount}1/$host/$dbname/spfile/spfile%d.%T_%U.ora';
   alter database backup controlfile to trace as '${mount}1/$host/$dbname/spfile/controltrace.$DATE_SUFFIX.sql';
EOF
fi

if [[ -z $catalogc ]]; then
   rman log $rmanlog1 << EOF
   connect target '${targetc}'
   @$rmanfiled1
EOF
else
   rman log $rmanlog1 << EOF
   connect target '${targetc}'
   connect catalog '${catalogc}'
   @$rmanfiled1
EOF
fi

if [ $? -ne 0 ]; then
  echo "
  Database backup failed at " `/bin/date '+%Y%m%d%H%M%S'`
  echo "
  Database backup failed at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog
  while IFS= read -r line
  do
    echo $line
  done < $rmanlog1
  exit 1
else
  echo "
  Database backup finished at " `/bin/date '+%Y%m%d%H%M%S'`
  echo "
  Database backup finished at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog 
fi

if [[ $dbstatus != "readonly" ]]; then
rman << EOF
connect target '${targetc}'
sql 'alter system switch logfile';
exit
EOF
fi

}

function backup2 {

echo "Database incremenal merge started at " `/bin/date '+%Y%m%d%H%M%S'`
echo "Database incremenal merge started at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog


if [[ -z $catalogc ]]; then
   rman log $rmanlog2 << EOF
   connect target '${targetc}'
   @$rmanfiled2
EOF
else
   rman log $rmanlog2 << EOF
   connect target '${targetc}'
   connect catalog '${catalogc}'
   @$rmanfiled2
EOF
fi

if [ $? -ne 0 ]; then
  echo "
  Database incremenal merge failed at " `/bin/date '+%Y%m%d%H%M%S'`
  echo "
  Database incremenal merge failed at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog
  while IFS= read -r line
  do
    echo $line
  done < $rmanlog2
  exit 1
else
  echo "
  Database incremenal merge finished at " `/bin/date '+%Y%m%d%H%M%S'`
  echo "
  Database incremenal merge finished at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog 
fi

}


function archive {

echo "Archive logs backup started at " `/bin/date '+%Y%m%d%H%M%S'`
echo "Archive logs backup started at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog

if [[ -z $catalogc ]]; then
   rman log $rmanloga << EOF
   connect target '${targetc}'
   @$rmanfilea
EOF
else
   rman log $rmanloga << EOF
   connect target '${targetc}'
   connect catalog '${catalogc}'
   @$rmanfilea
EOF
fi

if [ $? -ne 0 ]; then
  echo "
  Archive logs backup failed at " `/bin/date '+%Y%m%d%H%M%S'`
  echo "
  Archive logs backup failed at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog
  while IFS= read -r line
  do
    echo $line
  done < $rmanloga
  exit 1
else
  echo "
  Archive logs backup finished at " `/bin/date '+%Y%m%d%H%M%S'`
  echo "
  Archive logs backup finished at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog 
fi
}


function archiver {

echo "Archive logs backup started at " `/bin/date '+%Y%m%d%H%M%S'`
echo "Archive logs backup started at " `/bin/date '+%Y%m%d%H%M%S'` >> $runrlog

if [[ -z $catalogc ]]; then
   rman log $rmanlogar << EOF
   connect target '${targetc}'
   @$rmanfilear
EOF
else
   rman log $rmanlogar << EOF
   connect target '${targetc}'
   connect catalog '${catalogc}'
   @$rmanfilear
EOF
fi

if [ $? -ne 0 ]; then
  echo "
  Archive logs backup failed at " `/bin/date '+%Y%m%d%H%M%S'`
  echo "
  Archive logs backup failed at " `/bin/date '+%Y%m%d%H%M%S'` >> $runrlog
  while IFS= read -r line
  do
    echo $line
  done < $rmanlogar
  exit 1
else
  echo "
  Archive logs backup finished at " `/bin/date '+%Y%m%d%H%M%S'`
  echo "
  Archive logs backup finished at " `/bin/date '+%Y%m%d%H%M%S'` >> $runrlog 
fi

grep -i error $rmanlogar
 
if [ $? -eq 0 ]; then
   echo "Backup is successful. However there are channels not correct"
   exit 1
else
   echo "Backup is successful."
fi
}

function delete_expired {

if ! [[ "$retday" =~ ^[0-9]+$ ]]; then
  echo "$retday is not an integer. No data expiration after this backup"
  exit 1
  echo "Need to change the parameter after -e to be an integer"
else
 # let retnewday=$retday+1
  let retnewday=$retday
  echo "Clean backup files older than $retnewday started at " `/bin/date '+%Y%m%d%H%M%S'`
  echo "Clean backup files older than $retnewday started at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog
  echo "only delete old expired backup during database backup" >> $runlog
  if [[ -d "${mount}1/$host/$dbname" ]]; then
    gfind ${mount}1/$host/$dbname/datafile -type f -mtime +1 | grep -v D-${dbname^^} >> ${filelist}
    gfind ${mount}1/$host/$dbname/archivelog -type f -mtime +$retnewday  -exec /bin/rm -v {} \; >> $runlog
    gfind ${mount}1/$host/$dbname/controlfile -type f -mtime +$retnewday  -exec /bin/rm -v {} \; >> $runlog
    gfind ${mount}1/$host/$dbname/spfile -type f -mtime +$retnewday  -exec /bin/rm -v {} \; >> $runlog
    gfind ${mount}1/$host/$dbname/* -type d -mtime +$retnewday -prune -exec rm -rv {} \; >> $runlog
	
 #   filenum=`wc -l ${filelist} | gawk '{print $1}'`
   
    while IFS= read -r line
    do
      /bin/rm -v $line >> $runlog

      if [ $? -ne 0 ]; then
         echo "Delete backup files $line failed"
         echo "Delete backup files $line failed" >> $runlog 
      fi
    done < ${filelist}
	
   
    gfind ${mount}1/$host/$dbname -depth -type d -empty -exec /bin/rmdir -v {} \; >> $runlog
  fi
  echo "Clean backup files older than $retnewday finished at " `/bin/date '+%Y%m%d%H%M%S'`
  echo "Clean backup files older than $retnewday finished at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog
fi

}

function run_snapshot_catalog {

# create snapshot of backup files in backup_dir/datafile directory
echo "
clone directory /$view/${backup_dir}/datafile started at " `/bin/date '+%Y%m%d%H%M%S'`
echo "
clone directory /$view/${backup_dir}/datafile started at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog
$pyname -v $cohesityname -u $cohesityuser -d $addomain -s /$view/${backup_dir}/datafile -t /$view/${backup_dir}/datafile.$DATE_SUFFIX

if [ $? -ne 0 ]; then
  echo "Cohesity snapshot backup files in ${mount}1/${backup_dir}/datafile failed at " `/bin/date '+%Y%m%d%H%M%S'`
  echo "Cohesity snapshot backup files in ${mount}1/${backup_dir}/datafile failed at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog
  exit 1
else
  echo "Cohesity snapshot backup files in ${mount}1/${backup_dir}/datafile finished at " `/bin/date '+%Y%m%d%H%M%S'`
  echo "Cohesity snapshot backup files in ${mount}1/${backup_dir}/datafile finished at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog
fi

sleep 5

# RMAN catalog the snapshot backup file
echo " "
$catalog_bash
echo " "

}


setup

if [[ $archivelogonly = "yes" ]]; then
  echo "archive logs backup only"
  create_rmanfile_archive
  if [[ $preview = "yes" || $preview = "Yes" || $preview = "YES" ]]; then
    echo " "
    echo ORACLE ARCHIVE LOG BACKUP RMAN SCRIPT 
    echo " "
    echo "---------------"
    cat $rmanfilear
    echo "---------------"
  else
    archiver
  fi 
else
  create_rmanfile_all
  if [[ $preview = "yes" || $preview = "Yes" || $preview = "YES" ]]; then
    catalog_snapshot
    echo "   "
    echo ORACLE ARCHIVE LOG BACKUP RMAN SCRIPT
    echo "---------------"
    echo " "
    cat $rmanfilea
    echo "---------------"
    echo " "
    echo ORACLE DATABASE BACKUP RMAN SCRIPT
    echo " "
    echo "---------------"
    cat $rmanfiled1
    cat $rmanfiled2
    echo "---------------"
    echo ORACLE CATALOG SNAPSHOT BACKUP FILES BASH SCRIPT
    echo " "
    echo "---------------"
    cat $catalog_bash
    echo "---------------"
    echo Python script to create snapshot
    echo $pyname -v $cohesityname -u $cohesityuser -d $addomain -s /$view/${backup_dir}/datafile -t /$view/${backup_dir}/datafile.$DATE_SUFFIX
    echo "---------------"
  else
    backup1
    backup2
    catalog_snapshot
    archive
    sleep 30
    run_snapshot_catalog
    delete_expired
  fi

  grep -i error $runlog
  
  if [ $? -eq 0 ]; then
     echo "Backup is successful. However there are channels not correct"
     exit 1
  fi

  grep -i failed  $runlog

  if [ $? -eq 0 ]; then
     echo "Some procedures failed. Please review log file $runlog"
     exit 1
  fi

fi

#record timezoneoffset
if [[ -d ${mount}1/$host/$dbname/spfile ]]; then
   ((timezoneoffset=`/bin/date -u '+%Y%m%d%H%M%S'`-`/bin/date '+%Y%m%d%H%M%S'`))
   echo $timezoneoffset > ${mount}1/$host/$dbname/spfile/timezoneoffset-file
fi
