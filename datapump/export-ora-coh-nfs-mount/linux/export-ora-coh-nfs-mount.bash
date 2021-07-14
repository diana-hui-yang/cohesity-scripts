#!/bin/bash
#
# Name:         export-ora-coh-nfs-mount.bash
#
# Function:     This script export Oracle database using nfs mount. 
#		 
#
# Show Usage: run the command to show the usage
#
# Changes:
# 07/06/21 Diana Yang   New script
# 07/09/21 Diana Yang   Add RAC support
# 07/12/21 Diana Yang   Add PDB support
# 07/12/21 Diana Yang   Provide DBA an option to add their own export command
# 07/12/21 Diana Yang   Allow permanent mount
#
#################################################################

function show_usage {
echo "usage: export-ora-coh-nfs-mount.bash -s <Sqlplus connection> -h <host> -o <Oracle_sid> -d <PDB database> -y <Cohesity-cluster> -v <view> -m <mount-prefix> -n <number of mounts> -p <number of paralles> -e <retention> -z <file size> -x <ORACLE_HOME> -c <export options> -a <yes/no> -w <yes/no>"
echo " "
echo " Required Parameters"
echo " -h : host (scanname is required if it is RAC. optional if it is standalone.)"
echo " -o : ORACLE_DB_NAME (Need to have an entry of this database in /etc/oratab. If it is RAC, it is db_unique_name)"
echo " -y : Cohesity Cluster DNS name"
echo " -v : Cohesity View that is configured to be the target for Oracle export"
echo " -m : mount-prefix (like /mnt/ora)"
echo " -e : Retention time (days to retain the exports)"
echo " "
echo " Optional Parameters"
echo " -s : Sqlplus connection (example: \"<dbuser>/<dbpass>@<database connection string>\", optional if it is local)"
echo " -d : ORACLE PDB database"
echo " -n : number of mounts"
echo " -p : number of parallel (Optional, default is 4)"
echo " -a : yes means leave Cohesity NFS mount on server, default is umount all NFS mount after export is successful"
echo " -x : ORACLE_HOME (default is /etc/oratab, optional.)"
echo " -z : file size in GB (Optional, default is 58G)"
echo " -c : Export option chosen by DBA. It can be table level or schema level. example \"schemas=soe1\" The default is full"
echo " -w : yes means preview rman backup scripts"
echo "
"
}

while getopts ":s:h:o:d:y:v:m:n:p:a:e:z:x:c:w:" opt; do
  case $opt in
    s ) sqlplusc=$OPTARG;;
    h ) host=$OPTARG;;
    o ) dbname=$OPTARG;;
    d ) pdbname=$OPTARG;;
    y ) cohesityname=$OPTARG;;
    v ) view=$OPTARG;;
    m ) mount=$OPTARG;;
    n ) num=$OPTARG;;
    p ) parallel=$OPTARG;;
    a ) perm=$OPTARG;;
    e ) retday=$OPTARG;;
    z ) filesize=$OPTARG;;
    x ) oracle_home=$OPTARG;;
    c ) dba_exp_option=$OPTARG;;
    w ) preview=$OPTARG;;
  esac
done

#echo $mount, $dbname, $num

# Check required parameters
if test $mount && test $dbname && test $view && test $retday
then
  :
else
  show_usage 
  exit 1
fi


function setup {
if test $host
then
  hostdefinded=yes
else
  host=`hostname -s`
fi

orauser=`whoami`

if test $parallel
then
  :
else
  echo "no input for parallel, set parallel to be 4."
  parallel=4
fi

if test $filesize
then
  :
else
  echo "no input for filesize, set parallel to be 50."
  filesize=50
fi

if [[ -z $sqlplusc ]]; then
  sqllogin="sqlplus -s / as sysdba"
  exportlogin="expdp \'/ as sysdba\'"
else
  if [[ $sqlplusc == "/" ]]; then
    echo "It is local backup"
    sqllogin="sqlplus -s / as sysdba"
    exportlogin="expdp \'/ as sysdba\'"
  else
    remote="yes"
    cred=`echo $sqlplusc | awk -F @ '{print $1}'`
    conn=`echo $sqlplusc | awk -F @ '{print $2}' | awk '{print $1}'`
    sqllogin="sqlplus ${sqlplusc}"
    exportlogin="expdp \'$cred@$conn\'"	
  fi
fi

#echo sqlplus connection is ${sqlplusc}


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
script_name=`echo $DIRcurrent | awk -F "/" '{print $NF}'`


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
stdout=$DIR/log/$host/${dbname}.$DATE_SUFFIX.std
dbadir=$DIR/log/$host/$dbname.dba_directories.$DATE_SUFFIX.log
#expdplogdir=$DIR/log/$host
expdpfile=$DIR/log/$host/$dbname.expdp.$DATE_SUFFIX.sql

#echo $host $oracle_sid $mount $num

#trim log directory
find $DIR/log/$host -type f -mtime +7 -exec /bin/rm {} \;

if [ $? -ne 0 ]; then
  echo "del old logs in $DIR/log/$host failed" >> $runlog
  echo "del old logs in $DIR/log/$host failed"
  exit 2
fi

if [[ $remote != "yes" ]]; then
  echo "check whether this database is up running on $host"
  runoid=`ps -ef | grep pmon | awk 'NF>1{print $NF}' | grep -i $dbname | awk -F "pmon" '{print $2}' | sort -t _ -k 1`

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

if [[ -n $pdbname ]]; then
  export ORACLE_PDB_SID=$pdbname
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
    orasidintab=`echo ${arrinfo[$i]} | awk -F ":" '{print $1}'`
    orasidintab=${orasidintab,,}
    orahomeintab=`echo ${arrinfo[$i]} | awk -F ":" '{print $2}'`
  
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
      orasidintab=`echo ${arrinfo[$i]} | awk -F ":" '{print $1}'`
      orasidintab=${orasidintab,,}
      orahomeintab=`echo ${arrinfo[$i]} | awk -F ":" '{print $2}'`
  
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

if [ $? -ne 0 ]; then
  echo "oracle home $oracle_home provided or found in /etc/oratab is incorrect"
  exit 1
fi

export NLS_DATE_FORMAT='DD:MM:YYYY-HH24:MI:SS'

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

function create_rac_host_file {

if [[ ! -d $DIR/config ]]; then
  echo " $DIR/config does not exist, create it"
  mkdir -p $DIR/config
  
  if [ $? -ne 0 ]; then
    echo "create log directory $DIR/config failed. There is a permission issue"
    exit 1
  fi
   
fi

if [[ -n $host ]]; then
  
  nslookup $host | grep -i address | tail -n +2 | awk '{print $2}' > ${DIR}/config/rac-list
  
  if [[ ! -s ${DIR}/config/rac-list ]]; then
    echo "Oracle host provided here is not in DNS"
    exit 1
  fi

fi

currenthost=`hostname -s`

hostnum=`grep -v -e '^$' ${DIR}/config/rac-list | wc -l | awk '{print $1}'`

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
  nslookup $cohesityname | grep -i address | tail -n +2 | awk '{print $2}' > $vipfile
  
  if [[ ! -s $vipfile ]]; then
    echo "Cohesity Cluster name $cohesityname provided here is not in DNS"
    exit 1
  fi

fi

if [[ -z $num ]]; then
  num=`grep -v -e '^$' $vipfile | wc -l | awk '{print $1}'`
else
  numnode=`grep -v -e '^$' $vipfile | wc -l | awk '{print $1}'`
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

      if [[ $hostnum -gt 1 ]]; then
         while IFS= read -r nodename; do
	     ssh ${orauser}@$nodename << EOF
	     if [[ ! -d ${mount}$j ]]; then
                 echo "Directory ${mount}${j} does not exist, create it"
                 if sudo mkdir -p ${mount}${j}; then
                     echo "directory ${mount}${j} is created"
                 else
                     echo "creating directory ${mount}${j}. There is a permission issue"
                     exit 1
                 fi
              fi
EOF
	 done < ${DIR}/config/rac-list
      else
         if [[ ! -d ${mount}$j ]]; then
             echo "Directory ${mount}${j} does not exist, create it"
             if sudo mkdir -p ${mount}${j}; then
                echo "directory ${mount}${j} is created"
             else
                echo "creating directory ${mount}${j}. There is a permission issue"
                exit 1
             fi
          fi 
      fi

# check whether this mount point is being used   
	 
      if [[ $hostnum -gt 1 ]]; then
          while IFS= read -r nodename; do
	     mount_cnt=`ssh ${orauser}@$nodename << EOF
	     df -h ${mount}$j | grep -wc "${mount}$j$"
EOF
`
#             echo  what is mount_cnt $mount_cnt

# If not mounted, mount this IP	to the mountpoint
             if [[ "$mount_cnt" -lt 1 ]]; then
                echo "== "
                echo "mount point ${mount}$j is not mounted on host $nodename. Mount it at" `/bin/date '+%Y%m%d%H%M%S'`
                ssh ${orauser}@$nodename << EOF
                if sudo mount -o intr,hard,rsize=1048576,wsize=1048576,proto=tcp,vers=3,nolock $ip:/${view} ${mount}$j; then
                   echo "mount ${mount}${j} is sucessfull at " `/bin/date '+%Y%m%d%H%M%S'`
                   if [[ $j -eq 0 ]]; then
	              sudo chown ${ownerarr[0]}:${ownerarr[1]} ${mount}${j}
	              sudo chmod -R 770 ${mount}$j
                   fi
                else
                   echo "mount ${mount}${j} on host $nodename failed at " `/bin/date '+%Y%m%d%H%M%S'`
                   exit 1
                fi  
EOF
             else      
                echo "== "
                echo "mount point ${mount}$j on host $nodename is already mounted"	   
             fi
          done < ${DIR}/config/rac-list
      else
          mount_cnt=`df -h ${mount}$j | grep -wc "${mount}$j$"`

# If not mounted, mount this IP	to the mountpoint
          if [[ "$mount_cnt" -lt 1 ]]; then
             echo "== "
             echo "mount point ${mount}$j is not mounted. Mount it at" `/bin/date '+%Y%m%d%H%M%S'`
             if sudo mount -o intr,hard,rsize=1048576,wsize=1048576,proto=tcp,vers=3,nolock $ip:/${view} ${mount}$j; then
                echo "mount ${mount}${j} is sucessfull at " `/bin/date '+%Y%m%d%H%M%S'`
                if [[ $j -eq 0 ]]; then
                   sudo chown ${ownerarr[0]}:${ownerarr[1]} ${mount}${j}
#	              sudo chmod -R 770 ${mount}$j
                fi
             else
                echo "mount ${mount}${j} failed at " `/bin/date '+%Y%m%d%H%M%S'`
                exit 1
             fi  
          else      
             echo "== "
             echo "mount point ${mount}$j is already mounted"	   
          fi 
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
        if [[ $hostnum -gt 1 ]]; then
           while IFS= read -r nodename; do
	      mount_cnt=`ssh ${orauser}@$nodename << EOF
              df -h ${mount}$j | grep -wc "${mount}$j$"
EOF
`

# If mounted, umount this IP	to the mountpoint
              if [[ "$mount_cnt" -ge 1 ]]; then
                 echo "== "
                 echo "mount point ${mount}$j is mounted on host $nodename. umount it at" `/bin/date '+%Y%m%d%H%M%S'`
                 ssh ${orauser}@$nodename << EOF
                 if sudo umount ${mount}$j; then
                    echo "umount ${mount}${j} on host $nodename is sucessfull at " `/bin/date '+%Y%m%d%H%M%S'`
                 else
                    echo "umount ${mount}${j} on host $nodename failed at " `/bin/date '+%Y%m%d%H%M%S'`	 
                 fi
EOF
              else
                 echo "mount point ${mount}$j on host $nodename is not mounted"
              fi
           done < ${DIR}/config/rac-list
        else
           mount_cnt=`df -h ${mount}$j | grep -wc "${mount}$j$"`

# If mounted, umount this IP	to the mountpoint
           if [[ "$mount_cnt" -ge 1 ]]; then
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
        fi		   
        j=$[$j+1]		
     fi
   done < $vipfile
fi

}

function create_export_file {

echo "Create or replace directory"  >> $runlog

i=1
j=0
echo "num is $num"
while [[ $i -le $num ]]; do

  mount_cnt=`df -h ${mount}$i | grep -wc "${mount}$i$"`
#  echo $mount_cnt
  
  if [ "$mount_cnt" -eq 1 ]; then
     echo "$mount${i} is mount point"
     echo " "
	
     if [[ ! -d "${mount}${i}/exports/${dbname}" ]]; then
        echo "Directory ${mount}${i}/exports/${dbname} does not exist, create it"
        if mkdir -p ${mount}${i}/exports/${dbname}; then
          echo "${mount}${i}/exports is created"
        else
          echo "creating ${mount}${i}/exports/${dbname} failed. There is a permission issue"
          exit 1
        fi
     fi
	
    
     if [[ $j -lt $parallel ]]; then
		
#	grep -i EXPDP_COH$i $dbadir
  
#       if [ $? -eq 1 ]; then
#          echo "Export directory expdp_coh$i has not been created yet, creating now"
        echo "Creating or replace directory expdp_coh$i" 
        $sqllogin << EOF
        create or replace directory EXPDP_COH$i as '${mount}${i}/exports/${dbname}';
        exit
EOF
        if [ $? -eq 0 ]; then
           echo "dba_directories expdp_coh$i in Oracle was created successfully" >> $runlog
	   echo "dba_directories expdp_coh$i in Oracle  was created successfully"
	else
	   echo "dba_directories expdp_coh$i in Oracle failed to be created" >> $runlog
  	   echo "dba_directories expdp_coh$i in Oracle failed to be created"
	fi
#        else
#          echo "Export directory expdp_coh$i has been created already" 
#        fi
    
	if [[ -n $pdbname ]]; then
       if [[ -n $dba_exp_option ]]; then
           exportpath[$j]="EXPDP_COH${i}:expdp${j}_${pdbname}_dba_%U_${DATE_SUFFIX}.dmp"
       else		   
	       exportpath[$j]="EXPDP_COH${i}:expdp${j}_${pdbname}_full_%U_${DATE_SUFFIX}.dmp"
	   fi
        else
	   if [[ -n $dba_exp_option ]]; then
           exportpath[$j]="EXPDP_COH${i}:expdp${j}_${dbname}_dba_%U_${DATE_SUFFIX}.dmp"
	   else		   
	       exportpath[$j]="EXPDP_COH${i}:expdp${j}_${dbname}_full_%U_${DATE_SUFFIX}.dmp"
	   fi
        fi
     fi
		
     i=$[$i+1]
     j=$[$j+1]

     if [[ $i -gt $num && $j -le $parallel ]]; then 
        i=1
     fi
  else
     echo "$mount${i} is not a mount point. Backup will not start
     The mount prefix may not be correct or
     The input of the number of mount points may exceed the actuall number of mount points"
     exit 1
  fi

done

expdplogdir=${mount}1/exports/${dbname}
$sqllogin << EOF
create or replace directory EXPDP_COH_LOG as '${expdplogdir}';
exit
EOF

if [ $? -eq 0 ]; then
  echo "dba_directories expdp_coh_log in Oracle was created successfully" >> $runlog
  echo "dba_directories expdp_coh_log in Oracle  was created successfully"
else
  echo "dba_directories expdp_coh_log in Oracle failed to be created" >> $runlog
  echo "dba_directories expdp_coh_log in Oracle failed to be created"
fi

# query and save the directory
${sqllogin} << EOF
  spool $dbadir
  SET LINES 300
  col DIRECTORY_NAME format a20
  col DIRECTORY_PATH format a100
  select DIRECTORY_NAME, DIRECTORY_PATH from dba_directories
  where lower(DIRECTORY_NAME)like 'expdp_coh%';
  spool off
  exit
EOF


#echo "parallel is $parallel"
#echo "exportpath array length is ${#exportpath[@]}"

echo "#export database ${dbname}" > $expdpfile
expcmd="${exportlogin} dumpfile=${exportpath[0]}"
for (( i=1; i < ${#exportpath[@]}; i++ )); do
   expcmd="${expcmd},${exportpath[$i]}"
done

if [[ -n $pdbname ]]; then
   if [[ -n $dba_exp_option ]]; then
       expcmd="${expcmd} LOGFILE=EXPDP_COH_LOG:dba.expdp.${DATE_SUFFIX}.log ${dba_exp_option} FILESIZE=${filesize}G PARALLEL=$parallel"
   else
       expcmd="${expcmd} LOGFILE=EXPDP_COH_LOG:${pdbname}.expdp.${DATE_SUFFIX}.log FULL=Y FILESIZE=${filesize}G content=all PARALLEL=$parallel"
   fi
else
   if [[ -n $dba_exp_option ]]; then
       expcmd="${expcmd} LOGFILE=EXPDP_COH_LOG:dba.expdp.${DATE_SUFFIX}.log ${dba_exp_option} FILESIZE=${filesize}G PARALLEL=$parallel"   
   else
       expcmd="${expcmd} LOGFILE=EXPDP_COH_LOG:${dbname}.expdp.${DATE_SUFFIX}.log FULL=Y FILESIZE=${filesize}G content=all PARALLEL=$parallel" 
   fi
fi
echo ${expcmd} >> $expdpfile

chmod 750 $expdpfile
}


function export_database {

echo "Database export started at " `/bin/date '+%Y%m%d%H%M%S'`
echo "Database export started at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog

$expdpfile

if [ $? -ne 0 ]; then
  echo "Database export failed at " `/bin/date '+%Y%m%d%H%M%S'`
  echo "Database export failed at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog
  while IFS= read -r line
  do
    echo $line
  done < $expdpfile
  exit 1
else
  echo "Database export finished at " `/bin/date '+%Y%m%d%H%M%S'`
  echo "Database export finished at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog
#  if [[ -n $pdbname ]];then
#     cp ${expdplogdir}/${pdbname}.expdp.${DATE_SUFFIX}.log ${mount}1/exports/${dbname}
#  else
#     cp ${expdplogdir}/${dbname}.expdp.${DATE_SUFFIX}.log ${mount}1/exports/${dbname}
#  fi
fi

}

function delete_expired {

if ! [[ "$retday" =~ ^[0-9]+$ ]]; then
  echo "$retday is not an integer. No data expiration after this export"
  exit 1
  echo "Need to change the parameter after -e to be an integer"
else
  let retnewday=$retday+1
  echo "Clean export files older than $retnewday started at " `/bin/date '+%Y%m%d%H%M%S'`
  echo "Clean export files older than $retnewday started at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog
  echo "only delete old expired export during database export" >> $runlog
  if [[ -d "${mount}1/exports" ]]; then
    find ${mount}1/exports -type f -mtime +$retnewday -exec /bin/rm -f {} \;
    find ${mount}1/exports -depth -type d -empty -exec rmdir {} \;
  fi
  echo "Clean export files older than $retnewday finished at " `/bin/date '+%Y%m%d%H%M%S'`
  echo "Clean export files older than $retnewday finished at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog 
fi

}

setup

create_rac_host_file
create_vipfile
mount_coh


create_export_file
if [[ $preview = "yes" || $preview = "Yes" || $preview = "YES" ]]; then
  echo "   "
  echo ORACLE EXPORT SCRIPT
  echo "---------------"
  echo " "
  cat $expdpfile
  echo "---------------"   
else
  export_database
  delete_expired
fi

if [[ $perm = [Yy]* ]]; then
   echo "leave NFS mounts as they are"
else
   sleep 5
   echo "umount NFS mount"
   umount_coh
fi
