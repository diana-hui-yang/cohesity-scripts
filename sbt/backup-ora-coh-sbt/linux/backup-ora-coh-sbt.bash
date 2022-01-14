#!/bin/bash
#
# Name:         backup-ora-coh-sbt.bash
#
# Function:     This script backup oracle in backup set using Cohesity sbt library. 
#		It can do incremental backup and use Oracle recovery catalog
#		It can do archive log backup only. The retention time is in days.
#		It can also launch RMAN backup from a remote location
#
# Show Usage: run the command to show the usage
#
# Changes:
# 03/07/19 Diana Yang   New script
# 04/04/20 Diana Yang   Allow Oracle sid name has "_" symbol
# 04/04/20 Diana Yang   Better support for RAC database
# 07/21/20 Diana Yang   Improve the code
# 07/21/20 Diana Yang   Add Oracle section size option option
# 07/22/20 Diana Yang   Add option to be able to backup database remotely
# 08/06/20 Diana Yang   Rename this from backup-ora-coh-dedup.bash to backup-ora-coh-sbt.bash
# 08/14/20 Diana Yang   Add more contrains in RAC environment. 
# 10/29/20 Diana Yang   Make database name search not case sensitive.
# 10/30/20 Diana Yang   Standardlize name. Remove "-f" and "-s" as required parameter
# 10/31/20 Diana Yang   Support backing up RAC using nodes supplied by users
# 11/11/20 Diana Yang   Remove the need to manually create vip-list file
# 12/18/20 Diana Yang   Add option to backup the archive logs more than once
# 04/26/21 Diana Yang   Change syntax to use new sbt library
# 05/21/21 Diana Yang   Add a switch for TAG
# 07/23/21 Diana Yang   Add encryption-in-flight
# 09/03/21 Diana Yang   Add an option to use SunRPC
# 09/14/21 Diana Yang   Add an option to turn source side dedupe off and with new SBT library (4.0-sbt_release-20210908_d3530989)
# 10/08/21 Diana Yang   Add an option to manage retention by SBT library
#
#################################################################

function show_usage {
echo "usage: backup-ora-coh-sbt.bash -r <Target connection> -c <Catalog connection> -h <host> -n <rac-node1-conn,rac-node2-conn,...> -o <Oracle_DB_Name> -a <archive only> -i <incremental level> -y <Cohesity-cluster> -f <vip file> -v <view> -s <sbt home> -p <number of channels> -e <retention> -u <retention> -l <archive log keep days> -z <section size> -m <ORACLE_HOME> -w <yes/no> -b <number of archive logs> -t <tag> -g <yes/no> -j <cert path> -x <yes/no> -d <yes/no>"
echo " "
echo " Required Parameters"
echo " -h : host (scanname is required if it is RAC. optional if it is standalone.)"
echo " -o : ORACLE_DB_NAME (Need to have an entry of this database in /etc/oratab. If it is RAC, it is db_unique_name)"
echo " -y : Cohesity Cluster DNS name"
echo " -a : archivelog only backup (yes means archivelog backup only, no means database backup plus archivelog backup, default is no)"
echo " -i : If not archivelog only backup, it is full or incremental backup. 0 is full backup, and 1 is cumulative incremental backup"
echo " -v : Cohesity View that is configured to be the target for Oracle backup"
echo " -u : Retention time (days to retain the backups, expired file are deleted by SBT)"
echo " -e : Retention time (days to retain the backups, expired file are deleted by Oracle. Apply only after uncomment \"Delete obsolete\" in this script)"
echo " "
echo " Optional Parameters"
echo " -r : Target connection (example: \"<dbuser>/<dbpass>@<target connection string> as sysbackup\", optional if it is local backup)"
echo " -c : Catalog connection (example: \"<dbuser>/<dbpass>@<catalog connection string>\", optional)"
echo " -n : Rac nodes connectons strings that will be used to do backup (example: \"<rac1-node connection string,ora2-node connection string>\")"
echo " -p : number of channels (Optional, default is 4)"
echo " -f : The file lists Cohesity Cluster VIPs (default name is vip-list and default directory is config)"
echo " -s : Cohesity SBT library name including directoy or just directory (default name is libsbt_6_and_7_linux-x86_64.so, default directory is lib) "
echo " -l : Archive logs retain days (days to retain the local archivelogs before deleting them. default is 1 day, "no" means not deleting local archivelogs on disk)"
echo " -b : Number of times backing Archive logs (default is 1.)"
echo " -m : ORACLE_HOME (default is /etc/oratab, optional.)"
echo " -z : section size in GB (Optional, default is no section size)"
echo " -t : RMAN TAG"
echo " -g : yes means encryption-in-flight is used. The default is no"
echo " -j : encryption certificate file directory, default directory is lib"
echo " -x : yes means gRPC is used. no means SunRPC is used. The default is yes"
echo " -d : yes means source side dedup is used. The default is yes"
echo " -w : yes means preview rman backup scripts"
echo "

"
echo "Notes: Oracle \"Delete obsolete\" may delete readonly files within the recovery window. It is commented out in default script. 
please read https://support.oracle.com/epmos/faces/DocumentDisplay?parent=DOCUMENT\&sourceId=2245178.1\&id=29633753.8. Uncomment it when you see fit
"
}

while getopts ":r:c:h:n:o:a:i:y:f:v:s:p:e:l:b:z:m:t:g:j:x:d:u:w:" opt; do
  case $opt in
    r ) targetc=$OPTARG;;
    c ) catalogc=$OPTARG;;
    h ) host=$OPTARG;;
    n ) racconns=$OPTARG;;
    o ) dbname=$OPTARG;;
    a ) arch=$OPTARG;;
    i ) level=$OPTARG;;
    y ) cohesityname=$OPTARG;;
    f ) vipfile=$OPTARG;;
    v ) view=$OPTARG;;
    s ) sbtname=$OPTARG;;
    p ) parallel=$OPTARG;;
    e ) retday=$OPTARG;;
    u ) sretday=$OPTARG;;
    l ) archretday=$OPTARG;;
    b ) archcopynum=$OPTARG;;
    z ) sectionsize=$OPTARG;;
    m ) oracle_home=$OPTARG;;
    t ) TAG=$OPTARG;;
    g ) encryption=$OPTARG;;
    j ) encrydir=$OPTARG;;
    x ) grpctype=$OPTARG;;
    d ) sdedup=$OPTARG;;
    w ) preview=$OPTARG;;
  esac
done

#echo ${targetc}, ${catalogc}, $retday, $arch, $dbname, $vipfile, $host, $view

# Check required parameters
if test $dbname && test $view
then
  :
else
  show_usage 
  exit 1
fi

if test $retday || test $sretday
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

if [[ -z $sdedup ]]; then
   sdedup=yes
fi

if [[ -z $grpctype ]]; then
   grpctype=yes
fi

if [[ -z $archretday  ]]; then
  echo "Only retain one day local archive logs"
  archretday=1
fi

echo $archretday

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
  sqllogin="sqlplus / as sysdba"
else
  if [[ $targetc == "/" ]]; then
    echo "It is local backup"
    sqllogin="sqlplus / as sysdba"
  else
    remote="yes"
    cred=`echo $targetc | awk -F @ '{print $1}'`
    conn=`echo $targetc | awk -F @ '{print $2}' | awk '{print $1}'`
    sysbackupy=`echo $targetc | awk -F @ '{print $2}' | awk 'NF>1{print $NF}'`
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

if [[ ! -d $DIR/config ]]; then
  echo " $DIR/config does not exist, create it"
  mkdir -p $DIR/config
  
  if [ $? -ne 0 ]; then
    echo "create log directory $DIR/config failed. There is a permission issue"
    exit 1
  fi
   
fi

if [[ $encryption = [Yy]* ]];then
   echo "This backup will use encryption-in-flight"
   if [[ -z $encrydir ]]; then
      encrydir=$DIR/lib
   fi
    
   echo "encryption certificate directory is $encrydir"
   
   if test -f ${encrydir}/cert.cfg; then
      echo "encrpption certifcate exists, script continue"
   else
      echo "Encryption Certification is not found in directory ${encrydir}. Exit"
      exit 1
   fi
fi

if [[ -z $cohesityname ]]; then
  echo "Cohesity Cluster name is not provided, we will use vipfile"
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
  vipfile=${DIR}/config/${dbname}-vip-list
  echo "Cohesity Cluster name is $cohesityname. VIPS will be collected and stored in $vipfile"
  nslookup $cohesityname | grep -i address | tail -n +2 | awk '{print $2}' > $vipfile
  
  if [[ ! -s $vipfile ]]; then
     echo "Cohesity Cluster name $cohesityname provided here is not in DNS"
     exit 1
  fi

  i=1
  while [ $i -lt $parallel ]; do
    nslookup $cohesityname > /dev/null
    i=$[$i+1]
  done
fi

if [[ -n $sbtname ]]; then
   if [[ $sbtname == *".so" ]]; then
      echo "we will use the sbt library provided $sbtname"
   else  
      echo "This may be a directory"
      sbtname=${sbtname}/libsbt_linux_x86_64.so
      if test ! -f $sbtname; then
 	 sbtname=${sbtname}/libsbt_linux-x86_64.so
         if test ! -f $sbtname; then
            sbtname=${sbtname}/libsbt_6_and_7_linux-x86_64.so
         fi
      fi  
   fi
else
   echo "we assume the sbt library is in $DIR/lib"
   sbtname=${DIR}/lib/libsbt_linux_x86_64.so
   if test ! -f $sbtname; then
      sbtname=${DIR}/lib/libsbt_linux-x86_64.so
      if test ! -f $sbtname; then
        sbtname=${DIR}/lib/libsbt_6_and_7_linux-x86_64.so
      fi
   fi
fi

if test -f $sbtname; then
   echo "file $sbtname exists, script continue"
else
   echo "file $sbtname does not exist. exit"
   exit 1
fi

if [[ -n $sretday ]]; then
   if [[ ! -f $DIR/tools/sbt_list ]]; then
      echo "$DIR/tools/sbt_list file does not exist. Please copy sbt_list tool to $DIR/tools directory before using SBT to delete expired files"
	  exit 1
   fi
   if ! [[ "$sretday" =~ ^[0-9]+$ ]]; then
      echo "$sretday is not an integer. No data expiration after this backup"
      echo "Need to change the parameter after -u to be an integer"
      exit 1
   fi
fi


if [[ $sdedup != [Yy]* ]]; then
   sbt_release_time=` sbttest test -libname $sbtname | grep -i release | awk -F - '{print $3}' | awk -F _ '{print $1}'`
   if [[ $sbt_release_time -lt 20210908 ]]; then 
      echo "
This SBT library $sbtname does not support disable source side dedup 
using syntax "disable_source_side_dedup=true", please download the new SBT library 
from Cohesity support site if you wish to use this function or only use source side dedup
"
      exit 1
   fi
fi
    
#set up log file name
runlog=$DIR/log/$host/$dbname.$DATE_SUFFIX.log
runrlog=$DIR/log/$host/${dbname}.r.$DATE_SUFFIX.log
stdout=$DIR/log/$host/${dbname}.$DATE_SUFFIX.std
sbtlistlog=$DIR/log/$host/${dbname}.sbtlist.$DATE_SUFFIX.log
rmanlog=$DIR/log/$host/$dbname.rman.$DATE_SUFFIX.log
rmanloga=$DIR/log/$host/$dbname.archive.$DATE_SUFFIX.log
rmanlogar=$DIR/log/$host/$dbname.archive_r.$DATE_SUFFIX.log
rmanfiled=$DIR/log/$host/$dbname.rman.$DATE_SUFFIX.rcv
rmanfilea=$DIR/log/$host/$dbname.archive.$DATE_SUFFIX.rcv
rmanfilear=$DIR/log/$host/$dbname.archive_r.$DATE_SUFFIX.rcv


#echo $host $dbname $mount $num

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

which rman

if [ $? -ne 0 ]; then
  echo "oracle home $oracle_home provided or found in /etc/oratab is incorrect"
  exit 1
fi

export NLS_DATE_FORMAT='DD:MM:YYYY-HH24:MI:SS'


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
   else
      echo "rman target connect is successful. Continue"
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
CONFIGURE DEFAULT DEVICE TYPE TO sbt_tape;
CONFIGURE CONTROLFILE AUTOBACKUP ON;
CONFIGURE CONTROLFILE AUTOBACKUP FORMAT FOR DEVICE TYPE sbt_tape TO './$host/$dbname/%d_%F.ctl';
" > $rmanfiled

if [[ -n $retday ]]; then
   if [[ $dbstatus != "readonly" ]]; then
      echo "
CONFIGURE retention policy to recovery window of $retday days;
" >> $rmanfiled
   fi
fi

echo "
CONFIGURE DEFAULT DEVICE TYPE TO sbt_tape;
CONFIGURE CONTROLFILE AUTOBACKUP ON;
CONFIGURE CONTROLFILE AUTOBACKUP FORMAT FOR DEVICE TYPE sbt_tape TO './$host/$dbname/%d_%F.ctl';
" >> $rmanfilea

j=0
k=0
while [ $j -lt $parallel ]; do

    while IFS= read -r ip; do
    
        ip=`echo $ip | xargs`    	
	
	if [[ -n $ip ]]; then
           lastip=$ip
	   
           if [[ $j -eq 1 ]]; then
	      if [[ $encryption = [Yy]* ]]; then
	         if [[ -n $cohesityname ]]; then
	            if [[ $sdedup = [Yy]* && $grpctype = [Yy]* ]]; then
	               echo "CONFIGURE CHANNEL DEVICE TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$cohesityname:/$view,vips=$cohesityname,gflag_name=use_fixed_dedup_chunking,gflag_value=true,sbt_certificate_file=${encrydir}/cert.cfg)' format './$host/$dbname/%d_%T_%U';" >> $rmanfiled
	            elif [[ $sdedup = [Yy]* && $grpctype != [Yy]* ]]; then
		       echo "CONFIGURE CHANNEL DEVICE TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$cohesityname:/$view,vips=$cohesityname,gflag_name=use_fixed_dedup_chunking,gflag_value=true,gflag-name=sbt_use_grpc,gflag-value=false,sbt_certificate_file=${encrydir}/cert.cfg)' format './$host/$dbname/%d_%T_%U';" >> $rmanfiled
		    elif [[ $sdedup != [Yy]* && $grpctype = [Yy]* ]]; then
		       echo "CONFIGURE CHANNEL DEVICE TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$cohesityname:/$view,vips=$cohesityname,disable_source_side_dedup=true,sbt_certificate_file=${encrydir}/cert.cfg)' format './$host/$dbname/%d_%T_%U';" >> $rmanfiled
		    elif [[ $sdedup != [Yy]* && $grpctype != [Yy]* ]]; then
		       echo "CONFIGURE CHANNEL DEVICE TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$cohesityname:/$view,vips=$cohesityname,disable_source_side_dedup=true,gflag-name=sbt_use_grpc,gflag-value=false,sbt_certificate_file=${encrydir}/cert.cfg)' format './$host/$dbname/%d_%T_%U';" >> $rmanfiled
		    fi
		 else
		    if [[ $sdedup = [Yy]* && $grpctype = [Yy]* ]]; then
		       echo "CONFIGURE CHANNEL DEVICE TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,gflag_name=use_fixed_dedup_chunking,gflag_value=true,sbt_certificate_file=${encrydir}/cert.cfg)' format './$host/$dbname/%d_%T_%U';" >> $rmanfiled
	            elif [[ $sdedup = [Yy]* && $grpctype != [Yy]* ]]; then
		       echo "CONFIGURE CHANNEL DEVICE TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,gflag_name=use_fixed_dedup_chunking,gflag_value=true,gflag-name=sbt_use_grpc,gflag-value=false,sbt_certificate_file=${encrydir}/cert.cfg)' format './$host/$dbname/%d_%T_%U';" >> $rmanfiled
		    elif [[ $sdedup != [Yy]* && $grpctype = [Yy]* ]]; then
		       echo "CONFIGURE CHANNEL DEVICE TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,disable_source_side_dedup=true,sbt_certificate_file=${encrydir}/cert.cfg)' format './$host/$dbname/%d_%T_%U';" >> $rmanfiled
		    elif [[ $sdedup != [Yy]* && $grpctype != [Yy]* ]]; then
		       echo "CONFIGURE CHANNEL DEVICE TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,disable_source_side_dedup=true,gflag-name=sbt_use_grpc,gflag-value=false,sbt_certificate_file=${encrydir}/cert.cfg)' format './$host/$dbname/%d_%T_%U';" >> $rmanfiled
		   fi
			 
		 fi
	      else
	         if [[ -n $cohesityname ]]; then
		    if [[ $sdedup = [Yy]* && $grpctype = [Yy]* ]]; then
	               echo "CONFIGURE CHANNEL DEVICE TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$cohesityname:/$view,vips=$cohesityname,gflag_name=use_fixed_dedup_chunking,gflag_value=true)' format './$host/$dbname/%d_%T_%U';" >> $rmanfiled
	            elif [[ $sdedup = [Yy]* && $grpctype != [Yy]* ]]; then
		       echo "CONFIGURE CHANNEL DEVICE TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$cohesityname:/$view,vips=$cohesityname,gflag_name=use_fixed_dedup_chunking,gflag_value=true,gflag-name=sbt_use_grpc,gflag-value=false)' format './$host/$dbname/%d_%T_%U';" >> $rmanfiled
		    elif [[ $sdedup != [Yy]* && $grpctype = [Yy]* ]]; then
		       echo "CONFIGURE CHANNEL DEVICE TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$cohesityname:/$view,vips=$cohesityname,disable_source_side_dedup=true)' format './$host/$dbname/%d_%T_%U';" >> $rmanfiled
		    elif [[ $sdedup != [Yy]* && $grpctype != [Yy]* ]]; then
		       echo "CONFIGURE CHANNEL DEVICE TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$cohesityname:/$view,vips=$cohesityname,disable_source_side_dedup=true,gflag-name=sbt_use_grpc,gflag-value=false)' format './$host/$dbname/%d_%T_%U';" >> $rmanfiled
		    fi
		 else
		    if [[ $sdedup = [Yy]* && $grpctype = [Yy]* ]]; then
		       echo "CONFIGURE CHANNEL DEVICE TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,gflag_name=use_fixed_dedup_chunking,gflag_value=true)' format './$host/$dbname/%d_%T_%U';" >> $rmanfiled
	            elif [[ $sdedup = [Yy]* && $grpctype != [Yy]* ]]; then
		       echo "CONFIGURE CHANNEL DEVICE TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,gflag_name=use_fixed_dedup_chunking,gflag_value=true,gflag-name=sbt_use_grpc,gflag-value=false)' format './$host/$dbname/%d_%T_%U';" >> $rmanfiled
		    elif [[ $sdedup != [Yy]* && $grpctype = [Yy]* ]]; then
		       echo "CONFIGURE CHANNEL DEVICE TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,disable_source_side_dedup=true)' format './$host/$dbname/%d_%T_%U';" >> $rmanfiled
		    elif [[ $sdedup != [Yy]* && $grpctype != [Yy]* ]]; then
		       echo "CONFIGURE CHANNEL DEVICE TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,disable_source_side_dedup=true,gflag-name=sbt_use_grpc,gflag-value=false)' format './$host/$dbname/%d_%T_%U';" >> $rmanfiled
		    fi
		 fi
	      fi
#	      echo "Delete obsolete;" >> $rmanfiled
	      echo "RUN {" >> $rmanfiled
	      echo "RUN {" >> $rmanfilea
	   fi
	   
	   if [[ -n $racconns ]]; then
              if [[ $j -lt $parallel ]]; then
		 if [[ $encryption = [Yy]* ]]; then
		    if [[ $sdedup = [Yy]* && $grpctype = [Yy]* ]]; then
	               allocate_database[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' connect='$cred@${arrconns[$k]}' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,gflag_name=use_fixed_dedup_chunking,gflag_value=true,sbt_certificate_file=${encrydir}/cert.cfg)' format './$host/$dbname/%d_%T_%U.bdf';"
		       allocate_archive[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' connect='$cred@${arrconns[$k]}' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,gflag_name=use_fixed_dedup_chunking,gflag_value=true,sbt_certificate_file=${encrydir}/cert.cfg)' format './$host/$dbname/%d_%T_%U.blf';"
            	    elif [[ $sdedup = [Yy]* && $grpctype != [Yy]* ]]; then
		       allocate_database[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' connect='$cred@${arrconns[$k]}' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,gflag_name=use_fixed_dedup_chunking,gflag_value=true,gflag-name=sbt_use_grpc,gflag-value=false,sbt_certificate_file=${encrydir}/cert.cfg)' format './$host/$dbname/%d_%T_%U.bdf';"
		       allocate_archive[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' connect='$cred@${arrconns[$k]}' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,gflag_name=use_fixed_dedup_chunking,gflag_value=true,gflag-name=sbt_use_grpc,gflag-value=false,sbt_certificate_file=${encrydir}/cert.cfg)' format './$host/$dbname/%d_%T_%U.blf';"
		    elif [[ $sdedup != [Yy]* && $grpctype = [Yy]* ]]; then
                       allocate_database[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' connect='$cred@${arrconns[$k]}' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,disable_source_side_dedup=true,sbt_certificate_file=${encrydir}/cert.cfg)' format './$host/$dbname/%d_%T_%U.bdf';"
		       allocate_archive[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' connect='$cred@${arrconns[$k]}' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,disable_source_side_dedup=true,sbt_certificate_file=${encrydir}/cert.cfg)' format './$host/$dbname/%d_%T_%U.blf';"
            	    elif [[ $sdedup != [Yy]* && $grpctype != [Yy]* ]]; then 
		       allocate_database[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' connect='$cred@${arrconns[$k]}' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,disable_source_side_dedup=true,gflag-name=sbt_use_grpc,gflag-value=false,sbt_certificate_file=${encrydir}/cert.cfg)' format './$host/$dbname/%d_%T_%U.bdf';"
		       allocate_archive[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' connect='$cred@${arrconns[$k]}' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,disable_source_side_dedup=true,gflag-name=sbt_use_grpc,gflag-value=false,sbt_certificate_file=${encrydir}/cert.cfg)' format './$host/$dbname/%d_%T_%U.blf';"
		    fi    
		 else
		    if [[ $sdedup = [Yy]* && $grpctype = [Yy]* ]]; then
		       allocate_database[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' connect='$cred@${arrconns[$k]}' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,gflag_name=use_fixed_dedup_chunking,gflag_value=true)' format './$host/$dbname/%d_%T_%U.bdf';"
                       allocate_archive[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' connect='$cred@${arrconns[$k]}' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,gflag_name=use_fixed_dedup_chunking,gflag_value=true)' format './$host/$dbname/%d_%T_%U.blf';"
		    elif [[ $sdedup = [Yy]* && $grpctype != [Yy]* ]]; then
		       allocate_database[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' connect='$cred@${arrconns[$k]}' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,gflag_name=use_fixed_dedup_chunking,gflag_value=true,gflag-name=sbt_use_grpc,gflag-value=false)' format './$host/$dbname/%d_%T_%U.bdf';"
		       allocate_archive[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' connect='$cred@${arrconns[$k]}' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,gflag_name=use_fixed_dedup_chunking,gflag_value=true,gflag-name=sbt_use_grpc,gflag-value=false)' format './$host/$dbname/%d_%T_%U.blf';"
		    elif [[ $sdedup != [Yy]* && $grpctype = [Yy]* ]]; then
		       allocate_database[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' connect='$cred@${arrconns[$k]}' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,disable_source_side_dedup=true)' format './$host/$dbname/%d_%T_%U.bdf';" 
		       allocate_archive[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' connect='$cred@${arrconns[$k]}' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,disable_source_side_dedup=true)' format './$host/$dbname/%d_%T_%U.blf';"
		    elif [[ $sdedup != [Yy]* && $grpctype != [Yy]* ]]; then
		       allocate_database[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' connect='$cred@${arrconns[$k]}' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,disable_source_side_dedup=true,gflag-name=sbt_use_grpc,gflag-value=false)' format './$host/$dbname/%d_%T_%U.bdf';" 
		       allocate_archive[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' connect='$cred@${arrconns[$k]}' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,disable_source_side_dedup=true,gflag-name=sbt_use_grpc,gflag-value=false)' format './$host/$dbname/%d_%T_%U.blf';"
		    fi
	  	 fi
		 unallocate[j]="release channel c$j;"
	         k=$[$k+1]
	         j=$[$j+1]
              fi
			  
    	      if [[ $k -ge ${#arrconns[@]} && $j -le $parallel ]]; then
	          k=0
	      fi
  	   else
	      if [[ $j -lt $parallel ]]; then
                 if [[ $encryption = [Yy]* ]]; then
		    if [[ $sdedup = [Yy]* && $grpctype = [Yy]* ]]; then
	               allocate_database[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,gflag_name=use_fixed_dedup_chunking,gflag_value=true,sbt_certificate_file=${encrydir}/cert.cfg)' format './$host/$dbname/%d_%T_%U.bdf';"
   	               allocate_archive[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,gflag_name=use_fixed_dedup_chunking,gflag_value=true,sbt_certificate_file=${encrydir}/cert.cfg)' format './$host/$dbname/%d_%T_%U.blf';"
		    elif [[ $sdedup = [Yy]* && $grpctype != [Yy]* ]]; then
		       allocate_database[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,gflag_name=use_fixed_dedup_chunking,gflag_value=true,gflag-name=sbt_use_grpc,gflag-value=false,sbt_certificate_file=${encrydir}/cert.cfg)' format './$host/$dbname/%d_%T_%U.bdf';"
                       allocate_archive[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,gflag_name=use_fixed_dedup_chunking,gflag_value=true,gflag-name=sbt_use_grpc,gflag-value=false,sbt_certificate_file=${encrydir}/cert.cfg)' format './$host/$dbname/%d_%T_%U.blf';"
		    elif [[ $sdedup != [Yy]* && $grpctype = [Yy]* ]]; then
		       allocate_database[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,disable_source_side_dedup=true,sbt_certificate_file=${encrydir}/cert.cfg)' format './$host/$dbname/%d_%T_%U.bdf';"
		       allocate_archive[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,disable_source_side_dedup=true,sbt_certificate_file=${encrydir}/cert.cfg)' format './$host/$dbname/%d_%T_%U.blf';"
		    elif [[ $sdedup != [Yy]* && $grpctype != [Yy]* ]]; then
		       allocate_database[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,disable_source_side_dedup=true,gflag-name=sbt_use_grpc,gflag-value=false,sbt_certificate_file=${encrydir}/cert.cfg)' format './$host/$dbname/%d_%T_%U.bdf';"
		       allocate_archive[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,disable_source_side_dedup=true,gflag-name=sbt_use_grpc,gflag-value=false,sbt_certificate_file=${encrydir}/cert.cfg)' format './$host/$dbname/%d_%T_%U.blf';"
		    fi
         	 else
		    if [[ $sdedup = [Yy]* && $grpctype = [Yy]* ]]; then
	               allocate_database[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,gflag_name=use_fixed_dedup_chunking,gflag_value=true)' format './$host/$dbname/%d_%T_%U.bdf';"
   	               allocate_archive[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,gflag_name=use_fixed_dedup_chunking,gflag_value=true)' format './$host/$dbname/%d_%T_%U.blf';"
		    elif [[ $sdedup = [Yy]* && $grpctype != [Yy]* ]]; then
		       allocate_database[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,gflag_name=use_fixed_dedup_chunking,gflag_value=true,gflag-name=sbt_use_grpc,gflag-value=false)' format './$host/$dbname/%d_%T_%U.bdf';"
		       allocate_archive[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,gflag_name=use_fixed_dedup_chunking,gflag_value=true,gflag-name=sbt_use_grpc,gflag-value=false)' format './$host/$dbname/%d_%T_%U.blf';"
		    elif [[ $sdedup != [Yy]* && $grpctype = [Yy]* ]]; then
		       allocate_database[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,disable_source_side_dedup=true)' format './$host/$dbname/%d_%T_%U.bdf';"
		       allocate_archive[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,disable_source_side_dedup=true)' format './$host/$dbname/%d_%T_%U.blf';"
		    elif [[ $sdedup != [Yy]* && $grpctype != [Yy]* ]]; then
		       allocate_database[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,disable_source_side_dedup=true,gflag-name=sbt_use_grpc,gflag-value=false)' format './$host/$dbname/%d_%T_%U.bdf';"
		       allocate_archive[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,disable_source_side_dedup=true,gflag-name=sbt_use_grpc,gflag-value=false)' format './$host/$dbname/%d_%T_%U.blf';"
		    fi
		 fi
	         unallocate[j]="release channel c$j;"
              fi
              j=$[$j+1]
 	   fi
        fi
    done < $vipfile
done


for (( i=0; i < ${#allocate_database[@]}; i++ )); do
   echo ${allocate_database[$i]} >> $rmanfiled
done

for (( i=0; i < ${#allocate_archive[@]}; i++ )); do
   echo ${allocate_archive[$i]} >> $rmanfilea
done

#echo "crosscheck backup;" >> $rmanfiled
#echo "delete noprompt expired backup;" >> $rmanfiled

if [[ -z $sectionsize ]]; then
   echo "backup INCREMENTAL LEVEL $level CUMULATIVE TAG '$TAG' database filesperset 1;" >> $rmanfiled
else
   echo "backup INCREMENTAL LEVEL $level CUMULATIVE TAG '$TAG' database section size ${sectionsize}G filesperset 1;" >> $rmanfiled
fi
#if [[ $dbstatus != "readonly" ]]; then
#  echo "
#  sql 'alter system switch logfile';
#" >> $rmanfiled
#fi
if [[ $archretday = [Nn]* ]]; then
   echo "backup archivelog all filesperset 8 not backed up $archcopynum times;" >> $rmanfilea
elif [[ $archretday -eq 0 ]]; then
   echo "backup archivelog all filesperset 8 not backed up $archcopynum times delete input;" >> $rmanfilea
else
   echo "backup archivelog all filesperset 8 not backed up $archcopynum times archivelog until time 'sysdate-$archretday' delete input;" >> $rmanfilea
fi

for (( i=0; i < ${#unallocate[@]}; i++ )); do
   echo ${unallocate[$i]} >> $rmanfiled
   echo ${unallocate[$i]} >> $rmanfilea
done

echo "} 
 BACKUP CURRENT CONTROLFILE format './$host/$dbname/%d_%T_%U.ctl';
 exit;" >> $rmanfiled
echo "}
 exit;" >> $rmanfilea

echo "finished creating rman file" >> $runlog
echo "finished creating rman file"
}

function create_rmanfile_archive {

echo "Create rman file" >> $runrlog

echo "
CONFIGURE DEFAULT DEVICE TYPE TO sbt_tape;
CONFIGURE CONTROLFILE AUTOBACKUP ON;
CONFIGURE CONTROLFILE AUTOBACKUP FORMAT FOR DEVICE TYPE sbt_tape TO './$host/$dbname/%d_%F.ctl';

RUN {
" > $rmanfilear

i=1
j=0
while [ $j -lt $parallel ]; do

    while IFS= read -r ip; do
    
        ip=`echo $ip | xargs`    	
	if [[ -n $ip ]]; then
	   	
           if [[ $j -lt $parallel ]]; then
	      if [[ $encryption = [Yy]* ]]; then
		 if [[ $sdedup = [Yy]* && $grpctype = [Yy]* ]]; then
	            allocate_archive[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,gflag_name=use_fixed_dedup_chunking,gflag_value=true,sbt_certificate_file=${encrydir}/cert.cfg)' format './$host/$dbname/%d_%T_%U.blf';"
 	         elif [[ $sdedup = [Yy]* && $grpctype != [Yy]* ]]; then
		    allocate_archive[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,gflag_name=use_fixed_dedup_chunking,gflag_value=true,gflag-name=sbt_use_grpc,gflag-value=false,sbt_certificate_file=${encrydir}/cert.cfg)' format './$host/$dbname/%d_%T_%U.blf';"
		 elif [[ $sdedup != [Yy]* && $grpctype = [Yy]* ]]; then
		    allocate_archive[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,disable_source_side_dedup=true,sbt_certificate_file=${encrydir}/cert.cfg)' format './$host/$dbname/%d_%T_%U.blf';"
		 elif [[ $sdedup != [Yy]* && $grpctype != [Yy]* ]]; then
		    allocate_archive[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,disable_source_side_dedup=true,gflag-name=sbt_use_grpc,gflag-value=false,sbt_certificate_file=${encrydir}/cert.cfg)' format './$host/$dbname/%d_%T_%U.blf';"
		 fi
	      else
	         if [[ $sdedup = [Yy]* && $grpctype = [Yy]* ]]; then
	            allocate_archive[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,gflag_name=use_fixed_dedup_chunking,gflag_value=true)' format './$host/$dbname/%d_%T_%U.blf';"
	         elif [[ $sdedup = [Yy]* && $grpctype != [Yy]* ]]; then
		    allocate_archive[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,gflag_name=use_fixed_dedup_chunking,gflag_value=true,gflag-name=sbt_use_grpc,gflag-value=false)' format './$host/$dbname/%d_%T_%U.blf';"
		 elif [[ $sdedup != [Yy]* && $grpctype = [Yy]* ]]; then
		    allocate_archive[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,disable_source_side_dedup=true)' format './$host/$dbname/%d_%T_%U.blf';"
		 elif [[ $sdedup != [Yy]* && $grpctype != [Yy]* ]]; then
		    allocate_archive[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,disable_source_side_dedup=true,gflag-name=sbt_use_grpc,gflag-value=false)' format './$host/$dbname/%d_%T_%U.blf';"
		 fi
	      fi
	      unallocate[j]="release channel c$j;"  
           fi
           i=$[$i+1]
           j=$[$j+1]
	fi
    done < $vipfile
done

for (( i=0; i < ${#allocate_archive[@]}; i++ )); do
   echo ${allocate_archive[$i]} >> $rmanfilear
done

if [[ $archretday = [Nn]* ]]; then
   echo "backup archivelog all filesperset 8 not backed up $archcopynum times;" >> $rmanfilear
elif [[ $archretday -eq 0 ]]; then
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

function backup {

echo "Database backup started at " `/bin/date '+%Y%m%d%H%M%S'`
echo "Database backup started at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog

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
  while IFS= read -r ip
  do
    echo $ip
  done < $rmanlog 
  exit 1
else
  echo "Database backup finished at " `/bin/date '+%Y%m%d%H%M%S'`
  echo "Database backup finished at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog 
fi

if [[ $dbstatus != "readonly" ]]; then
rman << EOF
connect target '${targetc}'
sql 'alter system switch logfile';
exit
EOF
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

grep -i error $rmanloga

if [ $? -eq 0 ]; then
   echo "Backup is successful. However there are channels not correct"
#   exit 1
else
   echo "Backup is successful."
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
#   exit 1
else
   echo "Backup is successful."
fi
}

function delete_expired {
  
#let sretnewday=$sretday+1
let sretnewday=$sretday
echo "Clean backup files older than $sretnewday started at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog
echo "Clean backup files older than $sretnewday started at " `/bin/date '+%Y%m%d%H%M%S'` >> $sbtlistlog
echo "only delete old expired backup during database backup" >> $runlog
if [[ -n $cohesityname ]]; then
   $DIR/tools/sbt_list --view=$view/$host/$dbname --vips=$cohesityname --purge_view=true --days_before=$sretnewday --silent_mode=true >> $sbtlistlog
else
   $DIR/tools/sbt_list --view=$view/$host/$dbname --vips=$lastip --purge_view=true --days_before=$sretnewday --silent_mode=true >> $sbtlistlog
fi
#echo $DIR/tools/sbt_list --view=$view/$host/$dbname --vips=$lastip --purge_view=true --days_before=$sretnewday --silent_mode=true
if [ $? -eq 0 ]; then
   echo "Clean backup files older than $sretnewday finished at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog
   echo "Clean backup files older than $sretnewday finished at " `/bin/date '+%Y%m%d%H%M%S'` >> $sbtlistlog
else
   echo "Clean backup files older than $sretnewday failed at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog
   echo "Clean backup files older than $sretnewday failed at " `/bin/date '+%Y%m%d%H%M%S'` >> $sbtlistlog
fi 
}

setup

echo "
the backup script runs on `hostname -s` and in directory $DIR 

oracle database server is $host
"
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
  grep -i error $runrlog

  if [ $? -eq 0 ]; then
    echo "Backup may be successful. However there are IPs in $vipfile not reachable"
 #  exit 1
  fi
else
  echo "backup database plus archive logs"
  create_rmanfile_all
  if [[ $preview = "yes" || $preview = "Yes" || $preview = "YES" ]]; then
    echo "   "
    echo ORACLE ARCHIVE LOG BACKUP RMAN SCRIPT
    echo " "
    echo "---------------"
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
	if [[ -n $sretday ]]; then
	   delete_expired
	fi
  fi
  grep -i error $runlog

  if [ $? -eq 0 ]; then
    echo "Backup may be successful. However there are IPs in $vipfile not reachable"
#  exit 1
  fi
fi
