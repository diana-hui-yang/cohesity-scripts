#!/bin/ksh
#
# Name:         aix-backup-ora-coh-sbt.ksh
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
# 08/14/20 Diana Yang   Add more contrains in RAC environment. 
# 09/15/20 Diana Yang   Reduced number of pings. 
# 10/29/20 Diana Yang   Make database name search not case sensitive.
# 10/30/20 Diana Yang   Standardlize name. Remove "-f" and "-s" as required parameter
# 10/31/20 Diana Yang   Support backing up RAC using nodes supplied by users
# 11/11/20 Diana Yang   Remove the need to manually create vip-list file
# 12/18/20 Diana Yang   Add option to backup the archive logs more than once
# 01/21/21 Diana Yang   Check the sbt library in ORACLE_HOME/lib directory
# 05/21/21 Diana Yang   Add a switch for TAG
# 09/01/22 Diana Yang   Check whether database is RAC or not.
# 10/05/22 Diana Yang   Add the backup level number to the names of backupset.
# 11/29/22 Diana Yang   Add offline and full backup option.
# 01/22/23 Diana Yang   Add Synchronizing the backup with oracle control file record or recovery catalog record option
# 08/17/23 Diana Yang   Check any pdb database is in mount mode and added it to the output
# 07/39/24 Diana Yang   Convert the script from bash to ksh
#
#################################################################

function show_usage {
echo "usage: aix-backup-ora-coh-sbt.ksh -r <Target connection> -c <Catalog connection> -h <host> -n <rac-node1-conn,rac-node2-conn,...> -o <Oracle_DB_Name> -a <archive only> -i <incremental level> -y <Cohesity-cluster> -f <vip file> -v <view> -s <sbt home> -p <number of channels> -e <retention> -u <retention> -l <archive log keep days> -z <section size> -k <RMAN compression yes/no> -m <ORACLE_HOME> -w <yes/no> -b <number of archive logs> -t <tag>"
echo " "
echo " Required Parameters"
echo " -h : host (scanname is required if it is RAC. optional if it is standalone.)"
echo " -o : ORACLE_DB_NAME (Need to have an entry of this database in /etc/oratab. If it is RAC, it is db_name)"
echo " -y : Cohesity Cluster DNS name"
echo " -a : archivelog only backup (yes means archivelog backup only, no means database backup plus archivelog backup, default is no)"
echo " -i : If not archivelog only backup, it is full or incremental backup. 0 is full backup, and 1 is cumulative incremental backup, offline is offline full backup"
echo " -v : Cohesity View that is configured to be the target for Oracle backup"
echo " -u : Retention time (days to retain the backups, expired file are deleted by SBT. It is only required if -e option is not used or Cohesity policy is not used)"
echo " -e : Retention time (days to retain the backups, expired file are deleted by Oracle. It is only required if retention is managed by oracle only)"
echo " "
echo " Optional Parameters"
echo " -r : Target connection (example: \"<dbuser>/<dbpass>@<target connection string> as sysbackup\", optional if it is local backup)"
echo " -c : Catalog connection (example: \"<dbuser>/<dbpass>@<catalog connection string>\", optional)"
echo " -n : Rac nodes connectons strings that will be used to do backup (example: \"<rac1-node connection string,ora2-node connection string>\")"
echo " -p : number of channels (Optional, default is 4)"
echo " -f : The file lists Cohesity Cluster VIPs (default name is vip-list and default directory is config)"
echo " -s : Cohesity SBT library name including directoy or just directory (default name is libsbt_aix_powerpc.so, default directory is lib) "
echo " -l : Archive logs retain days (days to retain the local archivelogs before deleting them. default is 1 day, "no" means not deleting local archivelogs on disk)"
echo " -b : Number of times backing Archive logs (default is 1.)"
echo " -m : ORACLE_HOME (default is /etc/oratab, optional.)"
echo " -z : section size in GB (Optional, default is no section size)"
echo " -t : RMAN TAG"
echo " -k : RMAN compression (Optional, yes means RMAN compression. no means no RMAN compression. default is no)"
echo " -w : yes means preview rman backup scripts"
echo "

"
}

while getopts ":r:c:h:n:o:a:i:y:f:v:s:p:e:l:b:z:k:m:t:u:w:" opt; do
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
    k ) compression=$OPTARG;;
    w ) preview=$OPTARG;;
  esac
done


#echo ${targetc}, ${catalogc}, $retday, $arch, $dbname, $vipfile, $host, $view

# Check required parameters
# Check required parameters
# check whether "\" is in front of "
set -A fullcommand -- "$@"
lencommand=${#fullcommand[@]}
#echo $lencommand
i=0
while [ $i -lt $lencommand ]
do
   if [[ ${fullcommand[$i]} == *\"* ]]; then
      echo " \ shouldn't be part of input. Please remove \."
      exit 2 
   fi
   i=$((i + 1))
done

# check some input syntax
i=0
while [ $i -lt $lencommand ]
do
   if [[ ${fullcommand[$i]} == -a ]]; then
      archset=yes
   fi
   i=$((i + 1))
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
while [ $i -lt $lencommand ]
do
   if [[ ${fullcommand[$i]} == -g ]]; then
      encryptionset=yes
   fi
   i=$((i + 1))
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
while [ $i -lt $lencommand ]
do
   if [[ ${fullcommand[$i]} == -x ]]; then
      grpctypeset=yes
   fi
   i=$((i + 1))
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
while [ $i -lt $lencommand ]
do
   if [[ ${fullcommand[$i]} == -d ]]; then
      sdedupset=yes
   fi
   i=$((i + 1))
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
while [ $i -lt $lencommand ]
do
   if [[ ${fullcommand[$i]} == -w ]]; then
      previewset=yes
   fi
   i=$((i + 1))
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
while [ $i -lt $lencommand ]
do
   if [[ ${fullcommand[$i]} == -k ]]; then
      compressionset=yes
   fi
   i=$((i + 1))
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

if test $view
then
  :
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

if test $retday || test $sretday
then
  :
else
  show_usage
  exit 1
fi

if test $retday && test $sretday
then
  echo "Either provide option for -e or for -u or none. Both are not allowed"  
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
        echo "Backup type $level specified is not correct. It needs to be offline or full"
        exit 1
     fi
  fi
fi

if [[ -z $TAG ]]; then
   if [ "$level" -eq 0 ] || [ "$level" = "offline" ] || [ "$level" = "full" ]; then
     TAG=full_${DATE_SUFFIX}
   else
     TAG=incremental_${DATE_SUFFIX}
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

function get_oracle_info {

i=0
while IFS= read -r line
do
  if [[ $i -eq 1 ]]; then
     output=`echo $line | xargs`
     i=$((i + 1)) 
  fi
  case $line in
     *-*) 
	i=$((i + 1))
        ;;
     *)
        echo test > /dev/null
        ;;
  esac
done < $1

echo $output > /dev/null

}

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
  OLDIFS="$IFS"
  IFS=","
  set -A oldarrconns $racconns
  IFS="$OLDIFS"
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
       case $conn in
          */*)
             host=`echo $conn | awk -F '/' '{print $1}'`
             case $host in
                ":")
	           host=`echo $host | awk -F ':' '{print $1}'`
                   ;;
		*)
                   echo "host is $host"
                   ;;
	     esac 
             ;;
          *)
             echo "Connect String is $conn"
             ;;
       esac 
    fi
    if [[ -z $systype ]]; then
       systype=sysdba
    fi
    sqllogin="sqlplus ${cred}@${conn} as $systype"
    if [[ -z $dbname ]]; then
       case $conn in
          */*)
             dbname=`echo $conn | awk -F '/' 'NF>1{print $NF}'`
             ;;
          *)
             dbname=$conn
             ;;
       esac 
    fi
  fi
fi

echo target connection is ${targetc}

DIRcurrent=$0
DIR=`dirname $DIRcurrent`
FIRST_CHAR=$(echo "$DIR" | cut -c1)

if [[ "$FIRST_CHAR" != "/" ]]; then
  if [[ "$DIR" = '.' ]]; then
    DIR=$(pwd)
  else
    DIR=$(pwd)/${DIR}
  fi
fi

if [[ ! -d $DIR/rmanlogs/$host ]]; then
  echo " $DIR/rmanlogs/$host does not exist, create it"
  mkdir -p $DIR/rmanlogs/$host
  
  if [ $? -ne 0 ]; then
    echo "create log directory $DIR/rmanlogs/$host failed. There is a permission issue"
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
  vipfile=${DIR}/config/${dbname}-vip-list
  echo "Cohesity Cluster name is $cohesityname. VIPS will be collected and stored in $vipfile"
  nslookup $cohesityname | grep -i address | tail -n +2 | awk '{print $2}' > $vipfile
  
  if [[ ! -s $vipfile ]]; then
     echo "Cohesity Cluster name $cohesityname provided here is not in DNS"
     exit 1
  fi

  vipnum=`wc -w $vipfile | awk '{print $1}'`
  i=1
  while [ $i -lt $parallel ]; do
    nslookup $cohesityname > /dev/null
	i=$((i + 1))
  done
fi

if [[ -n $sbtname ]]; then
   if [[ $sbtname == *".so" ]]; then
      echo "we will use the sbt library provided $sbtname"
   else  
      echo "This may be a directory"
      sbtname=${sbtname}/libsbt_aix_powerpc.so
   fi
else
#    assume the sbt library is in $DIR/lib"
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

    
#set up log file name
runlog=$DIR/rmanlogs/$host/$dbname.$DATE_SUFFIX.log
runrlog=$DIR/rmanlogs/$host/${dbname}.r.$DATE_SUFFIX.log
stdout=$DIR/rmanlogs/$host/${dbname}.$DATE_SUFFIX.std
sbtlistlog=$DIR/rmanlogs/$host/${dbname}.sbtlist.$DATE_SUFFIX.log
rmanlog=$DIR/rmanlogs/$host/$dbname.rman.$DATE_SUFFIX.log
rmanloga=$DIR/rmanlogs/$host/$dbname.archive.$DATE_SUFFIX.log
rmanlogar=$DIR/rmanlogs/$host/$dbname.archive_r.$DATE_SUFFIX.log
rmanfiled=$DIR/rmanlogs/$host/$dbname.rman.$DATE_SUFFIX.rcv
rmanfilea=$DIR/rmanlogs/$host/$dbname.archive.$DATE_SUFFIX.rcv
rmanfilear=$DIR/rmanlogs/$host/$dbname.archive_r.$DATE_SUFFIX.rcv
expirelog=$DIR/rmanlogs/$host/$dbname.expire.$DATE_SUFFIX.log
obsoletelog=$DIR/rmanlogs/$host/$dbname.obsolete.$DATE_SUFFIX.log
archive_tag=archive_${DATE_SUFFIX}
ctl_tag=ctl_${DATE_SUFFIX}


#echo $host $dbname $mount $num

#trim log directory
touch $DIR/rmanlogs/$host/${dbname}.$DATE_SUFFIX.jobstart
find $DIR/rmanlogs/$host/${dbname}* -type f -mtime +7 -exec /usr/bin/rm {} \;
find $DIR/rmanlogs/$host -type f -mtime +14 -exec /usr/bin/rm {} \;

#if [ $? -ne 0 ]; then
#  echo "del old logs in $DIR/rmanlogs/$host failed" >> $runlog
#  echo "del old logs in $DIR/rmanlogs/$host failed"
#  exit 2
#fi

# get ORACLE_HOME in /etc/oratab if it is not provided in input

if [[ -z $oracle_home ]]; then

#change dbname to lowercase
#  dbname=${dbname,,}

  oratabinfo=`grep -i $dbname /etc/oratab`

#echo oratabinfo is $oratabinfo

  set -A arrinfo $oratabinfo
  leninfo=${#arrinfo[@]}

  k=0
  i=0
  while [ $i -lt $leninfo ]
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
    i=$((i + 1))
  done


  if [[ $k -eq 0 ]]; then
    oratabinfo=`grep -i ${dbname::${#dbname}-1} /etc/oratab`
    set -A arrinfo $oratabinfo
    leninfo=${#arrinfo[@]}

    j=0
    i=0
    while [ $i -lt $leninfo ]
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
      i=$((i + 1)) 
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
#  get oracle instance name. For a RAC database, the instance has a numerical number after the database name. 
    runoid=`ps -ef | grep pmon | awk 'NF>1{print $NF}' | grep -i $dbname | awk -F "pmon" '{print $2}' | sort -t _ -k 1`
    set -A arroid $runoid
    len=${#arroid[@]}

    i=0
    while [ $i -lt $len ]
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
        if echo "$lastc" | grep -qE '^[0-9]+$'; then
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
      i=$((i + 1))
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

grep -i error $stdout

if [ $? -eq 0 ]; then
   echo "Oracle query has errors, the backup won't run until the problems are fixed 

The query out file is $stdout
"
   exit 1
fi

output=""
get_oracle_info $stdout
db_name=$output

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
	  j=$((j + 1))
       else
          echo "connection string ${oldarrconns[$k]} is not valid or the instance is down, the backup will not use this connection string"
       fi
       k=$((k + 1))
   done
   echo ${arrconns[$j]}
   echo the number of valid connection is ${#arrconns[@]}
   
   if [[ ${#arrconns[@]} -eq 0 ]]; then
      echo "there is no valid connection string. Backup won't run"
      exit
   fi 
fi

export LIBPATH=$ORACLE_HOME/lib:$LIBPATH

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
CONFIGURE CONTROLFILE AUTOBACKUP FORMAT FOR DEVICE TYPE sbt_tape TO '$host/$db_name/%d_%F.ctl';
" > $rmanfiled

if [[ -n $retday ]]; then
   if [[ $dbstatus != "standby" ]]; then
      echo "
CONFIGURE retention policy to recovery window of $retday days;
" >> $rmanfiled
   fi
fi

echo "
CONFIGURE DEFAULT DEVICE TYPE TO sbt_tape;
CONFIGURE BACKUP OPTIMIZATION OFF;
CONFIGURE CONTROLFILE AUTOBACKUP ON;
CONFIGURE CONTROLFILE AUTOBACKUP FORMAT FOR DEVICE TYPE sbt_tape TO '$host/$db_name/%d_%F.ctl';
" >> $rmanfilea

j=0
k=0
while [ $j -lt $parallel ]; do

  while IFS= read -r ip; do
    
    ip=`echo $ip | xargs`    	
    if [[ -n $ip ]]; then
           lastip=$ip
       if [[ $j -eq 0 ]]; then
	  if [[ -n $cohesityname ]]; then
	     echo "CONFIGURE CHANNEL DEVICE TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,vips=$cohesityname)';" >> $rmanfiled
	  else
	     echo "CONFIGURE CHANNEL DEVICE TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,vips=$ip)';" >> $rmanfiled
	  fi
#	  echo "Delete obsolete;" >> $rmanfiled
	  echo "RUN {" >> $rmanfiled
	  echo "RUN {" >> $rmanfilea
       fi
	   
       if [[ -n $racconns ]]; then
          if [[ $j -lt $parallel ]]; then
             allocate_database[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' connect='$cred@${arrconns[$k]}' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,vips=$ip)';"
             allocate_archive[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' connect='$cred@${arrconns[$k]}' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,vips=$ip)' format '$host/$db_name/%d_%T_%U.blf';"
             unallocate[j]="release channel c$j;"
	     k=$((k + 1))
	     j=$((j + 1))
          fi
			  
    	  if [[ $k -ge ${#arrconns[@]} && $j -le $parallel ]]; then
	     k=0
	  fi
       else
	  if [[ $j -lt $parallel ]]; then
	     allocate_database[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,vips=$ip)';"
   	     allocate_archive[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,vips=$ip)' format '$host/$db_name/%d_%T_%U.blf';"
	     unallocate[j]="release channel c$j;"
          fi
          j=$((j + 1))
       fi
    fi
  done < $vipfile
done


i=0
while [ $i -lt ${#allocate_database[@]} ]
do
   echo ${allocate_database[$i]} >> $rmanfiled
   i=$((i + 1))
done

i=0
while [ $i -lt ${#allocate_archive[@]} ]
do
   echo ${allocate_archive[$i]} >> $rmanfilea
   i=$((i + 1))
done

#echo "crosscheck backup;" >> $rmanfiled
#echo "delete noprompt expired backup;" >> $rmanfiled

if [[ $level = "offline" || $level = "full" ]]; then
   if [[ -z $sectionsize ]]; then
      if [[ $compression = [Yy]* ]]; then
         echo "backup AS COMPRESSED BACKUPSET TAG '$TAG' database filesperset 1 format '$host/$db_name/%d_%T_%U_$level.bdf';" >> $rmanfiled
      else
         echo "backup TAG '$TAG' database filesperset 1 format '$host/$db_name/%d_%T_%U_$level.bdf';" >> $rmanfiled
      fi
   else
      if [[ $compression = [Yy]* ]]; then
         echo "backup AS COMPRESSED BACKUPSET TAG '$TAG' database section size ${sectionsize}G filesperset 1 format '$host/$db_name/%d_%T_%U_$level.bdf';" >> $rmanfiled
      else
         echo "backup TAG '$TAG' database section size ${sectionsize}G filesperset 1 format '$host/$db_name/%d_%T_%U_$level.bdf';" >> $rmanfiled
      fi
   fi
else
   if [[ -z $sectionsize ]]; then
      if [[ $compression = [Yy]* ]]; then
         echo "backup AS COMPRESSED BACKUPSET INCREMENTAL LEVEL $level CUMULATIVE TAG '$TAG' database filesperset 1 format '$host/$db_name/%d_%T_%U_level${level}.bdf';" >> $rmanfiled
      else
         echo "backup INCREMENTAL LEVEL $level CUMULATIVE TAG '$TAG' database filesperset 1 format '$host/$db_name/%d_%T_%U_level${level}.bdf';" >> $rmanfiled
      fi
   else
      if [[ $compression = [Yy]* ]]; then
         echo "backup backup AS COMPRESSED BACKUPSET INCREMENTAL LEVEL $level CUMULATIVE TAG '$TAG' database section size ${sectionsize}G filesperset 1 format '$host/$db_name/%d_%T_%U_level${level}.bdf';" >> $rmanfiled
      else
         echo "backup INCREMENTAL LEVEL $level CUMULATIVE TAG '$TAG' database section size ${sectionsize}G filesperset 1 format '$host/$db_name/%d_%T_%U_level${level}.bdf';" >> $rmanfiled
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
elif perl -e "if ($archretday == 0) { exit 0 } else { exit 1 }"; then
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

echo "BACKUP TAG '$ctl_tag' CURRENT CONTROLFILE format '$host/$db_name/%d_%T_%U.ctl';" >> $rmanfiled

#i=0
#while [ $i -lt  ${#unallocate[@]} ]
#do
#   echo ${unallocate[$i]} >> $rmanfiled
#   echo ${unallocate[$i]} >> $rmanfilea
#   i=$((i + 1))
#done

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
CONFIGURE CONTROLFILE AUTOBACKUP FORMAT FOR DEVICE TYPE sbt_tape TO '$host/$db_name/%d_%F.ctl';

RUN {
" > $rmanfilear

i=1
j=0
while [ $j -lt $parallel ]; do

  while IFS= read -r ip; do
    
    ip=`echo $ip | xargs`    	
    if [[ -n $ip ]]; then
	   	
       if [[ $j -lt $parallel ]]; then
          allocate_archive[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,vips=$ip)' format '$host/$db_name/%d_%T_%U.blf';"
	  unallocate[j]="release channel c$j;"  
       fi
       i=$((i + 1))
       j=$((j + 1))	  
    fi
  done < $vipfile
done

i=0
while [ $i -lt ${#allocate_archive[@]} ]
do
   echo ${allocate_archive[$i]} >> $rmanfilear
   i=$((i + 1))
done

if [[ $archretday = [Nn]* ]]; then
   if [[ $compression = [Yy]* ]]; then
      echo "backup AS COMPRESSED BACKUPSET TAG '$archive_tag' archivelog all filesperset 8 not backed up $archcopynum times;" >> $rmanfilear
   else
      echo "backup TAG '$archive_tag' archivelog all filesperset 8 not backed up $archcopynum times;" >> $rmanfilear
   fi
elif perl -e "if ($archretday == 0) { exit 0 } else { exit 1 }"; then
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

i=0
while [ $i -lt ${#unallocate[@]} ]
do
   echo ${unallocate[$i]} >> $rmanfilear
   i=$((i + 1))
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

output=""
get_oracle_info $stdout
open_mode=$output

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

   output=""
   get_oracle_info $stdout
   open_mode=$output


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
  exit 1
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
#  while IFS= read -r line 
#  do
#    echo $line
#  done < $rmanloga 
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
#  while IFS= read -r line
#  do
#    echo $line
#  done < $rmanlogar
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

function delete_expired_file {
  
#let sretnewday=$sretday+1
let sretnewday=$sretday
echo "Clean backup files older than $sretnewday started at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog
echo "Clean backup files older than $sretnewday started at " `/bin/date '+%Y%m%d%H%M%S'` >> $sbtlistlog
echo "only delete old expired backup during database backup" >> $runlog
if [[ -n $cohesityname ]]; then
   echo $DIR/tools/sbt_list --view=$view/$host/$db_name --vips=$cohesityname --purge_view=true --days_before=$sretnewday --silent_mode=true >> $sbtlistlog
   $DIR/tools/sbt_list --view=$view/$host/$db_name --vips=$cohesityname --purge_view=true --days_before=$sretnewday --silent_mode=true >> $sbtlistlog
else
   $DIR/tools/sbt_list --view=$view/$host/$db_name --vips=$lastip --purge_view=true --days_before=$sretnewday --silent_mode=true >> $sbtlistlog
fi
if [ $? -eq 0 ]; then
   echo "Clean backup files older than $sretnewday finished at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog
   echo "Clean backup files older than $sretnewday finished at " `/bin/date '+%Y%m%d%H%M%S'` >> $sbtlistlog
else
   echo "Clean backup files older than $sretnewday failed at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog
   echo "Clean backup files older than $sretnewday failed at " `/bin/date '+%Y%m%d%H%M%S'` >> $sbtlistlog
fi 
}

function del_obsolete_record {

# Clean Oracle backup record in control file or Oracle recovery catalog

if [[ -z $catalogc ]]; then
   rman log $obsoletelog << EOF > /dev/null
   connect target '${targetc}'
   crosscheck backup device type sbt;
   delete noprompt expired backup device type sbt;
   Delete noprompt obsolete device type sbt;
   exit
EOF
else
   rman log $obsoletelog << EOF > /dev/null
   connect target '${targetc}'
   connect catalog '${catalogc}'
   crosscheck backup device type sbt;
   delete noprompt expired backup device type sbt;
   Delete noprompt obsolete device type sbt
   exit
EOF
fi

grep -i error $obsoletelog
 
if [ $? -eq 0 ]; then
   echo "Delete obsolete failed. The error message is in log file $obsoletelog"
#   exit 1
else
   echo "Delete obsolete is successful."
fi

}

function sync_oracle_record {

# Clean Oracle backup record in control file or Oracle recovery catalog

if [[ -z $catalogc ]]; then
   rman log $expirelog << EOF > /dev/null
   connect target '${targetc}'
   crosscheck backup device type sbt;
   delete noprompt expired backup device type sbt;
   exit
EOF
else
   rman log $expirelog << EOF > /dev/null
   connect target '${targetc}'
   connect catalog '${catalogc}'
   crosscheck backup device type sbt;
   delete noprompt expired backup device type sbt;
   exit
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
    if [[ $level == "offline" ]]; then
       database_mount
       backup
       database_startup
    else
       backup
       archive
    fi
    if [[ -n $sretday ]]; then
       delete_expired_file
       sync_oracle_record
    fi
    if [[ -n $retday ]]; then
       del_obsolete_record 
    fi
  fi
  grep -i error $runlog

  if [ $? -eq 0 ]; then
    echo "Backup may be successful. However there are IPs in $vipfile not reachable"
#  exit 1
  fi
fi
