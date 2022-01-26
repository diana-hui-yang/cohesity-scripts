#!/bin/bash
#
# Name:         aix-backup-ora-coh-nfs-mount.bash
#
# Function:     This script backup oracle in backup set using nfs mount. 
#		It can do incremental backup and use Oracle recovery catalog
#		It can do archive log backup only. The retention time is in days.
#		If the retention time is unlimit, specify unlimit. It only deletes
#		the backup files. It won't clean RMMAN catalog. Oracle cleans its 
# 		RMAN catalog. 
#
# Show Usage: run the command to show the usage
#
# Changes:
# 01/29/21 Diana Yang   Modify Linux script to work in AIX
# 01/29/21 Diana Yang   change "awk" to "/opt/freeware/bin/gawk". change "df -h" to "df -g". 
# 01/29/21 Diana Yang   change "find" to "/opt/freeware/bin/find"
# 05/21/21 Diana Yang   Add option to backup the archive logs more than once
# 05/21/21 Diana Yang   Add a switch for TAG
#
#################################################################

function show_usage {
echo "usage: aix-backup-ora-coh-nfs-mount.bash -r <Target connection> -c <Catalog connection> -h <host> -d <rac-node1-conn,rac-node2-conn,...> -o <Oracle_sid> -a <archive only> -i <incremental level> -y <Cohesity-cluster> -v <view> -m <mount-prefix> -n <number of mounts> -p <number of channels> -e <retention> -l <archive log keep days> -z <section size> -x <ORACLE_HOME> -w <yes/no> -b <number of archive logs> -t <tag>"
echo " "
echo " Required Parameters"
echo " -h : host (scanname is required if it is RAC. optional if it is standalone.)"
echo " -o : ORACLE_DB_NAME (Need to have an entry of this database in /etc/oratab. If it is RAC, it is db_unique_name)"
echo " -a : yes (yes means archivelog backup only, no means database backup plus archivelog backup, no is optional)"
echo " -i : If not archive only, it is full or incremental backup. 0 is full backup, and 1 is cumulative incremental backup"
echo " -y : Cohesity Cluster DNS name"
echo " -v : Cohesity View that is configured to be the target for Oracle backup"
echo " -m : mount-prefix (like /mnt/ora)"
echo " -e : Retention time (days to retain the backups)"
echo " "
echo " Optional Parameters"
echo " -r : Target connection (example: \"<dbuser>/<dbpass>@<target connection string> as sysbackup\", optional if it is local backup)"
echo " -c : Catalog connection (example: \"<dbuser>/<dbpass>@<catalog connection string>\", optional)"
echo " -d : Rac nodes connectons strings that will be used to do backup (example: \"<rac1-node connection string,ora2-node connection string>\")"
echo " -n : number of mounts"
echo " -p : number of channels (Optional, default is 4)"
echo " -l : Archive logs retain days (days to retain the local archivelogs before deleting them. default is 1 day)"
echo " -b : Number of times backing Archive logs (default is 1.)"
echo " -x : ORACLE_HOME (default is /etc/oratab, optional.)"
echo " -z : section size in GB (Optional, default is no section size)"
echo " -t : RMAN TAG"
echo " -w : yes means preview rman backup scripts"
echo "
"
}

while getopts ":r:c:h:d:o:a:i:y:v:m:n:p:e:l:b:z:x:t:w:" opt; do
  case $opt in
    r ) targetc=$OPTARG;;
    c ) catalogc=$OPTARG;;
    h ) host=$OPTARG;;
    d ) racconns=$OPTARG;;
    o ) dbname=$OPTARG;;
    a ) arch=$OPTARG;;
    i ) level=$OPTARG;;
    y ) cohesityname=$OPTARG;;
    v ) view=$OPTARG;;
    m ) mount=$OPTARG;;
    n ) num=$OPTARG;;
    p ) parallel=$OPTARG;;
    e ) retday=$OPTARG;;
    l ) archretday=$OPTARG;;
    b ) archcopynum=$OPTARG;;
    z ) sectionsize=$OPTARG;;
    x ) oracle_home=$OPTARG;;
    t ) TAG=$OPTARG;;
    w ) preview=$OPTARG;;
  esac
done

echo $mount, $dbname, $retday, $view, $num

# Check required parameters
if test $mount && test $dbname && test $retday
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

  if test $level
  then
    :
  else
    echo "incremental level was not specified"
    echo " "
    show_usage 
    exit 1
  fi
  
  if [[ $level -ne 0 && $level -ne 1 ]]; then
    echo "incremental level is set to be $level. Backup won't start"
    echo "incremental backup level needs to be either 0 or 1"
    echo " "
    show_usage 
    exit 1
  fi
fi

if [[ -z $TAG ]]; then
   if [[ $level -eq 0 ]]; then
     TAG=full
   else
     TAG=incremental
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
  host=`hostname -s`
fi

if test $parallel
then
  :
else
  echo "no input for parallel, set parallel to be 4."
  parallel=4
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
  sqllogin="sqlplus -s / as sysdba"
else
  if [[ $targetc == "/" ]]; then
    echo "It is local backup"
    sqllogin="sqlplus -s / as sysdba"
  else
    remote="yes"
    cred=`echo $targetc | /opt/freeware/bin/gawk -F @ '{print $1}'`
    conn=`echo $targetc | /opt/freeware/bin/gawk -F @ '{print $2}' | /opt/freeware/bin/gawk '{print $1}'`
    sysbackupy=`echo $targetc | /opt/freeware/bin/gawk -F @ '{print $2}' | /opt/freeware/bin/gawk 'NF>1{print $NF}'`
    if [[ -z $sysbackupy ]]; then
       sqllogin="sqlplus -s ${cred}@${conn} as sysdba"
    else
       sqllogin="sqlplus -s ${cred}@${conn} as sysbackup"
    fi
  fi
fi

echo target connection is ${targetc}

echo "rmanlogin is \"$rmanlogin\""
echo "rmanlogin syntax can be like \"rman target /\" or"
#echo "\"rman target '\"sysbackup/<password>@<database connect string> as sysbackup\"' \""
echo "\"rman target sys/<password>@<database connect string> catalog <user>/<password>@<catalog>\""

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
script_name=`echo $DIRcurrent | /opt/freeware/bin/gawk -F "/" '{print $NF}'`

if test $view || test $num
then
  :
else
  show_usage 
  exit 1
fi

if [[ -n $view ]]; then
   if [[ -z $cohesityname ]]; then
      echo "Cohesity name is not provided. Check vip-list file" 
      if [[ ! -f $DIR/config/vip-list ]]; then
        echo "can't find $DIR/config/vip-list file. Please provide cohesity name or populate $DIR/config/vip-list with Cohesity VIPs"
        echo " "
        show_usage
        exit 1
      fi
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

runlog=$DIR/log/$host/$dbname.$DATE_SUFFIX.log
runrlog=$DIR/log/$host/${dbname}.r.$DATE_SUFFIX.log
stdout=$DIR/log/$host/${dbname}.$DATE_SUFFIX.std
rmanlog=$DIR/log/$host/$dbname.rman.$DATE_SUFFIX.log
rmanlogs=$DIR/log/$host/$dbname.spfile.$DATE_SUFFIX.log
rmanloga=$DIR/log/$host/$dbname.archive.$DATE_SUFFIX.log
rmanlogar=$DIR/log/$host/$dbname.archive_r.$DATE_SUFFIX.log
rmanfiled=$DIR/log/$host/$dbname.rman.$DATE_SUFFIX.rcv
rmanfilea=$DIR/log/$host/$dbname.archive.$DATE_SUFFIX.rcv
rmanfilear=$DIR/log/$host/$dbname.archive_r.$DATE_SUFFIX.rcv

#echo $host $oracle_sid $mount $num

#trim log directory
/opt/freeware/bin/find $DIR/log/$host/${dbname}* -type f -mtime +7 -exec /opt/freeware/bin/rm {} \;
/opt/freeware/bin/find $DIR/log/$host -type f -mtime +14 -exec /opt/freeware/bin/rm {} \;

if [ $? -ne 0 ]; then
  echo "del old logs in $DIR/log/$host failed" >> $runlog
  echo "del old logs in $DIR/log/$host failed"
  exit 2
fi

if [[ $remote != "yes" ]]; then
  echo "check whether this database is up running on $host"
  runoid=`ps -ef | grep pmon | /opt/freeware/bin/gawk 'NF>1{print $NF}' | grep -i $dbname | /opt/freeware/bin/gawk -F "pmon" '{print $2}' | sort -t _ -k 1`

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

# get ORACLE_HOME in /etc/oratab if it is not provided in input

if [[ -z $oracle_home ]]; then

#change dbname to lowercase
  dbname=${dbname,,}
  oratabinfo=`grep -i $dbname /etc/oratab`

#echo oratabinfo is $oratabinfo
  
  arrinfo=($oratabinfo)
  leninfo=${#arrinfo[@]}

  k=0
  for (( i=0; i<$leninfo; i++))
  do
    orasidintab=`echo ${arrinfo[$i]} | /opt/freeware/bin/gawk -F ":" '{print $1}'`
    orasidintab=${orasidintab,,}
    orahomeintab=`echo ${arrinfo[$i]} | /opt/freeware/bin/gawk -F ":" '{print $2}'`
  
    if [[ $orasidintab == ${dbname} ]]; then    
       oracle_home=$orahomeintab
       export ORACLE_HOME=$oracle_home
       export PATH=$PATH:$ORACLE_HOME/bin
       k=1   
    fi
#   echo orasidintab is $orasidintab
  done

  if [[ $k -eq 0 ]]; then
    oratabinfo=`grep -i ${dbname::${#dbname}-1} /etc/oratab`
    arrinfo=($oratabinfo)
    leninfo=${#arrinfo[@]}
	
    j=0
    for (( i=0; i<$leninfo; i++))
    do
      orasidintab=`echo ${arrinfo[$i]} | /opt/freeware/bin/gawk -F ":" '{print $1}'`
      orasidintab=${orasidintab,,}
      orahomeintab=`echo ${arrinfo[$i]} | /opt/freeware/bin/gawk -F ":" '{print $2}'`
  
      if [[ $orasidintab == ${dbname} ]]; then    
        oracle_home=$orahomeintab
        export ORACLE_HOME=$oracle_home
        export PATH=$PATH:$ORACLE_HOME/bin
        j=1   
      fi
    done
	
    if [[ $j -eq 0 ]]; then
       echo "No Oracle db_unique_name $dbname information in /etc/oratab. Will check whether ORACLE_HOME is set"
       if [[ ! -d $ORACLE_HOME ]]; then	     
         echo "No Oracle db_unique_name $dbname information in /etc/oratab and ORACLE_HOME is not set"
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

owner=`ls -ld $ORACLE_HOME | awk '{print $3 " " $4}'`
ownerarr=($owner)

which rman

if [ $? -ne 0 ]; then
  echo "oracle home $oracle_home provided or found in /etc/oratab is incorrect"
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

function create_vipfile {

if [[ ! -d $DIR/config ]]; then
  echo " $DIR/config does not exist, create it"
  mkdir -p $DIR/config
  
  if [ $? -ne 0 ]; then
    echo "create log directory $DIR/config failed. There is a permission issue"
    exit 1
  fi
   
fi

if [[ -z $cohesityname ]]; then
  echo "Cohesity Cluster name is not provided, we will use vipfile"
  vipfile=${DIR}/config/vip-list
else
  vipfile=${DIR}/config/${dbname}-vip-list
  echo "Cohesity Cluster name is $cohesityname. VIPS will be collected and stored in $vipfile"
  nslookup $cohesityname | grep -i address | tail -n +2 | /opt/freeware/bin/gawk '{print $2}' > $vipfile 
  
  if [[ ! -s $vipfile ]]; then
    echo "Cohesity Cluster name $cohesityname provided here is not in DNS"
    exit 1
  fi
 
fi

if [[ -z $num ]]; then
  num=`grep -v -e '^$' $vipfile | wc -l | /opt/freeware/bin/gawk '{print $1}'`
else
  numnode=`grep -v -e '^$' $vipfile | wc -l | /opt/freeware/bin/gawk '{print $1}'`
  if [[ $num -ge $numnode ]]; then
     num=$numnode
  fi
fi

}

function mount_coh {

echo "mount Cohesity view if they are not mounted yet"
j=1
while IFS= read -r ip; do
    
   ip=`echo $ip | xargs`   
	  
   if [[ $j -le $num ]]; then
# check whether mountpoint exist

     if [[ ! -d ${mount}$j ]]; then
       echo "Directory ${mount}${j} does not exist, create it"
       if sudo mkdir -p ${mount}${j}; then
         echo "directory ${mount}${j} is created"
       else
         echo "creating directory ${mount}${j}. There is a permission issue"
         exit 1
       fi
     fi

# check whether this mount point is being used

     mount_cnt=`df -g ${mount}$j | grep -wc "${mount}$j$"`

# If not mounted, mount this IP	to the mountpoint
     if [ "$mount_cnt" -lt 1 ]; then
       echo "== "
       echo "mount point ${mount}$j is not mounted. Mount it at" `/bin/date '+%Y%m%d%H%M%S'`
       echo "sudo mount -o rw,bg,hard,intr,rsize=524288,wsize=524288,vers=3,proto=tcp,sec=sys,llock,noac $ip:/${view} ${mount}$j"
       if sudo mount -o rw,bg,hard,intr,rsize=524288,wsize=524288,vers=3,proto=tcp,sec=sys,llock,noac $ip:/${view} ${mount}$j; then
          echo "mount ${mount}${j} is sucessfull at " `/bin/date '+%Y%m%d%H%M%S'`
	  sudo chown ${ownerarr[0]}:${ownerarr[1]} ${mount}${j}
#          sudo chmod 777 ${mount}$j
       else
          echo "mount ${mount}${j} failed at " `/bin/date '+%Y%m%d%H%M%S'`
          exit 1
       fi  
     else      
       echo "== "
       echo "mount point ${mount}$j is already mounted"	   
     fi
     j=$[$j+1]
   fi
     
done < $vipfile   

}

function umount_coh {

# check whether any backup using this script is running 
#ps -ef | grep -w ${script_name}
status=`ps -ef | grep -w ${script_name} |wc -l`
echo "status=$status"
if [ "$status" -gt 3 ]; then
   echo "== "
   echo " ${script_name} is still running at " `/bin/date '+%Y%m%d%H%M%S'`
   echo " will not run umount"
else
   echo "== "
   echo " will umount Cohesity NFS mountpoint"
   j=1
   while IFS= read -r ip; do
    
     ip=`echo $ip | xargs`
	 
	  
     if [[ $j -le $num ]]; then
	 
        mount_cnt=`df -g ${mount}$j | grep -wc "${mount}$j$"`

# If mounted, umount this IP	to the mountpoint
        if [ "$mount_cnt" -ge 1 ]; then
           echo "== "
	   echo "mount point ${mount}$j is mounted. umount it at" `/bin/date '+%Y%m%d%H%M%S'`
           if sudo umount ${mount}$j; then
              echo "umount ${mount}${j} is sucessfull at " `/bin/date '+%Y%m%d%H%M%S'`
           else
              echo "umount ${mount}${j} failed at " `/bin/date '+%Y%m%d%H%M%S'`	 
           fi
	else
           echo "mount point ${mount}$j is not mounted"
        fi
        j=$[$j+1]	
     fi
   done < $vipfile
fi

}

function create_rmanfile_all {

echo "Create rman file" >> $runlog

echo "
CONFIGURE DEFAULT DEVICE TYPE TO disk;
CONFIGURE CONTROLFILE AUTOBACKUP ON;
CONFIGURE CONTROLFILE AUTOBACKUP FORMAT FOR DEVICE TYPE DISK TO '${mount}1/$host/$dbname/controlfile/%d_%F.ctl';
CONFIGURE retention policy to recovery window of $retday days;
" > $rmanfiled
#echo "Delete obsolete;" >> $rmanfiled
echo " 
RUN {
" >> $rmanfiled

echo "
CONFIGURE DEFAULT DEVICE TYPE TO disk;
CONFIGURE CONTROLFILE AUTOBACKUP ON;
CONFIGURE CONTROLFILE AUTOBACKUP FORMAT FOR DEVICE TYPE DISK TO '${mount}1/$host/$dbname/controlfile/%d_%F.ctl';

RUN {
" >> $rmanfilea

i=1
j=0
k=0
echo "num is $num"
while [[ $i -le $num ]]; do
  mountstatus=`mount | grep -i  "${mount}${i}"`
  if [[ -n $mountstatus ]]; then
    echo "$mount${i} is mount point"
    echo " "
	
    if [[ ! -d "${mount}${i}/$host/$dbname/datafile.${DATE_SUFFIX}" ]]; then
       echo "Directory ${mount}${i}/$host/$dbname/datafile.${DATE_SUFFIX} does not exist, create it"
       if mkdir -p ${mount}${i}/$host/$dbname/datafile.${DATE_SUFFIX}; then
          echo "${mount}${i}/$host/$dbname/datafile.${DATE_SUFFIX} is created"
       else
          echo "creating ${mount}${i}/$host/$dbname/datafile.${DATE_SUFFIX} failed. There is a permission issue"
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
          allocate_database[$j]="allocate channel fs$j device type disk connect='$cred@${arrconns[$k]}' format = '$mount$i/$host/$dbname/datafile.${DATE_SUFFIX}/%d_%T_%U.bdf';"
          allocate_archive[$j]="allocate channel fs$j device type disk connect='$cred@${arrconns[$k]}' format = '$mount$i/$host/$dbname/archivelog/%d_%T_%U.blf';"
          unallocate[j]="release channel fs$j;"
       fi

       i=$[$i+1]
       j=$[$j+1]
       k=$[$k+1]

       if [[ $k -ge ${#arrconns[@]} && $j -le $parallel ]]; then 
          k=0
       fi
	  
       if [[ $i -gt $num && $j -le $parallel ]]; then 
          i=1
       fi
    else
      if [[ $j -lt $parallel ]]; then
         allocate_database[$j]="allocate channel fs$j device type disk format = '$mount$i/$host/$dbname/datafile.${DATE_SUFFIX}/%d_%T_%U.bdf';"
         allocate_archive[$j]="allocate channel fs$j device type disk format = '$mount$i/$host/$dbname/archivelog/%d_%T_%U.blf';"
         unallocate[j]="release channel fs$j;"
      fi

      i=$[$i+1]
      j=$[$j+1]

      if [[ $i -gt $num && $j -le $parallel ]]; then 
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
   echo ${allocate_database[$i]} >> $rmanfiled
done

for (( i=0; i < ${#allocate_archive[@]}; i++ )); do
   echo ${allocate_archive[$i]} >> $rmanfilea
done

if [[ -z $sectionsize ]]; then
   echo "backup INCREMENTAL LEVEL $level CUMULATIVE TAG '$TAG' database filesperset 1;" >> $rmanfiled
else
   echo "backup INCREMENTAL LEVEL $level CUMULATIVE TAG '$TAG' database section size ${sectionsize}G filesperset 1;" >> $rmanfiled
fi

if [[ $archretday -eq 0 ]]; then
   echo "backup archivelog all not backed up $archcopynum times delete input;" >> $rmanfilea
else
   echo "backup archivelog all not backed up $archcopynum times archivelog until time 'sysdate-$archretday' delete input;" >> $rmanfilea
fi

for (( i=0; i < ${#unallocate[@]}; i++ )); do
   echo ${unallocate[$i]} >> $rmanfiled
   echo ${unallocate[$i]} >> $rmanfilea
done

echo " 
}
" >> $rmanfiled
#echo "
#crosscheck backup;
#delete noprompt expired backup;
#" >> $rmanfiled
echo "
exit;
" >> $rmanfiled
echo "
}
exit;
" >> $rmanfilea

echo "finished creating rman file" >> $runlog
echo "finished creating rman file"
}
function create_rmanfile_archive {

echo "
CONFIGURE DEFAULT DEVICE TYPE TO disk;
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
    echo "$mount${i} is mount point"
    echo " "
	
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
       allocate_archive[$j]="allocate channel fs$j device type disk format = '$mount$i/$host/$dbname/archivelog/%d_%T_%U.blf';"
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
   echo "backup archivelog all not backed up $archcopynum times delete input;" >> $rmanfilear
else
   echo "backup archivelog all not backed up $archcopynum times archivelog until time 'sysdate-$archretday' delete input;" >> $rmanfilear
fi

for (( i=0; i < ${#unallocate[@]}; i++ )); do
   echo ${unallocate[$i]} >> $rmanfilear
done

echo "}
exit;" >> $rmanfilear

echo "finished creating rman file" >> $runrlog
echo "finished creating rman file"
}

function backup {

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
EOF
else
   rman log $rmanlogs << EOF
   connect target '${targetc}'
   connect catalog '${catalogc}'
   BACKUP AS COPY SPFILE format '${mount}1/$host/$dbname/spfile/spfile%d.%T_%U.ora';
EOF
fi

  
if [[ -z $catalogc ]]; then
   rman log $rmanlog << EOF
   connect target '${targetc}'
   @$rmanfiled
EOF
else
   rman log $rmanlog << EOF
   connect target '${targetc}'
   connect catalog '${catalogc}'
   @$rmanfiled
EOF
fi

if [ $? -ne 0 ]; then
  echo "Database backup failed at " `/bin/date '+%Y%m%d%H%M%S'`
  echo "Database backup failed at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog
  while IFS= read -r line
  do
    echo $line
  done < $rmanlog 
  exit 1
else
  echo "Database backup finished at " `/bin/date '+%Y%m%d%H%M%S'`
  echo "Database backup finished at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog 
fi

rman << EOF
connect target '${targetc}'
sql 'alter system switch logfile';
exit
EOF

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
  echo "Archive logs backup failed at " `/bin/date '+%Y%m%d%H%M%S'`
  echo "Archive logs backup failed at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog
  while IFS= read -r line
  do
    echo $line
  done < $rmanloga 
  exit 1
else
  echo "Archive logs backup finished at " `/bin/date '+%Y%m%d%H%M%S'`
  echo "Archive logs backup finished at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog 
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
  echo "Archive logs backup failed at " `/bin/date '+%Y%m%d%H%M%S'`
  echo "Archive logs backup failed at " `/bin/date '+%Y%m%d%H%M%S'` >> $runrlog
  while IFS= read -r line
  do
    echo $line
  done < $rmanlogar
  exit 1
else
  echo "Archive logs backup finished at " `/bin/date '+%Y%m%d%H%M%S'`
  echo "Archive logs backup finished at " `/bin/date '+%Y%m%d%H%M%S'` >> $runrlog 
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
  let retnewday=$retday+1
  echo "Clean backup files older than $retnewday started at " `/bin/date '+%Y%m%d%H%M%S'`
  echo "Clean backup files older than $retnewday started at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog
  echo "only delete old expired backup during database backup" >> $runlog
  if [[ -d "${mount}1/$host/$dbname" ]]; then
    /opt/freeware/bin/find ${mount}1/$host/$dbname -type f -mtime +$retnewday -exec /bin/rm -vf {} \; >> $runlog
    /opt/freeware/bin/find ${mount}1/$host/$dbname -depth -type d -empty -exec rmdir -v {} \; >> $runlog
  fi
  echo "Clean backup files older than $retnewday finished at " `/bin/date '+%Y%m%d%H%M%S'`
  echo "Clean backup files older than $retnewday finished at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog 
fi

}

function skip_noarchive_db {

$sqllogin << EOF > $stdout
   select '=='||LOG_MODE AA from v\$database;
EOF

grep -wc "==NOARCHIVELOG" $stdout

if [ $? -eq 0 ]; then
   echo "Checking whether database $dbname is in archivelog mode or not started at " `/bin/date '+%Y%m%d%H%M%S'`
   echo "Checking whether database $dbname is in archivelog mode or not started at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog
   echo "$dbname is in NOARCHIVELOG, skip the backup."
   echo "$dbname is in NOARCHIVELOG, skip the backup." >> $runlog
   exit
fi

echo "Checking whether database $dbname is in archivelog mode or not started at " `/bin/date '+%Y%m%d%H%M%S'`
echo "Checking whether database $dbname is in archivelog mode or not started at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog
echo "$dbname is in ARCHIVELOG, start the backup."
echo "$dbname is in ARCHIVELOG, start the backup." >> $runlog

}


setup
skip_noarchive_db
if [[ -n $view ]]; then
   create_vipfile
   mount_coh
fi

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
    cat $rmanfiled
    echo "---------------"
  else
    backup
    archive
    delete_expired
  fi

  grep -i error $runlog
  
  if [ $? -eq 0 ]; then
     echo "Backup is successful. However there are channels not correct"
     exit 1
  fi

fi

if [[ -n $view && -n $vipfile ]]; then
   sleep 5 
   umount_coh
fi
