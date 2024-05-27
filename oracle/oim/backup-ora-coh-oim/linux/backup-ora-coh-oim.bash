#!/bin/bash
#
# Name:         backup-ora-coh-oim.bash
#
# Function:     This script backup oracle using Oracle Incremental Merge
#               using nfs mount. It can do incremental backup and use Oracle
#               recovery catalog. It can do archive log backup only. The retention 
#               time is in days. If the retention time is unlimit, specify unlimit.
#		        It only deletes the backup files. It won't clean RMAN catalog.
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
# 10/23/21 Diana Yang   Improve catalog performance
# 11/04/21 Diana Yang   Add Oracle section size option
# 01/02/22 Diana Yang   Add MAX throughput limit allowed for RMAN backup
# 01/11/22 Diana Yang   Work with any case oracle database name (regardless uppercase or lowercase)
# 09/07/22 Diana Yang   Check whether database is RAC or not.
# 02/08/22 Diana Yang   Add more log info. for troubleshooting
# 08/17/23 Diana Yang   Check any pdb database is in mount mode and added it to the output
# 08/29/23 Diana Yang   Delete the datafile copy that haven't changed for 30 days. In read only situation, a new backup will run.
# 09/28/23 Diana Yang   Delete the expired files before clone start.
# 10/30/23 Diana Yang   Prevent cleaning the database files in DG standby backup
#
#################################################################

function show_usage {
echo "usage: backup-ora-coh-oim.bash -r <Target connection> -c <Catalog connection> -h <host> -d <rac-node1-conn,rac-node2-conn,...> -o <Oracle_DB_Name> -t <backup type> -a <archive only> -y <Cohesity-cluster> -v <view> -u <Cohesity Oracle User> -g <AD Domain> -z <section size> -m <mount-prefix> -n <number of mounts> -p <number of channels> -e <retention> -s <python script directory> -l <archive log keep days> -b <ORACLE_HOME> -f <number of archive logs> -x <Max throughput> -i <yes/no> -w <yes/no>" 
echo " "
echo " Required Parameters"
echo " -h : host (scanname is required if it is RAC. optional if it is standalone.)"
echo " -o : ORACLE_DB_NAME (Need to have an entry of this database in /etc/oratab. If it is RAC, it is db_unique_name)"
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
echo " -b : ORACLE_HOME (default is /etc/oratab, optional.)"
echo " -x : Maximum throughput (default is no limit. Unit is MB/sec. Archivelog backup throughput will be 20% of max throughput if database backup is running)"
echo " -i : yes means using Cohesity API Key, no means using Cohesity user/password. Default is no"
echo " -w : yes means preview rman backup scripts"
}

while getopts ":r:c:h:d:o:a:t:y:v:u:g:z:m:n:p:s:e:l:f:b:x:i:w:" opt; do
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
    i ) apikey=$OPTARG;;
    w ) preview=$OPTARG;;
  esac
done

#echo $dbname, $mount, $host, $num

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
   if [[ ${fullcommand[$i]} == -i ]]; then
      apikeyset=yes
   fi
done
if [[ -n $apikeyset ]]; then
   if [[ -z $apikey ]]; then
      echo "Please enter 'yes' as the argument for -i. It may be empty or not all options are given an argument. All options should be given an arguments"
      exit 2
   else
      if [[ $apikey != [Yy]* ]]; then
         echo "'yes' should be provided after -i in syntax, other answer is not valid"
	 exit 2
      fi 
   fi
fi
								
if test $mount && test $num && test $retday
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

if [[ $num -le 0 ]]; then
   echo "The argument for -n has to be larger than 0"
   exit 1
fi

DATE_SUFFIX=`/bin/date '+%Y%m%d%H%M%S'`
#echo $DATE_SUFFIX

if [[ $arch = "arch" || $arch = "Arch" || $arch = "ARCH" || $arch = "yes" || $arch = "Yes" || $arch = "YES" ]]; then
  echo "Only backup archive logs"
  archivelogonly=yes
else
  echo "Will backup database backup plus archive logs"
 
  if test $cohesityname && test $view && test $cohesityuser
  then
    :
  else
    echo "Cohesity cluster, view, user information should be provided"
    show_usage
    exit 1
  fi
  
  if [[ -z $addomain ]]; then
      addomain=local
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

function get_oracle_info {

i=0
while IFS= read -r line
do
  if [[ $i -eq 1 ]]; then
     output=`echo $line | xargs`
     i=$[$i+1]
  fi
  if [[ $line =~ "-" ]];then
     i=$[$i+1]
  fi
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

if test $max_throughput
then
   ((channel_thr=${max_throughput} / $parallel))
   ((arch_chan_parallel_thr=${channel_thr} / 5))
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

#echo target connection is ${targetc}


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

logdir=$DIR/log/$host
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
origfilelist=$DIR/log/$host/${dbname}.origfiles.all.$DATE_SUFFIX
tag=${dbname}_${DATE_SUFFIX}
expirelog=$DIR/log/$host/$dbname.expire.$DATE_SUFFIX.log

#echo $host $oracle_sid $mount $num

#trim log directory
touch $DIR/log/$host/${dbname}.$DATE_SUFFIX.jobstart
find $DIR/log/$host/${dbname}* -type f -mtime +7 -exec /bin/rm {} \;
find $DIR/log/$host/* -type f -mtime +14 -exec /bin/rm {} \;

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

if [[ -z ${oracle_home} ]]; then
   oracle_home=`env | grep ORACLE_HOME | awk -F '=' '{print $2}'`
fi

echo "check whether rman is in the command path"
which rman

if [ $? -ne 0 ]; then
  echo "oracle home $oracle_home provided or found in /etc/oratab is incorrect"
  exit 1
fi
echo "
Yes, rman is in the command path"

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
echo "The backup will use remote connection provided by "-r" argument"
# echo "target connection is $targetc"
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
#   echo "catalog connection is $catalogc"
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

get_oracle_info $stdout
db_name=$output

$sqllogin << EOF > /dev/null
   spool $stdout
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

# determine the datafilecopy directory when the backup is incremental
echo "determine the datafilecopy directory when the backup is incremental"

backup_dir=$host/$dbname
if [[  $ttype = "incre" || $ttype = "Incre" || $ttype = "INCRE" ]]; then

   rm $stdout
   $sqllogin << EOF > /dev/null
   spool $stdout replace
   SET LINES 300
   select FNAME from v\$backup_files 
   where BACKUP_TYPE='COPY' and FILE_TYPE='DATAFILE' and TAG='INCRE_UPDATE';
EOF

   if [ $? -ne 0 ]; then
      echo "Some part of this connection string \"$sqllogin\" is incorrect"
      exit 1
   fi

   get_oracle_info $stdout
   dbcopyfile=$output   

   if [[ -n $dbcopyfile ]]; then
      dbsrcdir=`echo ${dbcopyfile} | awk 'BEGIN{FS=OFS="/"}{NF--; print}'`
		if [[ -n $dbsrcdir ]]; then
         echo "The full backup directory is $dbsrcdir"
         echo "The full backup directory is $dbsrcdir" >> $runlog

         dbsrctopdir=`echo ${dbsrcdir} | awk 'BEGIN{FS=OFS="/"}{NF--; print}'`
         origdbname=`echo ${dbsrctopdir} | awk -F "/" '{print $NF}'` 
         orighost=`echo ${dbsrctopdir} | awk 'BEGIN{FS=OFS="/"}{NF--; print}' | awk -F "/" '{print $NF}'`

         if [[ $host != $orighost ]]; then
            echo "The original Host of the full backup is $orighost which is different from the current host $host"
            echo "The original Host if the full backup is $orighost which is different from the current host $host" >> $runlog
            echo "If the full backup directory should use the current host, run a full backup"
            echo "If the full backup directory should use the current host, run a full backup"  >> $runlog
         fi
         echo "The original dbname is $origdbname"
         echo "The original dbname is $origdbname" >> $runlog
         backup_dir=$orighost/$origdbname
      fi
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
CONFIGURE DEFAULT DEVICE TYPE TO disk;
CONFIGURE BACKUP OPTIMIZATION OFF;
CONFIGURE DEVICE TYPE DISK PARALLELISM $parallel BACKUP TYPE TO BACKUPSET;
CONFIGURE CONTROLFILE AUTOBACKUP ON;
CONFIGURE CONTROLFILE AUTOBACKUP FORMAT FOR DEVICE TYPE DISK TO '${mount}1/$host/$dbname/controlfile/%d_%F.ctl';
" > $rmanfiled1
			  
if [[ $dbstatus != "standby" ]]; then
echo "
CONFIGURE retention policy to recovery window of $retday days;
" >> $rmanfiled1
fi

echo " 
RUN {
" >> $rmanfiled1

echo " 
RUN {
" >> $rmanfiled2

echo "
CONFIGURE DEFAULT DEVICE TYPE TO disk;
CONFIGURE BACKUP OPTIMIZATION OFF;
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

if [[ $ttype = "full" || $ttype = "Full" || $ttype = "FULL" ]]; then
   echo "Full backup" 
   echo "Full backup" >> $runlog
   echo "
   crosscheck datafilecopy all;
   delete noprompt expired datafilecopy all;
   delete noprompt copy of database tag 'incre_update'; " >> $rmanfiled1
   
   if [[ -z $sectionsize ]]; then
      echo "backup incremental level 1 for recover of copy with tag 'incre_update' database filesperset 8; " >> $rmanfiled1
   else
      echo "backup SECTION SIZE ${sectionsize}G incremental level 1 for recover of copy with tag 'incre_update' database filesperset 8; " >> $rmanfiled1 
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
      echo "backup SECTION SIZE ${sectionsize}G incremental level 1 for recover of copy with tag 'incre_update' database filesperset 8; " >> $rmanfiled1 
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

#for (( i=0; i < ${#unallocate[@]}; i++ )); do
#   echo ${unallocate[$i]} >> $rmanfiled1
#   echo ${unallocate[$i]} >> $rmanfilea
#done

#for (( i=0; i < ${#unallocate_incre[@]}; i++ )); do
#   echo ${unallocate_incre[$i]} >> $rmanfiled2
#done

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
   $sqllogin << EOF > /dev/null
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
CONFIGURE BACKUP OPTIMIZATION OFF;
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

#for (( i=0; i < ${#unallocate[@]}; i++ )); do
#   echo ${unallocate[$i]} >> $rmanfilear
#done

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
rman log $catalog_log << EOF > /dev/null
 connect target '${targetc}'
" >> $catalog_bash
else
echo "
rman log $catalog_log << EOF > /dev/null
connect target '${targetc}'
connect catalog '${catalogc}'
" >> $catalog_bash
fi

echo "
CONFIGURE DEFAULT DEVICE TYPE TO disk;
CONFIGURE BACKUP OPTIMIZATION OFF;
CONFIGURE CONTROLFILE AUTOBACKUP ON;
CONFIGURE CONTROLFILE AUTOBACKUP FORMAT FOR DEVICE TYPE DISK TO '${mount}1/$host/$dbname/controlfile/%d_%F.ctl';
" >> $catalog_bash
#cd ${mount}1/$host/$dbname/datafile.$DATE_SUFFIX


if [[ -n $orighost ]]; then
  cd ${mount}1/$orighost/$origdbname/datafile
else
  cd ${mount}1/$host/$dbname/datafile
fi
	 
num_dfile=`ls *_data_*| wc -l`
dfile=(`ls *_data_*`)
i=1
j=0
k=1
while [ $i -le $num ]; do
  	
  if [[ $j -lt $num_dfile ]]; then
     if [[ $k -eq 1 ]]; then
	if [[ -n $orighost ]]; then
           echo "CATALOG DATAFILECOPY 	 
        '${mount}${i}/$orighost/$origdbname/datafile.$DATE_SUFFIX/${dfile[$j]}'"  >> $catalog_bash
	else
	   echo "CATALOG DATAFILECOPY 	 
        '${mount}${i}/$host/$dbname/datafile.$DATE_SUFFIX/${dfile[$j]}'"  >> $catalog_bash
	fi
     else
	if [[ -n $orighost ]]; then
           echo ",'${mount}${i}/$orighost/$origdbname/datafile.$DATE_SUFFIX/${dfile[$j]}'"  >> $catalog_bash
	else
	   echo ",'${mount}${i}/$host/$dbname/datafile.$DATE_SUFFIX/${dfile[$j]}'"  >> $catalog_bash
	fi
     fi
  fi

  i=$[$i+1]
  j=$[$j+1]
  k=$[$k+1]


  if [[ $i -gt $num && $j -le $num_dfile ]]; then 
     i=1
  fi
  
  if [[ $k -gt 200 && $j -le $num_dfile ]];then
     echo " tag '${tag}';" >> $catalog_bash
     k=1
  fi
  
done

if [[ $j -gt $num_dfile ]]; then
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
CREATE PFILE='$pfile_path' FROM spfile;
EOF

# backup spfile
echo "backup spfile" >> $runlog
if [[ -z $catalogc ]]; then
   rman log $rmanlogs << EOF > /dev/null
   connect target '${targetc}'
   BACKUP AS COPY SPFILE format '${mount}1/$host/$dbname/spfile/spfile%d.%T_%U.ora';
   alter database backup controlfile to trace as '${mount}1/$host/$dbname/spfile/controltrace.$DATE_SUFFIX.sql';
EOF
else
   rman log $rmanlogs << EOF > /dev/null
   connect target '${targetc}'
   connect catalog '${catalogc}'
   BACKUP AS COPY SPFILE format '${mount}1/$host/$dbname/spfile/spfile%d.%T_%U.ora';
   alter database backup controlfile to trace as '${mount}1/$host/$dbname/spfile/controltrace.$DATE_SUFFIX.sql';
EOF
fi

if [[ -z $catalogc ]]; then
   rman log $rmanlog1 << EOF > /dev/null
   connect target '${targetc}'
   @$rmanfiled1
EOF
else
   rman log $rmanlog1 << EOF > /dev/null
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

if [[ $dbstatus != "standby" ]]; then
rman << EOF
connect target '${targetc}'
sql 'alter system switch logfile';
exit
EOF
fi

}

function backup2 {

echo "Database incremental merge started at " `/bin/date '+%Y%m%d%H%M%S'`
echo "Database incremental merge started at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog


if [[ -z $catalogc ]]; then
   rman log $rmanlog2 << EOF > /dev/null
   connect target '${targetc}'
   @$rmanfiled2
EOF
else
   rman log $rmanlog2 << EOF > /dev/null
   connect target '${targetc}'
   connect catalog '${catalogc}'
   @$rmanfiled2
EOF
fi

if [ $? -ne 0 ]; then
  echo "
  Database incremental merge failed at " `/bin/date '+%Y%m%d%H%M%S'`
  echo "
  Database incremental merge failed at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog
  while IFS= read -r line
  do
    echo $line
  done < $rmanlog2
  exit 1
else
  echo "
  Database incremental merge finished at " `/bin/date '+%Y%m%d%H%M%S'`
  echo "
  Database incremental merge finished at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog 
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

function early() {
  perl -e '
    $t=time()-'${1:-30}'*86400;
    @t=localtime($t);
    printf("%04d%02d%02d%02d%02d%02d",$t[5]+1900,$t[4]+1,$t[3],$t[2],$t[1],$t[0]);'
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
    echo direcory "${mount}1/$host/$dbname" exist
    echo direcory "${mount}1/$host/$dbname" exist >> $runlog
    if [[ -d ${mount}1/$host/$dbname/datafile ]]; then
       find ${mount}1/$host/$dbname/datafile/* -type f | grep -v D-${db_name^^}_ >> ${filelist}
       find ${mount}1/$host/$dbname/datafile/* -type f -mtime +30 -exec /bin/rm -v {} \; >> $runlog
    fi
    find ${mount}1/$host/$dbname/archivelog/* -type f -mtime +$retnewday  -exec /bin/rm -v {} \; >> $runlog
    find ${mount}1/$host/$dbname/controlfile/* -type f -mtime +$retnewday  -exec /bin/rm -v {} \; >> $runlog
    find ${mount}1/$host/$dbname/spfile/* -type f -mtime +$retnewday  -exec /bin/rm -v {} \; >> $runlog
#    find ${mount}1/$host/$dbname/* -type d -mtime +$retnewday -prune -exec rm -rv {} \; >> $runlog

    echo "
    find the datafile.* directories that are created +$retnewday ago and delete them"
	
	expiretime=`early $retnewday`
    for i in `ls -d ${mount}1/$host/$dbname/datafile.*`
    do
       createdtime=`echo $i | awk -F "." '{print $2}'`
       if [[ $createdtime -le $expiretime ]]; then
	  echo /bin/rm -rv $i >> $runlog
       fi
    done

    echo "finish the deletion of old datafile.* directories
    "
   
	
 #   filenum=`wc -l ${filelist} | awk '{print $1}'`
 
    if [[ -f ${filelist} ]]; then
       while IFS= read -r line
       do
         /bin/rm -v $line >> $runlog

         if [ $? -ne 0 ]; then
            echo "Delete backup files $line failed"
            echo "Delete backup files $line failed" >> $runlog 
         fi
       done < ${filelist}
    fi
	
   
#    find ${mount}1/$host/$dbname -depth -type d -empty -exec /bin/rmdir -v {} \; >> $runlog   
	
    if [ $? -ne 0 ]; then
       echo "Clean backup files in ${mount}1/$host/$dbname directory older than $retnewday failed at " `/bin/date '+%Y%m%d%H%M%S'`
       echo "Clean backup files in ${mount}1/$host/$dbname directory older than $retnewday failed at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog
    else
       echo "Clean backup files in ${mount}1/$host/$dbname directory older than $retnewday finished at " `/bin/date '+%Y%m%d%H%M%S'`
       echo "Clean backup files in ${mount}1/$host/$dbname directory older than $retnewday finished at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog
    fi
  else
    echo direcory "${mount}1/$host/$dbname" does not exist
    echo direcory "${mount}1/$host/$dbname" does nit exist >> $runlog
    ls -l ${mount}1/$host
    ls -l ${mount}1/$host >> $runlog
  fi
  
  if [[ -n $orighost ]]; then
     if [[ -d "${mount}1/$orighost/$origdbname" ]]; then
        echo direcory "${mount}1/$orighost/$origdbname" exist
        echo direcory "${mount}1/$orighost/$origdbname" exist >> $runlog
        if [[ -d ${mount}1/$orighost/$origdbname/datafile ]]; then
           find ${mount}1/$orighost/$origdbname/datafile/* -type f | grep -v D-${db_name^^}_ >> ${origfilelist}
        fi
        find ${mount}1/$orighost/$origdbname/archivelog/* -type f -mtime +$retnewday  -exec /bin/rm -v {} \; >> $runlog
        find ${mount}1/$orighost/$origdbname/controlfile/* -type f -mtime +$retnewday  -exec /bin/rm -v {} \; >> $runlog
        find ${mount}1/$orighost/$origdbname/spfile/* -type f -mtime +$retnewday  -exec /bin/rm -v {} \; >> $runlog
#        find ${mount}1/$orighost/$origdbname/* -type d -mtime +$retnewday -prune -exec /bin/rm -rv {} \; >> $runlog
        echo "
        find the datafile.* directories that are created +$retnewday ago and delete them"
	
        expiretime=`early $retnewday`
        for i in `ls -d ${mount}1/$orighost/$origdbname/datafile.*`
        do
           createdtime=`echo $i | awk -F "." '{print $2}'`
           if [[ $createdtime -le $expiretime ]]; then
	      echo /bin/rm -rv $i >> $runlog
           fi
        done

        echo "finish the deletion of old datafile.* directories
        "
	
 #   filenum=`wc -l ${filelist} | awk '{print $1}'`
 
        if [[ -f ${origfilelist} ]]; then
           while IFS= read -r line
           do
             /bin/rm -v $line >> $runlog

             if [ $? -ne 0 ]; then
               echo "Delete backup files $line failed"
               echo "Delete backup files $line failed" >> $runlog 
             fi
           done < ${origfilelist}
        fi
	
   
#        find ${mount}1/$orighost/$origdbname -depth -type d -empty -exec /bin/rmdir -v {} \; >> $runlog
	
        if [ $? -ne 0 ]; then
          echo "Clean backup files in ${mount}1/$orighost/$origdbname directory older than $retnewday failed at " `/bin/date '+%Y%m%d%H%M%S'`
          echo "Clean backup files in ${mount}1/$orighost/$origdbname directory older than $retnewday failed at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog
        else
          echo "Clean backup files in ${mount}1/$orighost/$origdbname directory older than $retnewday finished at " `/bin/date '+%Y%m%d%H%M%S'`
          echo "Clean backup files in ${mount}1/$orighost/$origdbname directory older than $retnewday finished at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog
        fi
     else
       echo direcory "${mount}1/$orighost/$origdbname" does not exist
       echo direcory "${mount}1/$orighost/$origdbname" does nit exist >> $runlog
       ls -l ${mount}1/$orighost
       ls -l ${mount}1/$orighost >> $runlog
     fi
  fi
fi

}

function run_snapshot_catalog {

# create snapshot of backup files in backup_dir/datafile directory


src_datafile_dir=/$view/${backup_dir}/datafile
tgt_datafile_dir=/$view/${backup_dir}/datafile.$DATE_SUFFIX
if [[ -d ${tgt_datafile_dir} ]]; then
   echo "target clone directory ${tgt_datafile_dir} was created by other methods"
   echo "target clone directory ${tgt_datafile_dir} was created by other methods" >> $runlog
   ls -ld ${tgt_datafile_dir}
   ls -ld ${tgt_datafile_dir} >> $runlog
   ls -l ${tgt_datafile_dir}
   ls -l ${tgt_datafile_dir} >> $runlog
   echo "delete the direcory ${tgt_datafile_dir}"
   /bin/rm -r ${tgt_datafile_dir}
   sleep 10
fi

echo "
clone directory $src_datafile_dir started at " `/bin/date '+%Y%m%d%H%M%S'`
echo "
clone directory $sqlplus started at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog

   
if [[ -z $apikey ]]; then 
   $pyname -v $cohesityname -u $cohesityuser -d $addomain -s $src_datafile_dir -t $tgt_datafile_dir -l $logdir 
else
   if [[ $apikey = [Yy]* ]]; then
       $pyname -v $cohesityname -u $cohesityuser -i -s $src_datafile_dir -t $tgt_datafile_dir -l $logdir 
   else
       $pyname -v $cohesityname -u $cohesityuser -d $addomain -s $src_datafile_dir -t $tgt_datafile_dir -l $logdir 
   fi
fi

if [ $? -ne 0 ]; then
  echo "Cohesity snapshot backup files in $src_datafile_dir failed at " `/bin/date '+%Y%m%d%H%M%S'`
  echo "Cohesity snapshot backup files in $src_datafile_dir failed at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog
  if [[ -d ${tgt_datafile_dir} ]]; then 
     echo "Even the clone job returns none zero error code, the target directory ${tgt_datafile_dir} was created"
  else
     exit 1
  fi
else
  echo "Cohesity snapshot backup files in $src_datafile_dir finished at " `/bin/date '+%Y%m%d%H%M%S'`
  echo "Cohesity snapshot backup files in $src_datafile_dir finished at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog
fi

}

function sync_oracle_record {

# Clean Oracle backup record in control file or Oracle recovery catalog

if [[ -z $catalogc ]]; then
   rman log $expirelog << EOF > /dev/null
   connect target '${targetc}'
   crosscheck datafilecopy all;
   crosscheck  backup;
   crosscheck  archivelog all;
   delete noprompt expired archivelog all;
   delete noprompt expired datafilecopy all;
   delete noprompt expired backup;
   exit
EOF
else
   rman log $expirelog << EOF > /dev/null
   connect target '${targetc}'
   connect catalog '${catalogc}'
   crosscheck datafilecopy all;
   crosscheck  backup;
   crosscheck  archivelog all;
   delete noprompt expired archivelog all;
   delete noprompt expired datafilecopy all;
   delete noprompt expired backup;
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
    cat $rmanfiled1
    cat $rmanfiled2
    echo " "
    echo "---------------"
    if [[ -n $orighost ]]; then
       catalog_snapshot
       echo ORACLE CATALOG SNAPSHOT BACKUP FILES BASH SCRIPT is
       ls $catalog_bash
    fi
    echo Python script to create snapshot
    if [[ -z $apikey ]]; then 
       echo $pyname -v $cohesityname -u $cohesityuser -d $addomain -s /$view/${backup_dir}/datafile -t /$view/${backup_dir}/datafile.$DATE_SUFFIX -l $logdir 
    else
       if [[ $apikey = [Yy]* ]]; then
          echo $pyname -v $cohesityname -u $cohesityuser -i -s /$view/${backup_dir}/datafile -t /$view/${backup_dir}/datafile.$DATE_SUFFIX -l $logdir 
       else
          echo $pyname -v $cohesityname -u $cohesityuser -d $addomain -s /$view/${backup_dir}/datafile -t /$view/${backup_dir}/datafile.$DATE_SUFFIX -l $logdir
       fi
    fi
    echo "---------------"
  else
    backup1
    backup2
    archive
    echo " "
    delete_expired
    sleep 5
    run_snapshot_catalog
    catalog_snapshot
    sleep 5
# RMAN catalog the snapshot backup file
    echo " "
    $catalog_bash
    sync_oracle_record	
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

#record offset
if [[ -d ${mount}1/$host/$dbname/spfile ]]; then
   ((timezoneoffset=`/bin/date -u '+%Y%m%d%H%M%S'`-`/bin/date '+%Y%m%d%H%M%S'`))
   echo $timezoneoffset > ${mount}1/$host/$dbname/spfile/timezoneoffset-file
fi
