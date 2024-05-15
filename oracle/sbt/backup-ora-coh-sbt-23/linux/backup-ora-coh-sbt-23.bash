#!/bin/bash
#
# Name:         backup-ora-coh-sbt-23.bash
#
# Function:     This script backs up the Oracle database in backupset format using the Cohesity SBT library. 
#		It should be used in conjunction with a Cohesity ZDLRA-type view. It can do incremental backup and 
#		use Oracle recovery catalog, It can do archive log backup only. It can also launch RMAN backup 
#		from a remote location.
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
# 09/01/22 Diana Yang   Check whether database is RAC or not.
# 10/05/22 Diana Yang   Add the backup level number to the names of backupset.
# 11/29/22 Diana Yang   Add offline and full backup option.
# 01/22/23 Diana Yang   Add Synchronizing the backup with oracle control file record or recovery catalog record option
# 01/25/23 Diana Yang   Use new syntax, use Cohesity Policy to manage retention, and simplify the steps
# 08/17/23 Diana Yang   Check any pdb database is in mount mode and added it to the output
#
#################################################################

umask 036

function show_usage {
echo "usage: backup-ora-coh-sbt-23.bash -r <Target connection> -c <Catalog connection> -h <host> -n <rac-node1-conn,rac-node2-conn,...> -o <Oracle_DB_Name> -a <archive only> -i <incremental level> -y <Cohesity-cluster> -f <vip file> -v <view> -e <catalog view> -s <sbt home> -p <number of channels> -l <archive log keep days> -z <section size> -k <RMAN compression yes/no> -m <ORACLE_HOME> -w <yes/no> -b <number of archive logs> -t <tag> -g <yes/no> -j <cert path or name> -x <yes/no> -d <yes/no> -q <yes/no>"
echo " "
echo " Required Parameters"
echo " -h : host (scanname is required if it is RAC. optional if it is standalone.)"
echo " -o : ORACLE_DB_NAME (Need to have an entry of this database in /etc/oratab. If it is RAC, it is db_name)"
echo " -y : Cohesity Cluster DNS name"
echo " -a : archivelog only backup (yes means archivelog backup only, no means database backup plus archivelog backup, default is no)"
echo " -i : If not archivelog only backup, it is full or incremental backup. 0 is full backup, and 1 is cumulative incremental backup, offline is offline full backup"
echo " -v : Cohesity View that is configured to be the target for Oracle backup"
echo " -e : Cohesity View that is configured to be the Cohesity catalog for Oracle backup"
echo " "
echo " Optional Parameters"
echo " -r : Target connection (example: \"<dbuser>/<dbpass>@<target connection string> as sysbackup\", optional if it is local backup)"
echo " -c : Catalog connection (example: \"<dbuser>/<dbpass>@<catalog connection string>\", optional)"
echo " -n : Rac nodes connectons strings that will be used to do backup (example: \"<rac1-node connection string,ora2-node connection string>\")"
echo " -p : number of channels (Optional, default is 4)"
echo " -f : The file lists Cohesity Cluster VIPs (default name is vip-list and default directory is config)"
echo " -s : Cohesity SBT library name including directoy or just directory (default name is libsbt_linux_x86_64.so, default directory is lib) "
echo " -l : Archive logs retain days (days to retain the local archivelogs before deleting them. default is 1 day, "no" means not deleting local archivelogs on disk)"
echo " -b : Number of times backing Archive logs (default is 1.)"
echo " -m : ORACLE_HOME (default is /etc/oratab, optional.)"
echo " -z : section size in GB (Optional, default is no section size)"
echo " -t : RMAN TAG"
echo " -k : RMAN compression (Optional, yes means RMAN compression. no means no RMAN compression. default is no)"
echo " -g : yes means encryption-in-flight is used. The default is no"
echo " -j : encryption certificate file directory, default directory is lib"
echo " -x : yes means gRPC is used. no means SunRPC is used. The default is yes"
echo " -d : yes means source side dedup is used. The default is yes"
echo " -q : yes means sbt activity record are recorded in sbtio.log. no means only errors are recorded in sbtio.log. The default is yes"
echo " -w : yes means preview rman backup scripts"
echo " "

}

while getopts ":r:c:h:n:o:a:i:y:f:v:e:s:p:l:b:z:k:m:t:g:j:x:d:q:w:" opt; do
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
    e ) cata_view=$OPTARG;;
    s ) sbtname=$OPTARG;;
    p ) parallel=$OPTARG;;
    l ) archretday=$OPTARG;;
    b ) archcopynum=$OPTARG;;
    z ) sectionsize=$OPTARG;;
    m ) oracle_home=$OPTARG;;
    t ) TAG=$OPTARG;;
    g ) encryption=$OPTARG;;
    j ) encrydir=$OPTARG;;
    x ) grpctype=$OPTARG;;
    k ) compression=$OPTARG;;
    d ) sdedup=$OPTARG;;
    q ) sbtiolog=$OPTARG;;
    w ) preview=$OPTARG;;
  esac
done

#echo ${targetc}, ${catalogc},$arch, $dbname, $vipfile, $host, $view

# Check required parameters
# check whether "\" is in front of "
fullcommand=($@)
lencommand=${#fullcommand[@]}
#echo $lencommand
i=0
for (( i=0; i<$lencommand; i++ ))
do
   if [[ ${fullcommand[$i]} == *\"* ]]; then
      echo " \ shouldn't be part of input. Please remove \."
      exit 2 
   fi
done

# check some input syntax
i=0
for (( i=0; i<$lencommand; i++ ))
do
   if [[ ${fullcommand[$i]} == -a ]]; then
      archset=yes
   fi
done
if [[ -n $archset ]]; then
   if [[ -z $arch ]]; then
      echo "Please enter 'yes' as the argument for -a. It may be empty or not all options are given an argument. All options should be given an arguments"
      exit 2
   else
      if [[ $arch != [Yy]* ]]; then
         echo "'yes' or 'Yes' should be provided after -a in syntax, other answer is not valid"
	 exit 2
      fi
   fi 
fi

i=0
for (( i=0; i<$lencommand; i++ ))
do
   if [[ ${fullcommand[$i]} == -g ]]; then
      encryptionset=yes
   fi
done
if [[ -n $encryptionset ]]; then
   if [[ -z $encryption ]]; then
      echo "Please enter 'yes' as the argument for -g. It may be empty or not all options are given an argument. All options should be given an arguments"
      exit 2
   else
      if [[ $encryption != [Yy]* && $encryption != [Nn]* ]]; then
         echo "'yes' or 'no' should be provided after -g in syntax, other answer is not valid"
	 exit 2
      fi
   fi 
fi

i=0
for (( i=0; i<$lencommand; i++ ))
do
   if [[ ${fullcommand[$i]} == -x ]]; then
      grpctypeset=yes
   fi
done
if [[ -n $grpctypeset ]]; then
   if [[ -z $grpctype ]]; then
      echo "Please enter 'yes' as the argument for -x. It may be empty or not all options are given an argument. All options should be given an arguments"
      exit 2
   else
      if [[ $grpctype != [Yy]* && $grpctype != [Nn]* ]]; then
         echo "'yes' or 'no' should be provided after -x in syntax, other answer is not valid"
	 exit 2
      fi
   fi 
fi

i=0
for (( i=0; i<$lencommand; i++ ))
do
   if [[ ${fullcommand[$i]} == -d ]]; then
      sdedupset=yes
   fi
done
if [[ -n $sdedupset ]]; then
   if [[ -z $sdedup ]]; then
      echo "Please enter 'yes' as the argument for -d. It may be empty or not all options are given an argument. All options should be given an arguments"
      exit 2
   else
      if [[ $sdedup != [Yy]* && $sdedup != [Nn]* ]]; then
         echo "'yes' or 'no' should be provided after -d in syntax, other answer is not valid"
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
      echo "Please enter 'yes' as the argument for -w. It may be empty or not all options are given an argument. All options should be given an arguments"
      exit 2
   else
      if [[ $preview != [Yy]* ]]; then
         echo "'yes' should be provided after -w in syntax, other answer is not valid"
	 exit 2
      fi 
   fi
fi

i=0
for (( i=0; i<$lencommand; i++ ))
do
   if [[ ${fullcommand[$i]} == -q ]]; then
      sbtiologset=yes
   fi
done
if [[ -n $sbtiologset ]]; then
   if [[ -z $sbtiolog ]]; then
      echo "Please enter 'yes' as the argument for -q. It may be empty or not all options are given an argument. All options should be given an arguments"
      exit 2
   else
      if [[ $sbtiolog != [Yy]* && $sbtiolog != [Nn]* ]]; then
         echo "'yes' or 'no' should be provided after -q in syntax, other answer is not valid"
	 exit 2
      fi
   fi 
fi

if [[ -z $sbtiolog ]]; then
   sbtiolog=yes
fi

i=0
for (( i=0; i<$lencommand; i++ ))
do
   if [[ ${fullcommand[$i]} == -k ]]; then
      compressionset=yes
   fi
done
if [[ -n $compressionset ]]; then
   if [[ -z $compression ]]; then
      echo "Please enter 'yes' as the argument for -k. It may be empty or not all options are given an argument. All options should be given an arguments"
      exit 2
   else
      if [[ $compression != [Yy]* && $compression != [Nn]* ]]; then
         echo "'yes' or 'no' should be provided after -k in syntax, other answer is not valid"
	 exit 2
      fi
   fi 
fi

if [[ -z $compression ]]; then
   compression=no
fi


if test $view && test $cata_view
then
  if [[ $cata_view != [A-Za-z]* ]]; then
     echo "The argument for -e is catalog view. It should be the view name, not a digit"
     exit 1
  fi 
else
  show_usage 
  exit 1
fi


if test $dbname || test "$targetc"
then
  :
else
  show_usage 
  exit 1
fi


DATE_SUFFIX=`/bin/date '+%Y%m%d%H%M%S'`
#echo $DATE_SUFFIX

if [[ $arch = "arch" || $arch = "Arch" || $arch = "ARCH" || $arch = "yes" || $arch = "Yes" || $arch = "YES" ]]; then
  echo "Only backup archive logs"
  archivelogonly=yes
else
  echo "Will backup database backup plus archive logs"

  if test $level
  then
    :
  else
    echo "Backup type was not specified. The options are offline, full, 0, or 1."
    echo " "
    exit 1
  fi
  

  if [[ $level != "offline" && $level != "full" ]]; then
     echo "This may be incremental backup"
     if [[ $level -ne 0 && $level -ne 1 ]]; then
       echo "incremental level is set to be $level. Backup won't start"
       echo "incremental backup level needs to be either 0, or 1"
       echo " "
       exit 1
     fi
     if [[ $level == [A-Za-z]* ]]; then
        echo "Not incremental backup"
        echo "Backup type $level specified is not correct. It needs to be offline of full"
        exit 1
     fi
  fi
fi

if [[ -z $TAG ]]; then
   if [[ $level -eq 0 || $level = "offline" || $level = "full" ]]; then
     TAG=full_${DATE_SUFFIX}
   else
     TAG=incremental_${DATE_SUFFIX}
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
  IFS=', ' read -r -a oldarrconns <<< "$racconns"
  if [[ -z $targetc ]]; then
    echo "RAC database connection information is missing. It is input after -r"
    exit 1
  fi
  echo  RAC connection is $racconns
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
    systype=`echo $targetc | awk -F @ '{print $2}' | awk 'NF>1{print $NF}'`
    if [[ -z $hostdefinded ]]; then
       if [[ $conn =~ '/' ]]; then
          host=`echo $conn | awk -F '/' '{print $1}'`
          if [[ $host =~ ':' ]]; then
	     host=`echo $host | awk -F ':' '{print $1}'`
	  fi
       fi
    fi
    if [[ -z $systype ]]; then
       systype=sysdba
    fi
    sqllogin="sqlplus ${cred}@${conn} as $systype"
    if [[ -z $dbname ]]; then
       if [[ $conn =~ '/' ]]; then
          dbname=`echo $conn | awk -F '/' 'NF>1{print $NF}'`
       else
          dbname=$conn
       fi
    fi
  fi
fi

echo target connection is ${targetc}

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
   
   if [[ -f $encrydir ]]; then
      encrycert=$encrydir
   else  
      echo "encryption certificate directory is $encrydir"
   
      if test -f ${encrydir}/cert.cfg; then
         echo "encrpption certifcate exists, script continue"
	 encrycert=${encrydir}/cert.cfg
      elif test -f ${encrydir}/ora_sbt_cert.cfg; then
         echo "encrpption certifcate exists, script continue"
	 encrycert=${encrydir}/ora_sbt_cert.cfg
      else
         echo "Encryption Certification is not found in directory ${encrydir}. Exit"
         exit 1
      fi
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
   echo "file ${DIR}/lib/libsbt_linux_x86_64.so does not exist. exit"
   exit 1
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
expirelog=$DIR/log/$host/$dbname.expire.$DATE_SUFFIX.log
archive_tag=archive_${DATE_SUFFIX}
ctl_tag=ctl_${DATE_SUFFIX}


#echo $host $dbname $mount $num

#trim log directory
find $DIR/log/$host/${dbname}* -type f -mtime +7 -exec /bin/rm {} \;
find $DIR/log/$host -type f -mtime +14 -exec /bin/rm {} \;

#if [ $? -ne 0 ]; then
#  echo "del old logs in $DIR/log/$host failed" >> $runlog
#  echo "del old logs in $DIR/log/$host failed"
#  exit 2
#fi

# get ORACLE_HOME in /etc/oratab if it is not provided in input

if [[ -z $oracle_home ]]; then

#change dbname to lowercase
#  dbname=${dbname,,}

  oratabinfo=`grep -i $dbname /etc/oratab`

#echo oratabinfo is $oratabinfo

  arrinfo=($oratabinfo)
  leninfo=${#arrinfo[@]}

  k=0
  for (( i=0; i<$leninfo; i++))
  do
    orasidintab=`echo ${arrinfo[$i]} | awk -F ":" '{print $1}'`
#    orasidintab=${orasidintab,,}
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

if [[ $remote != "yes" ]]; then
  echo "check whether this database is up running on $host"
  j=0
  
  export ORACLE_SID=$dbname
  #check whether the database is RAC database or not
  $sqllogin << EOF > /dev/null
   spool $stdout replace
   select name, value from v\$parameter where name='cluster_database';
EOF
  if grep -i "ORA-01034" $stdout > /dev/null; then
    echo "Oracle database $dbname may be a RAC or not running"
# get oracle instance name. For a RAC database, the instance has a numerical number after the database name. 
    runoid=`ps -ef | grep pmon | awk 'NF>1{print $NF}' | grep -i $dbname | awk -F "pmon" '{print $2}' | sort -t _ -k 1`
    arroid=($runoid)
    len=${#arroid[@]}

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
              export ORACLE_SID=$oracle_sid
	      $sqllogin << EOF > /dev/null
               spool $stdout replace
               select name, value from v\$parameter where name='cluster_database';
EOF
              if grep -i "true" $stdout; then
	         echo "Oracle database $dbname is a RAC database"
		    if [[ -z $hostdefinded ]]; then
		       echo "This is RAC environment, scanname should be provided after -h option"
                       echo "  "
                       exit 2
                    else
		       echo "Oracle RAC database $dbname instance $oracle_sid is up on $host. Backup can start"
                       yes_oracle_sid=$oracle_sid
    	               j=1
		    fi
	      else
	         echo "Oracle database $oracle_sid is a standalone database, not the same database as $dbname."
		 echo "Oracle database $dbname is not up on $host. Backup will not start on $host"
		 exit 2
 	      fi
           fi
        fi 
      fi
    done
  else
    echo "Oracle database $dbname is up on $host. Backup can start"
    yes_oracle_sid=$dbname
    j=1
  fi

  if [[ $j -eq 0 ]]; then
    echo "Oracle database $dbname is not up on $host. Backup will not start on $host"
    exit 2
  fi
  echo ORACLE_SID is $yes_oracle_sid
  export ORACLE_SID=$yes_oracle_sid
fi


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

# Get db_name defined in database
$sqllogin << EOF > /dev/null
   spool $stdout replace
   select name from v\$database;
EOF

if [ $? -ne 0 ]; then
   echo "Some part of this connection string \"$sqllogin\" is incorrect"
   exit 1
fi


i=0
while IFS= read -r line
do
  if [[ $i -eq 1 ]]; then
     db_name=`echo $line | xargs`
     i=$[$i+1]
  fi
  if [[ $line =~ "-" ]];then
     i=$[$i+1]
  fi
done < $stdout


$sqllogin << EOF > /dev/null
   spool $stdout replace
   select database_role from v\$database;
EOF
    
grep -i "standby" $stdout
if [ $? -eq 0 ]; then
   echo "Database is a standby database"
   dbstatus=standby
else
   dbstatus=normal
fi

k=0
j=0
if [[ -n $racconns ]]; then
   echo the number of connection is ${#oldarrconns[@]}
   while [ $k -lt ${#oldarrconns[@]} ]; do
       echo sqllogin1="sqlplus $cred@${oldarrconns[$k]} as $systype"
       sqllogin1="sqlplus $cred@${oldarrconns[$k]} as $systype"
       rm $stdout
       $sqllogin1 << EOF > /dev/null
       spool $stdout replace
       select name from v\$database;
EOF
       if grep -i $db_name $stdout > /dev/null; then
	  echo "connection string ${oldarrconns[$k]} is valid"
	  arrconns[$j]=${oldarrconns[$k]}
	  j=$[$j+1]
       else
          echo "connection string ${oldarrconns[$k]} is not valid or the instance is down, the backup will not use this connection string"
       fi
       k=$[$k+1]
   done
   echo ${arrconns[$j]}
   echo the number of valid connection is ${#arrconns[@]}
   
   if [[ ${#arrconns[@]} -eq 0 ]]; then
      echo "there is no valid connection string. Backup won't run"
      exit
   fi
fi

# Check whether this database has any PDB database in mount mode. If there is any, this PDB database integrity can't be verified. 
echo "Check whether this database has any PDB database in mount mode"
echo " "
$sqllogin << EOF > /dev/null
   spool $stdout replace
   COL name        FORMAT a20
   select name, open_mode from v\$pdbs;
EOF

grep -w MOUNTED  $stdout > /dev/null
if [ $? -eq 0 ]; then
   echo "There are PDB databases in mount mode. These PDB databases integrity can't be verified"
   echo "There are PDB databases in mount mode. These PDB databases integrity can't be verified" >> $runlog
   echo " " >> $runlog
   echo " "
   cat $stdout
   cat $stdout >> $runlog
   echo " " >> $runlog
   echo " "
fi

}

function create_rmanfile_all {

echo "Create rman file" >> $runlog

echo "
CONFIGURE DEFAULT DEVICE TYPE TO sbt_tape;
CONFIGURE BACKUP OPTIMIZATION OFF;
CONFIGURE CONTROLFILE AUTOBACKUP ON;
CONFIGURE CONTROLFILE AUTOBACKUP FORMAT FOR DEVICE TYPE sbt_tape TO '%d_%F.ctl';
" > $rmanfiled

echo "
CONFIGURE DEFAULT DEVICE TYPE TO sbt_tape;
CONFIGURE BACKUP OPTIMIZATION OFF;
CONFIGURE CONTROLFILE AUTOBACKUP ON;
CONFIGURE CONTROLFILE AUTOBACKUP FORMAT FOR DEVICE TYPE sbt_tape TO '%d_%F.ctl';
" >> $rmanfilea

j=0
k=0
while [ $j -lt $parallel ]; do

    while IFS= read -r ip; do
    
        ip=`echo $ip | xargs`    	
	
	if [[ -n $ip ]]; then
           lastip=$ip
	   
           if [[ $j -eq 0 ]]; then
	      if [[ $encryption = [Yy]* ]]; then
	         if [[ -n $cohesityname ]]; then
	            if [[ $sdedup = [Yy]* && $grpctype = [Yy]* ]]; then
	               echo "CONFIGURE CHANNEL DEVICE TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$cohesityname,sbt_certificate_file=${encrycert})';" >> $rmanfiled
	            elif [[ $sdedup = [Yy]* && $grpctype != [Yy]* ]]; then
		       echo "CONFIGURE CHANNEL DEVICE TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$cohesityname,gflag-name=sbt_use_grpc,gflag-value=false,sbt_certificate_file=${encrycert})';" >> $rmanfiled
		    elif [[ $sdedup != [Yy]* && $grpctype = [Yy]* ]]; then
		       echo "CONFIGURE CHANNEL DEVICE TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$cohesityname,disable_source_side_dedup=true,sbt_certificate_file=${encrycert})';" >> $rmanfiled
		    elif [[ $sdedup != [Yy]* && $grpctype != [Yy]* ]]; then
		       echo "CONFIGURE CHANNEL DEVICE TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$cohesityname,disable_source_side_dedup=true,gflag-name=sbt_use_grpc,gflag-value=false,sbt_certificate_file=${encrycert})';" >> $rmanfiled
		    fi
		 else
		    if [[ $sdedup = [Yy]* && $grpctype = [Yy]* ]]; then
		       echo "CONFIGURE CHANNEL DEVICE TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,sbt_certificate_file=${encrycert})';" >> $rmanfiled
	            elif [[ $sdedup = [Yy]* && $grpctype != [Yy]* ]]; then
		       echo "CONFIGURE CHANNEL DEVICE TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,gflag-name=sbt_use_grpc,gflag-value=false,sbt_certificate_file=${encrycert})';" >> $rmanfiled
		    elif [[ $sdedup != [Yy]* && $grpctype = [Yy]* ]]; then
		       echo "CONFIGURE CHANNEL DEVICE TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,disable_source_side_dedup=true,sbt_certificate_file=${encrycert})';" >> $rmanfiled
		    elif [[ $sdedup != [Yy]* && $grpctype != [Yy]* ]]; then
		       echo "CONFIGURE CHANNEL DEVICE TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,disable_source_side_dedup=true,gflag-name=sbt_use_grpc,gflag-value=false,sbt_certificate_file=${encrycert})';" >> $rmanfiled
		   fi
			 
		 fi
	      else
	         if [[ -n $cohesityname ]]; then
		    if [[ $sdedup = [Yy]* && $grpctype = [Yy]* ]]; then
	               echo "CONFIGURE CHANNEL DEVICE TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$cohesityname)';" >> $rmanfiled
	            elif [[ $sdedup = [Yy]* && $grpctype != [Yy]* ]]; then
		       echo "CONFIGURE CHANNEL DEVICE TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$cohesityname,gflag-name=sbt_use_grpc,gflag-value=false)';" >> $rmanfiled
		    elif [[ $sdedup != [Yy]* && $grpctype = [Yy]* ]]; then
		       echo "CONFIGURE CHANNEL DEVICE TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$cohesityname,disable_source_side_dedup=true)';" >> $rmanfiled
		    elif [[ $sdedup != [Yy]* && $grpctype != [Yy]* ]]; then
		       echo "CONFIGURE CHANNEL DEVICE TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$cohesityname,disable_source_side_dedup=true,gflag-name=sbt_use_grpc,gflag-value=false)';" >> $rmanfiled
		    fi
		 else
		    if [[ $sdedup = [Yy]* && $grpctype = [Yy]* ]]; then
		       echo "CONFIGURE CHANNEL DEVICE TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip)';" >> $rmanfiled
	            elif [[ $sdedup = [Yy]* && $grpctype != [Yy]* ]]; then
		       echo "CONFIGURE CHANNEL DEVICE TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,gflag-name=sbt_use_grpc,gflag-value=false)';" >> $rmanfiled
		    elif [[ $sdedup != [Yy]* && $grpctype = [Yy]* ]]; then
		       echo "CONFIGURE CHANNEL DEVICE TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,disable_source_side_dedup=true)';" >> $rmanfiled
		    elif [[ $sdedup != [Yy]* && $grpctype != [Yy]* ]]; then
		       echo "CONFIGURE CHANNEL DEVICE TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,disable_source_side_dedup=true,gflag-name=sbt_use_grpc,gflag-value=false)';" >> $rmanfiled
		    fi
		 fi
	      fi
#              echo "crosscheck backup device type sbt;
#                   delete noprompt expired backup device type sbt;
#                   Delete noprompt obsolete device type sbt;" >> $rmanfiled
	      echo "RUN {" >> $rmanfiled
	      echo "RUN {" >> $rmanfilea
	   fi
	   
	   if [[ -n $racconns ]]; then
              if [[ $j -lt $parallel ]]; then
		 if [[ $encryption = [Yy]* ]]; then
		    if [[ $sdedup = [Yy]* && $grpctype = [Yy]* ]]; then
	               allocate_database[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' connect='$cred@${arrconns[$k]} as $systype' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,sbt_certificate_file=${encrycert})';"
		       allocate_archive[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' connect='$cred@${arrconns[$k]} as $systype' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,sbt_certificate_file=${encrycert})' format '%d_%T_%U.blf';"
            	    elif [[ $sdedup = [Yy]* && $grpctype != [Yy]* ]]; then
		       allocate_database[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' connect='$cred@${arrconns[$k]} as $systype' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,gflag-name=sbt_use_grpc,gflag-value=false,sbt_certificate_file=${encrycert})';"
		       allocate_archive[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' connect='$cred@${arrconns[$k]} as $systype' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,gflag-name=sbt_use_grpc,gflag-value=false,sbt_certificate_file=${encrycert})' format '%d_%T_%U.blf';"
		    elif [[ $sdedup != [Yy]* && $grpctype = [Yy]* ]]; then
                       allocate_database[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' connect='$cred@${arrconns[$k]} as $systype' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,disable_source_side_dedup=true,sbt_certificate_file=${encrycert})';"
		       allocate_archive[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' connect='$cred@${arrconns[$k]} as $systype' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,disable_source_side_dedup=true,sbt_certificate_file=${encrycert})' format '%d_%T_%U.blf';"
            	    elif [[ $sdedup != [Yy]* && $grpctype != [Yy]* ]]; then 
		       allocate_database[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' connect='$cred@${arrconns[$k]} as $systype' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,disable_source_side_dedup=true,gflag-name=sbt_use_grpc,gflag-value=false,sbt_certificate_file=${encrycert})';"
		       allocate_archive[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' connect='$cred@${arrconns[$k]} as $systype' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,disable_source_side_dedup=true,gflag-name=sbt_use_grpc,gflag-value=false,sbt_certificate_file=${encrycert})' format '%d_%T_%U.blf';"
		    fi    
		 else
		    if [[ $sdedup = [Yy]* && $grpctype = [Yy]* ]]; then
		       allocate_database[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' connect='$cred@${arrconns[$k]} as $systype' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip)';"
                       allocate_archive[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' connect='$cred@${arrconns[$k]} as $systype' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip)' format '%d_%T_%U.blf';"
		    elif [[ $sdedup = [Yy]* && $grpctype != [Yy]* ]]; then
		       allocate_database[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' connect='$cred@${arrconns[$k]} as $systype' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,gflag-name=sbt_use_grpc,gflag-value=false)';"
		       allocate_archive[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' connect='$cred@${arrconns[$k]} as $systype' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,gflag-name=sbt_use_grpc,gflag-value=false)' format '%d_%T_%U.blf';"
		    elif [[ $sdedup != [Yy]* && $grpctype = [Yy]* ]]; then
		       allocate_database[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' connect='$cred@${arrconns[$k]} as $systype' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,disable_source_side_dedup=true);" 
		       allocate_archive[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' connect='$cred@${arrconns[$k]} as $systype' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,disable_source_side_dedup=true)' format '%d_%T_%U.blf';"
		    elif [[ $sdedup != [Yy]* && $grpctype != [Yy]* ]]; then
		       allocate_database[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' connect='$cred@${arrconns[$k]} as $systype' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,disable_source_side_dedup=true,gflag-name=sbt_use_grpc,gflag-value=false)';" 
		       allocate_archive[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' connect='$cred@${arrconns[$k]} as $systype' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,disable_source_side_dedup=true,gflag-name=sbt_use_grpc,gflag-value=false)' format '%d_%T_%U.blf';"
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
	               allocate_database[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,sbt_certificate_file=${encrycert})';"
   	               allocate_archive[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,sbt_certificate_file=${encrycert})' format '%d_%T_%U.blf';"
		    elif [[ $sdedup = [Yy]* && $grpctype != [Yy]* ]]; then
		       allocate_database[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,gflag-name=sbt_use_grpc,gflag-value=false,sbt_certificate_file=${encrycert})';"
                       allocate_archive[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,gflag-name=sbt_use_grpc,gflag-value=false,sbt_certificate_file=${encrycert})' format '%d_%T_%U.blf';"
		    elif [[ $sdedup != [Yy]* && $grpctype = [Yy]* ]]; then
		       allocate_database[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,disable_source_side_dedup=true,sbt_certificate_file=${encrycert})';"
		       allocate_archive[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,disable_source_side_dedup=true,sbt_certificate_file=${encrycert})' format '%d_%T_%U.blf';"
		    elif [[ $sdedup != [Yy]* && $grpctype != [Yy]* ]]; then
		       allocate_database[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,disable_source_side_dedup=true,gflag-name=sbt_use_grpc,gflag-value=false,sbt_certificate_file=${encrycert})';"
		       allocate_archive[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,disable_source_side_dedup=true,gflag-name=sbt_use_grpc,gflag-value=false,sbt_certificate_file=${encrycert})' format '%d_%T_%U.blf';"
		    fi
         	 else
		    if [[ $sdedup = [Yy]* && $grpctype = [Yy]* ]]; then
	               allocate_database[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip)';"
   	               allocate_archive[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip)' format '%d_%T_%U.blf';"
		    elif [[ $sdedup = [Yy]* && $grpctype != [Yy]* ]]; then
		       allocate_database[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,gflag-name=sbt_use_grpc,gflag-value=false)';"
		       allocate_archive[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,gflag-name=sbt_use_grpc,gflag-value=false)' format '%d_%T_%U.blf';"
		    elif [[ $sdedup != [Yy]* && $grpctype = [Yy]* ]]; then
		       allocate_database[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,disable_source_side_dedup=true)';"
		       allocate_archive[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,disable_source_side_dedup=true)' format '%d_%T_%U.blf';"
		    elif [[ $sdedup != [Yy]* && $grpctype != [Yy]* ]]; then
		       allocate_database[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,disable_source_side_dedup=true,gflag-name=sbt_use_grpc,gflag-value=false)';"
		       allocate_archive[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,disable_source_side_dedup=true,gflag-name=sbt_use_grpc,gflag-value=false)' format '%d_%T_%U.blf';"
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

if [[ $level = "offline" || $level = "full" ]]; then
   if [[ -z $sectionsize ]]; then
      if [[ $compression = [Yy]* ]]; then
         echo "backup AS COMPRESSED BACKUPSET TAG '$TAG' database filesperset 1 format '%d_%T_%U_$level.bdf';" >> $rmanfiled
      else
         echo "backup TAG '$TAG' database filesperset 1 format '%d_%T_%U_$level.bdf';" >> $rmanfiled
      fi
   else
      if [[ $compression = [Yy]* ]]; then
         echo "backup AS COMPRESSED BACKUPSET TAG '$TAG' database section size ${sectionsize}G filesperset 1 format '%d_%T_%U_$level.bdf';" >> $rmanfiled
      else
         echo "backup TAG '$TAG' database section size ${sectionsize}G filesperset 1 format '%d_%T_%U_$level.bdf';" >> $rmanfiled
      fi
   fi
else
   if [[ -z $sectionsize ]]; then
      if [[ $compression = [Yy]* ]]; then
         echo "backup AS COMPRESSED BACKUPSET INCREMENTAL LEVEL $level CUMULATIVE TAG '$TAG' database filesperset 1 format '%d_%T_%U_level${level}.bdf';" >> $rmanfiled
      else
         echo "backup INCREMENTAL LEVEL $level CUMULATIVE TAG '$TAG' database filesperset 1 format '%d_%T_%U_level${level}.bdf';" >> $rmanfiled
      fi
   else
      if [[ $compression = [Yy]* ]]; then
         echo "backup backup AS COMPRESSED BACKUPSET INCREMENTAL LEVEL $level CUMULATIVE TAG '$TAG' database section size ${sectionsize}G filesperset 1 format '%d_%T_%U_level${level}.bdf';" >> $rmanfiled
      else
         echo "backup INCREMENTAL LEVEL $level CUMULATIVE TAG '$TAG' database section size ${sectionsize}G filesperset 1 format '%d_%T_%U_level${level}.bdf';" >> $rmanfiled
      fi
   fi
fi
#if [[ $dbstatus != "standby" ]]; then
#  echo "
#  sql 'alter system switch logfile';
#" >> $rmanfiled
#fi
if [[ $archretday = [Nn]* ]]; then
   if [[ $compression = [Yy]* ]]; then
      echo "backup AS COMPRESSED BACKUPSET TAG '$archive_tag' archivelog all filesperset 8 not backed up $archcopynum times;" >> $rmanfilea
   else
      echo "backup TAG '$archive_tag' archivelog all filesperset 8 not backed up $archcopynum times;" >> $rmanfilea
   fi
elif [[ $archretday -eq 0 ]]; then
   if [[ $compression = [Yy]* ]]; then
      echo "backup AS COMPRESSED BACKUPSET TAG '$archive_tag' archivelog all filesperset 8 not backed up $archcopynum times delete input;" >> $rmanfilea
   else
      echo "backup TAG '$archive_tag' archivelog all filesperset 8 not backed up $archcopynum times delete input;" >> $rmanfilea
   fi
else
   if [[ $compression = [Yy]* ]]; then
      echo "backup AS COMPRESSED BACKUPSET TAG '$archive_tag' archivelog all filesperset 8 not backed up $archcopynum times archivelog until time 'sysdate-$archretday' delete input;" >> $rmanfilea
   else
      echo "backup TAG '$archive_tag' archivelog all filesperset 8 not backed up $archcopynum times archivelog until time 'sysdate-$archretday' delete input;" >> $rmanfilea
   fi
fi

echo "BACKUP TAG '$ctl_tag' CURRENT CONTROLFILE format '%d_%T_%U.ctl';" >> $rmanfiled

for (( i=0; i < ${#unallocate[@]}; i++ )); do
   echo ${unallocate[$i]} >> $rmanfiled
   echo ${unallocate[$i]} >> $rmanfilea
done

echo "} 
 exit;" >> $rmanfiled
echo "}
 exit;" >> $rmanfilea

echo "finished creating rman file" >> $runlog
echo "finished creating rman file"
}

function create_rmanfile_all_nolog {

echo "Create rman file" >> $runlog

echo "
CONFIGURE DEFAULT DEVICE TYPE TO sbt_tape;
CONFIGURE BACKUP OPTIMIZATION OFF;
CONFIGURE CONTROLFILE AUTOBACKUP ON;
CONFIGURE CONTROLFILE AUTOBACKUP FORMAT FOR DEVICE TYPE sbt_tape TO '%d_%F.ctl';
" > $rmanfiled

echo "
CONFIGURE DEFAULT DEVICE TYPE TO sbt_tape;
CONFIGURE BACKUP OPTIMIZATION OFF;
CONFIGURE CONTROLFILE AUTOBACKUP ON;
CONFIGURE CONTROLFILE AUTOBACKUP FORMAT FOR DEVICE TYPE sbt_tape TO '%d_%F.ctl';
" >> $rmanfilea

j=0
k=0
while [ $j -lt $parallel ]; do

    while IFS= read -r ip; do
    
        ip=`echo $ip | xargs`    	
	
	if [[ -n $ip ]]; then
           lastip=$ip
	   
           if [[ $j -eq 0 ]]; then
	      if [[ $encryption = [Yy]* ]]; then
	         if [[ -n $cohesityname ]]; then
	            if [[ $sdedup = [Yy]* && $grpctype = [Yy]* ]]; then
	               echo "CONFIGURE CHANNEL DEVICE TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$cohesityname,sbt_certificate_file=${encrycert},log_level=0)';" >> $rmanfiled
	            elif [[ $sdedup = [Yy]* && $grpctype != [Yy]* ]]; then
		       echo "CONFIGURE CHANNEL DEVICE TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$cohesityname,gflag-name=sbt_use_grpc,gflag-value=false,sbt_certificate_file=${encrycert},log_level=0)';" >> $rmanfiled
		    elif [[ $sdedup != [Yy]* && $grpctype = [Yy]* ]]; then
		       echo "CONFIGURE CHANNEL DEVICE TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$cohesityname,disable_source_side_dedup=true,sbt_certificate_file=${encrycert},log_level=0)';" >> $rmanfiled
		    elif [[ $sdedup != [Yy]* && $grpctype != [Yy]* ]]; then
		       echo "CONFIGURE CHANNEL DEVICE TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$cohesityname,disable_source_side_dedup=true,gflag-name=sbt_use_grpc,gflag-value=false,sbt_certificate_file=${encrycert},log_level=0)';" >> $rmanfiled
		    fi
		 else
		    if [[ $sdedup = [Yy]* && $grpctype = [Yy]* ]]; then
		       echo "CONFIGURE CHANNEL DEVICE TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,sbt_certificate_file=${encrycert},log_level=0)';" >> $rmanfiled
	            elif [[ $sdedup = [Yy]* && $grpctype != [Yy]* ]]; then
		       echo "CONFIGURE CHANNEL DEVICE TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,gflag-name=sbt_use_grpc,gflag-value=false,sbt_certificate_file=${encrycert},log_level=0)';" >> $rmanfiled
		    elif [[ $sdedup != [Yy]* && $grpctype = [Yy]* ]]; then
		       echo "CONFIGURE CHANNEL DEVICE TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,disable_source_side_dedup=true,sbt_certificate_file=${encrycert},log_level=0)';" >> $rmanfiled
		    elif [[ $sdedup != [Yy]* && $grpctype != [Yy]* ]]; then
		       echo "CONFIGURE CHANNEL DEVICE TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,disable_source_side_dedup=true,gflag-name=sbt_use_grpc,gflag-value=false,sbt_certificate_file=${encrycert},log_level=0)';" >> $rmanfiled
		   fi
			 
		 fi
	      else
	         if [[ -n $cohesityname ]]; then
		    if [[ $sdedup = [Yy]* && $grpctype = [Yy]* ]]; then
	               echo "CONFIGURE CHANNEL DEVICE TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$cohesityname,log_level=0)';" >> $rmanfiled
	            elif [[ $sdedup = [Yy]* && $grpctype != [Yy]* ]]; then
		       echo "CONFIGURE CHANNEL DEVICE TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$cohesityname,gflag-name=sbt_use_grpc,gflag-value=false,log_level=0)';" >> $rmanfiled
		    elif [[ $sdedup != [Yy]* && $grpctype = [Yy]* ]]; then
		       echo "CONFIGURE CHANNEL DEVICE TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$cohesityname,disable_source_side_dedup=true,log_level=0)';" >> $rmanfiled
		    elif [[ $sdedup != [Yy]* && $grpctype != [Yy]* ]]; then
		       echo "CONFIGURE CHANNEL DEVICE TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$cohesityname,disable_source_side_dedup=true,gflag-name=sbt_use_grpc,gflag-value=false,log_level=0)';" >> $rmanfiled
		    fi
		 else
		    if [[ $sdedup = [Yy]* && $grpctype = [Yy]* ]]; then
		       echo "CONFIGURE CHANNEL DEVICE TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,log_level=0)';" >> $rmanfiled
	            elif [[ $sdedup = [Yy]* && $grpctype != [Yy]* ]]; then
		       echo "CONFIGURE CHANNEL DEVICE TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,gflag-name=sbt_use_grpc,gflag-value=false,log_level=0)';" >> $rmanfiled
		    elif [[ $sdedup != [Yy]* && $grpctype = [Yy]* ]]; then
		       echo "CONFIGURE CHANNEL DEVICE TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,disable_source_side_dedup=true,log_level=0)';" >> $rmanfiled
		    elif [[ $sdedup != [Yy]* && $grpctype != [Yy]* ]]; then
		       echo "CONFIGURE CHANNEL DEVICE TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,disable_source_side_dedup=true,gflag-name=sbt_use_grpc,gflag-value=false,log_level=0)';" >> $rmanfiled
		    fi
		 fi
	      fi
#	         echo "crosscheck backup device type sbt;
#	           delete noprompt expired backup device type sbt;
#	           Delete noprompt obsolete device type sbt;" >> $rmanfiled
	      echo "RUN {" >> $rmanfiled
	      echo "RUN {" >> $rmanfilea
	   fi
	   
	   if [[ -n $racconns ]]; then
              if [[ $j -lt $parallel ]]; then
		 if [[ $encryption = [Yy]* ]]; then
		    if [[ $sdedup = [Yy]* && $grpctype = [Yy]* ]]; then
	               allocate_database[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' connect='$cred@${arrconns[$k]} as $systype' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,sbt_certificate_file=${encrycert},log_level=0)';"
		       allocate_archive[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' connect='$cred@${arrconns[$k]} as $systype' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,sbt_certificate_file=${encrycert},log_level=0)' format '%d_%T_%U.blf';"
            	    elif [[ $sdedup = [Yy]* && $grpctype != [Yy]* ]]; then
		       allocate_database[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' connect='$cred@${arrconns[$k]} as $systype' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,gflag-name=sbt_use_grpc,gflag-value=false,sbt_certificate_file=${encrycert},log_level=0)';"
		       allocate_archive[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' connect='$cred@${arrconns[$k]} as $systype' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,gflag-name=sbt_use_grpc,gflag-value=false,sbt_certificate_file=${encrycert},log_level=0)' format '%d_%T_%U.blf';"
		    elif [[ $sdedup != [Yy]* && $grpctype = [Yy]* ]]; then
                       allocate_database[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' connect='$cred@${arrconns[$k]} as $systype' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,disable_source_side_dedup=true,sbt_certificate_file=${encrycert},log_level=0)';"
		       allocate_archive[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' connect='$cred@${arrconns[$k]} as $systype' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,disable_source_side_dedup=true,sbt_certificate_file=${encrycert},log_level=0)' format '%d_%T_%U.blf';"
            	    elif [[ $sdedup != [Yy]* && $grpctype != [Yy]* ]]; then 
		       allocate_database[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' connect='$cred@${arrconns[$k]} as $systype' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,disable_source_side_dedup=true,gflag-name=sbt_use_grpc,gflag-value=false,sbt_certificate_file=${encrycert},log_level=0)';"
		       allocate_archive[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' connect='$cred@${arrconns[$k]} as $systype' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,disable_source_side_dedup=true,gflag-name=sbt_use_grpc,gflag-value=false,sbt_certificate_file=${encrycert},log_level=0)' format '%d_%T_%U.blf';"
		    fi    
		 else
		    if [[ $sdedup = [Yy]* && $grpctype = [Yy]* ]]; then
		       allocate_database[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' connect='$cred@${arrconns[$k]} as $systype' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,log_level=0)';"
                       allocate_archive[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' connect='$cred@${arrconns[$k]} as $systype' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,log_level=0)' format '%d_%T_%U.blf';"
		    elif [[ $sdedup = [Yy]* && $grpctype != [Yy]* ]]; then
		       allocate_database[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' connect='$cred@${arrconns[$k]} as $systype' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,gflag-name=sbt_use_grpc,gflag-value=false,log_level=0)';"
		       allocate_archive[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' connect='$cred@${arrconns[$k]} as $systype' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,gflag-name=sbt_use_grpc,gflag-value=false,log_level=0)' format '%d_%T_%U.blf';"
		    elif [[ $sdedup != [Yy]* && $grpctype = [Yy]* ]]; then
		       allocate_database[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' connect='$cred@${arrconns[$k]} as $systype' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,disable_source_side_dedup=true,log_level=0);" 
		       allocate_archive[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' connect='$cred@${arrconns[$k]} as $systype' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,disable_source_side_dedup=true,log_level=0)' format '%d_%T_%U.blf';"
		    elif [[ $sdedup != [Yy]* && $grpctype != [Yy]* ]]; then
		       allocate_database[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' connect='$cred@${arrconns[$k]} as $systype' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,disable_source_side_dedup=true,gflag-name=sbt_use_grpc,gflag-value=false,log_level=0)';" 
		       allocate_archive[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' connect='$cred@${arrconns[$k]} as $systype' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,disable_source_side_dedup=true,gflag-name=sbt_use_grpc,gflag-value=false,log_level=0)' format '%d_%T_%U.blf';"
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
	               allocate_database[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,sbt_certificate_file=${encrycert},log_level=0)';"
   	               allocate_archive[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,sbt_certificate_file=${encrycert},log_level=0)' format '%d_%T_%U.blf';"
		    elif [[ $sdedup = [Yy]* && $grpctype != [Yy]* ]]; then
		       allocate_database[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,gflag-name=sbt_use_grpc,gflag-value=false,sbt_certificate_file=${encrycert},log_level=0)';"
                       allocate_archive[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,gflag-name=sbt_use_grpc,gflag-value=false,sbt_certificate_file=${encrycert},log_level=0)' format '%d_%T_%U.blf';"
		    elif [[ $sdedup != [Yy]* && $grpctype = [Yy]* ]]; then
		       allocate_database[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,disable_source_side_dedup=true,sbt_certificate_file=${encrycert},log_level=0)';"
		       allocate_archive[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,disable_source_side_dedup=true,sbt_certificate_file=${encrycert},log_level=0)' format '%d_%T_%U.blf';"
		    elif [[ $sdedup != [Yy]* && $grpctype != [Yy]* ]]; then
		       allocate_database[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,disable_source_side_dedup=true,gflag-name=sbt_use_grpc,gflag-value=false,sbt_certificate_file=${encrycert},log_level=0)';"
		       allocate_archive[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,disable_source_side_dedup=true,gflag-name=sbt_use_grpc,gflag-value=false,sbt_certificate_file=${encrycert},log_level=0)' format '%d_%T_%U.blf';"
		    fi
         	 else
		    if [[ $sdedup = [Yy]* && $grpctype = [Yy]* ]]; then
	               allocate_database[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,log_level=0)';"
   	               allocate_archive[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,log_level=0)' format '%d_%T_%U.blf';"
		    elif [[ $sdedup = [Yy]* && $grpctype != [Yy]* ]]; then
		       allocate_database[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,gflag-name=sbt_use_grpc,gflag-value=false,log_level=0)';"
		       allocate_archive[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,gflag-name=sbt_use_grpc,gflag-value=false,log_level=0)' format '%d_%T_%U.blf';"
		    elif [[ $sdedup != [Yy]* && $grpctype = [Yy]* ]]; then
		       allocate_database[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,disable_source_side_dedup=true,log_level=0)';"
		       allocate_archive[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,disable_source_side_dedup=true,log_level=0)' format '%d_%T_%U.blf';"
		    elif [[ $sdedup != [Yy]* && $grpctype != [Yy]* ]]; then
		       allocate_database[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,disable_source_side_dedup=true,gflag-name=sbt_use_grpc,gflag-value=false,log_level=0)';"
		       allocate_archive[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,disable_source_side_dedup=true,gflag-name=sbt_use_grpc,gflag-value=false,log_level=0)' format '%d_%T_%U.blf';"
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

if [[ $level = "offline" || $level = "full" ]]; then
   if [[ -z $sectionsize ]]; then
      if [[ $compression = [Yy]* ]]; then
         echo "backup AS COMPRESSED BACKUPSET TAG '$TAG' database filesperset 1 format '%d_%T_%U_$level.bdf';" >> $rmanfiled
      else
         echo "backup TAG '$TAG' database filesperset 1 format '%d_%T_%U_$level.bdf';" >> $rmanfiled
      fi
   else
      if [[ $compression = [Yy]* ]]; then
         echo "backup AS COMPRESSED BACKUPSET TAG '$TAG' database section size ${sectionsize}G filesperset 1 format '%d_%T_%U_$level.bdf';" >> $rmanfiled
      else
         echo "backup TAG '$TAG' database section size ${sectionsize}G filesperset 1 format '%d_%T_%U_$level.bdf';" >> $rmanfiled
      fi
   fi
else
   if [[ -z $sectionsize ]]; then
      if [[ $compression = [Yy]* ]]; then
         echo "backup AS COMPRESSED BACKUPSET INCREMENTAL LEVEL $level CUMULATIVE TAG '$TAG' database filesperset 1 format '%d_%T_%U_level${level}.bdf';" >> $rmanfiled
      else
         echo "backup INCREMENTAL LEVEL $level CUMULATIVE TAG '$TAG' database filesperset 1 format '%d_%T_%U_level${level}.bdf';" >> $rmanfiled
      fi
   else
      if [[ $compression = [Yy]* ]]; then
         echo "backup backup AS COMPRESSED BACKUPSET INCREMENTAL LEVEL $level CUMULATIVE TAG '$TAG' database section size ${sectionsize}G filesperset 1 format '%d_%T_%U_level${level}.bdf';" >> $rmanfiled
      else
         echo "backup INCREMENTAL LEVEL $level CUMULATIVE TAG '$TAG' database section size ${sectionsize}G filesperset 1 format '%d_%T_%U_level${level}.bdf';" >> $rmanfiled
      fi
   fi
fi
#if [[ $dbstatus != "standby" ]]; then
#  echo "
#  sql 'alter system switch logfile';
#" >> $rmanfiled
#fi
if [[ $archretday = [Nn]* ]]; then
   if [[ $compression = [Yy]* ]]; then
      echo "backup AS COMPRESSED BACKUPSET TAG '$archive_tag' archivelog all filesperset 8 not backed up $archcopynum times;" >> $rmanfilea
   else
      echo "backup TAG '$archive_tag' archivelog all filesperset 8 not backed up $archcopynum times;" >> $rmanfilea
   fi
elif [[ $archretday -eq 0 ]]; then
   if [[ $compression = [Yy]* ]]; then
      echo "backup AS COMPRESSED BACKUPSET TAG '$archive_tag' archivelog all filesperset 8 not backed up $archcopynum times delete input;" >> $rmanfilea
   else
      echo "backup TAG '$archive_tag' archivelog all filesperset 8 not backed up $archcopynum times delete input;" >> $rmanfilea
   fi
else
   if [[ $compression = [Yy]* ]]; then
      echo "backup AS COMPRESSED BACKUPSET TAG '$archive_tag' archivelog all filesperset 8 not backed up $archcopynum times archivelog until time 'sysdate-$archretday' delete input;" >> $rmanfilea
   else
      echo "backup TAG '$archive_tag' archivelog all filesperset 8 not backed up $archcopynum times archivelog until time 'sysdate-$archretday' delete input;" >> $rmanfilea
   fi
fi

echo "BACKUP TAG '$ctl_tag' CURRENT CONTROLFILE format '%d_%T_%U.ctl';" >> $rmanfiled

for (( i=0; i < ${#unallocate[@]}; i++ )); do
   echo ${unallocate[$i]} >> $rmanfiled
   echo ${unallocate[$i]} >> $rmanfilea
done

echo "} 
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
CONFIGURE BACKUP OPTIMIZATION OFF;
CONFIGURE CONTROLFILE AUTOBACKUP ON;
CONFIGURE CONTROLFILE AUTOBACKUP FORMAT FOR DEVICE TYPE sbt_tape TO '%d_%F.ctl';

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
	            allocate_archive[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,sbt_certificate_file=${encrycert})' format '%d_%T_%U.blf';"
 	         elif [[ $sdedup = [Yy]* && $grpctype != [Yy]* ]]; then
		    allocate_archive[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,gflag-name=sbt_use_grpc,gflag-value=false,sbt_certificate_file=${encrycert})' format '%d_%T_%U.blf';"
		 elif [[ $sdedup != [Yy]* && $grpctype = [Yy]* ]]; then
		    allocate_archive[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,disable_source_side_dedup=true,sbt_certificate_file=${encrycert})' format '%d_%T_%U.blf';"
		 elif [[ $sdedup != [Yy]* && $grpctype != [Yy]* ]]; then
		    allocate_archive[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,disable_source_side_dedup=true,gflag-name=sbt_use_grpc,gflag-value=false,sbt_certificate_file=${encrycert})' format '%d_%T_%U.blf';"
		 fi
	      else
	         if [[ $sdedup = [Yy]* && $grpctype = [Yy]* ]]; then
	            allocate_archive[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip)' format '%d_%T_%U.blf';"
	         elif [[ $sdedup = [Yy]* && $grpctype != [Yy]* ]]; then
		    allocate_archive[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,gflag-name=sbt_use_grpc,gflag-value=false)' format '%d_%T_%U.blf';"
		 elif [[ $sdedup != [Yy]* && $grpctype = [Yy]* ]]; then
		    allocate_archive[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,disable_source_side_dedup=true)' format '%d_%T_%U.blf';"
		 elif [[ $sdedup != [Yy]* && $grpctype != [Yy]* ]]; then
		    allocate_archive[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,disable_source_side_dedup=true,gflag-name=sbt_use_grpc,gflag-value=false)' format '%d_%T_%U.blf';"
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
   if [[ $compression = [Yy]* ]]; then
      echo "backup AS COMPRESSED BACKUPSET TAG '$archive_tag' archivelog all filesperset 8 not backed up $archcopynum times;" >> $rmanfilear
   else
      echo "backup TAG '$archive_tag' archivelog all filesperset 8 not backed up $archcopynum times;" >> $rmanfilear
   fi
elif [[ $archretday -eq 0 ]]; then
   if [[ $compression = [Yy]* ]]; then
      echo "backup AS COMPRESSED BACKUPSET TAG '$archive_tag' archivelog all filesperset 8 not backed up $archcopynum times delete input;" >> $rmanfilear
   else
      echo "backup TAG '$archive_tag' archivelog all filesperset 8 not backed up $archcopynum times delete input;" >> $rmanfilear
   fi
else
   if [[ $compression = [Yy]* ]]; then
      echo "backup AS COMPRESSED BACKUPSET TAG '$archive_tag' archivelog all filesperset 8 not backed up $archcopynum times archivelog until time 'sysdate-$archretday' delete input;" >> $rmanfilear
   else
      echo "backup TAG '$archive_tag' archivelog all filesperset 8 not backed up $archcopynum times archivelog until time 'sysdate-$archretday' delete input;" >> $rmanfilear
   fi
fi

for (( i=0; i < ${#unallocate[@]}; i++ )); do
   echo ${unallocate[$i]} >> $rmanfilear
done

echo "}
 exit;" >> $rmanfilear

echo "finished creating rman file" >> $runrlog
echo "finished creating rman file"
}

function create_rmanfile_archive_nolog {

echo "Create rman file" >> $runrlog

echo "
CONFIGURE DEFAULT DEVICE TYPE TO sbt_tape;
CONFIGURE BACKUP OPTIMIZATION OFF;
CONFIGURE CONTROLFILE AUTOBACKUP ON;
CONFIGURE CONTROLFILE AUTOBACKUP FORMAT FOR DEVICE TYPE sbt_tape TO '%d_%F.ctl';

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
	            allocate_archive[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,sbt_certificate_file=${encrycert},log_level=0)' format '%d_%T_%U.blf';"
 	         elif [[ $sdedup = [Yy]* && $grpctype != [Yy]* ]]; then
		    allocate_archive[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,gflag-name=sbt_use_grpc,gflag-value=false,sbt_certificate_file=${encrycert},log_level=0)' format '%d_%T_%U.blf';"
		 elif [[ $sdedup != [Yy]* && $grpctype = [Yy]* ]]; then
		    allocate_archive[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,disable_source_side_dedup=true,sbt_certificate_file=${encrycert},log_level=0)' format '%d_%T_%U.blf';"
		 elif [[ $sdedup != [Yy]* && $grpctype != [Yy]* ]]; then
		    allocate_archive[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,disable_source_side_dedup=true,gflag-name=sbt_use_grpc,gflag-value=false,sbt_certificate_file=${encrycert},log_level=0)' format '%d_%T_%U.blf';"
		 fi
	      else
	         if [[ $sdedup = [Yy]* && $grpctype = [Yy]* ]]; then
	            allocate_archive[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,log_level=0)' format '%d_%T_%U.blf';"
	         elif [[ $sdedup = [Yy]* && $grpctype != [Yy]* ]]; then
		    allocate_archive[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,gflag-name=sbt_use_grpc,gflag-value=false,log_level=0)' format '%d_%T_%U.blf';"
		 elif [[ $sdedup != [Yy]* && $grpctype = [Yy]* ]]; then
		    allocate_archive[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,disable_source_side_dedup=true,log_level=0)' format '%d_%T_%U.blf';"
		 elif [[ $sdedup != [Yy]* && $grpctype != [Yy]* ]]; then
		    allocate_archive[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,disable_source_side_dedup=true,gflag-name=sbt_use_grpc,gflag-value=false,log_level=0)' format '%d_%T_%U.blf';"
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
   if [[ $compression = [Yy]* ]]; then
      echo "backup AS COMPRESSED BACKUPSET TAG '$archive_tag' archivelog all filesperset 8 not backed up $archcopynum times;" >> $rmanfilear
   else
      echo "backup TAG '$archive_tag' archivelog all filesperset 8 not backed up $archcopynum times;" >> $rmanfilear
   fi
elif [[ $archretday -eq 0 ]]; then
   if [[ $compression = [Yy]* ]]; then
      echo "backup AS COMPRESSED BACKUPSET TAG '$archive_tag' archivelog all filesperset 8 not backed up $archcopynum times delete input;" >> $rmanfilear
   else
      echo "backup TAG '$archive_tag' archivelog all filesperset 8 not backed up $archcopynum times delete input;" >> $rmanfilear
   fi
else
   if [[ $compression = [Yy]* ]]; then
      echo "backup AS COMPRESSED BACKUPSET TAG '$archive_tag' archivelog all filesperset 8 not backed up $archcopynum times archivelog until time 'sysdate-$archretday' delete input;" >> $rmanfilear
   else
      echo "backup TAG '$archive_tag' archivelog all filesperset 8 not backed up $archcopynum times archivelog until time 'sysdate-$archretday' delete input;" >> $rmanfilear
   fi
fi

for (( i=0; i < ${#unallocate[@]}; i++ )); do
   echo ${unallocate[$i]} >> $rmanfilear
done

echo "}
 exit;" >> $rmanfilear

echo "finished creating rman file" >> $runrlog
echo "finished creating rman file"
}

function database_mount {

echo "Change the database to mount open mode if it is not already is"
# test the database status
# Get open mode
rm $stdout
$sqllogin << EOF > /dev/null
   spool $stdout replace
   select open_mode from v\$database;
EOF

i=0
while IFS= read -r line
do
  if [[ $i -eq 1 ]]; then
     open_mode=`echo $line | xargs`
     i=$[$i+1]
  fi
  if [[ $line =~ "-" ]];then
     i=$[$i+1]
  fi
done < $stdout

echo database at $open_mode open mode

# If it is not in mounted mode, shut it down and start it in mount mode
if [[ $open_mode != "MOUNTED" ]]; then
    echo "shutdown the database and started it at mount open mode"
    $sqllogin << EOF
    shutdown immediate;
    startup mount
EOF

   if [ $? -ne 0 ]; then
      echo "Database failed to start to mount open mode at " `/bin/date '+%Y%m%d%H%M%S'`
      echo "Database failed to start to mount open mode at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog
      exit 1
   else
      echo "Database started to mount open mode at finished at " `/bin/date '+%Y%m%d%H%M%S'`
      echo "Database started to mount open mode at finished at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog 
   fi
else
    echo "database is at mount open mode, the backup can start" 
    echo "database is at mount open mode, the backup can start" >> $runlog
fi

}

function database_startup {

echo "startup the database after the offline backup finishes"
# Startup the database when offline backup is done
if [[ $open_mode != "MOUNTED" ]]; then
   $sqllogin << EOF
   alter database open;
EOF

   rm $stdout
   $sqllogin << EOF > /dev/null
     spool $stdout replace
     select open_mode from v\$database;
EOF

   i=0
   while IFS= read -r line
   do
     if [[ $i -eq 1 ]]; then
       open_mode=`echo $line | xargs`
       i=$[$i+1]
     fi
     if [[ $line =~ "-" ]];then
       i=$[$i+1]
     fi
   done < $stdout


   if [[ $open_mode == "MOUNTED" ]]; then
      echo "Database failed to start at " `/bin/date '+%Y%m%d%H%M%S'`
      echo "Database failed to start at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog
      exit 1
   else
      echo "Database started finished at " `/bin/date '+%Y%m%d%H%M%S'`
      echo "Database started finished at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog 
   fi
else
   echo "The database was at mount open mode. no need to start the databse"
fi

}

function backup {

echo "Database backup started at " `/bin/date '+%Y%m%d%H%M%S'`
echo "Database backup started at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog

if [[ -z $catalogc ]]; then
   rman log $rmanlog << EOF > /dev/null
   connect target '${targetc}'
   @$rmanfiled
EOF
else
   rman log $rmanlog << EOF > /dev/null
   connect target '${targetc}'
   connect catalog '${catalogc}'
   @$rmanfiled
EOF
fi

if [ $? -ne 0 ]; then
  echo "Database backup failed at " `/bin/date '+%Y%m%d%H%M%S'`
  echo "Database backup failed at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog
#  while IFS= read -r ip
#  do
#    echo $ip
#  done < $rmanlog 
#  exit 1
else
  echo "Database backup finished at " `/bin/date '+%Y%m%d%H%M%S'`
  echo "Database backup finished at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog 
fi

#echo open mode is $open_mode
echo dbstatus is $dbstatus

if [[ $dbstatus != "standby" ]]; then
   if [[ $level != "offline" ]]; then
      rman << EOF
connect target '${targetc}'
sql 'ALTER SYSTEM ARCHIVE LOG CURRENT';
exit
EOF
   fi
fi
}

function archive {

echo "Archive logs backup started at " `/bin/date '+%Y%m%d%H%M%S'`
echo "Archive logs backup started at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog

if [[ -z $catalogc ]]; then
   rman log $rmanloga << EOF > /dev/null
   connect target '${targetc}'
   @$rmanfilea
EOF
else
   rman log $rmanloga << EOF > /dev/null
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
   channelfail=yes
#   exit 1
else
   echo "Backup is successful."
fi
}

function archiver {

echo "Archive logs backup started at " `/bin/date '+%Y%m%d%H%M%S'`
echo "Archive logs backup started at " `/bin/date '+%Y%m%d%H%M%S'` >> $runrlog

if [[ -z $catalogc ]]; then
   rman log $rmanlogar << EOF > /dev/null
   connect target '${targetc}'
   @$rmanfilear
EOF
else
   rman log $rmanlogar << EOF > /dev/null
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


function sync_oracle_record {

# Clean Oracle backup record in control file or Oracle recovery catalog

if [[ -z $catalogc ]]; then
   rman log $expirelog << EOF > /dev/null
   connect target '${targetc}'
   crosscheck backup device type sbt;
   delete noprompt expired backup device type sbt;
   exit;
EOF
else
   rman log $expirelog << EOF > /dev/null
   connect target '${targetc}'
   connect catalog '${catalogc}'
   crosscheck backup device type sbt;
   delete noprompt expired backup device type sbt;
   exit;
EOF
fi

grep -i error $expirelog
 
if [ $? -eq 0 ]; then
   echo "Expiration failed. The error message is in log file $expirelog"
#   exit 1
else
   echo "Oracle control file or Oracle recovery catalog is synced up with the actual backup files."
fi

}


setup

echo "
the backup script runs on `hostname -s` and in directory $DIR 

oracle database server is $host
"
if [[ $archivelogonly = "yes" ]]; then
  echo "archive logs backup only"
  if [[ $sbtiolog = [Yy]* ]]; then
     create_rmanfile_archive
  else
     create_rmanfile_archive_nolog
  fi
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
  if [[ $sbtiolog = [Yy]* ]]; then
     create_rmanfile_all
  else
     create_rmanfile_all_nolog
  fi
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
    if [[ $level == "offline" ]]; then
       database_mount
       backup
       database_startup
    else
       backup
       archive
    fi
    if [[ -z $channelfail ]]; then
       sync_oracle_record
    fi
  fi
  grep -i error $runlog

  if [ $? -eq 0 ]; then
    echo "Backup may be successful. However there are IPs in $vipfile not reachable"
#  exit 1
  fi
fi
