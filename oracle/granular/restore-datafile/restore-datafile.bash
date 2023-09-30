#!/bin/bash
#
# Name:         restore-datafile.bash
#
# Function:     This script restore Oracle datafiles from Oracle backup.
#               It checks the datafile online status first. If it is online, it will bring it offline first
#               once it is given the permission. 
# Warning:      Restore can overwrite the existing datafile. This script needs to be used in caution.
#               The author accepts no liability for damages resulting from its use.
#
#
# Show Usage: run the command to show the usage
#
# Changes:
# 06/12/23 Diana Yang   New script
# 08/31/23 Diana Yang   Handle the database in mount situation
#
#################################################################

function show_usage {
echo "usage: restore-datafile.bash -o <Oracle instance name> -f <datafile name or id> -p <PDB database name> -m <mount>  -b <ORACLE_HOME> -w <yes/no>"
echo " "
echo " Required Parameters"
echo " -o : Oracle instance name. If it is not RAC, it is the same as DB name. If it is RAC, it is the instance name like cohcdba2. It is a CDB not PDB"
echo " -f : Oracle datafile name or id."
echo " "
echo " Optional Parameters"
echo " -p : PDB database name. If this database is a root of a CDB database, enter root "
echo " -m : NFS mount point created by Cohesity view restore (like /opt/cohesity/mount_paths/nfs_oracle_mounts/oratestview/oracle_35135289_8258227_path0)"
echo " -b : ORACLE_HOME (Optional, default is current environment)"
echo " -w : yes means preview rman backup scripts"
}

while getopts ":o:m:b:f:p:w:" opt; do
  case $opt in
    o ) oraclesid=$OPTARG;;
    p ) pdbname=$OPTARG;;
    m ) mount=$OPTARG;;
    b ) oracle_home=$OPTARG;;
    f ) datafile_info=$OPTARG;;
    w ) preview=$OPTARG;;
  esac
done


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
   if [[ ${fullcommand[$i]} == -f ]]; then
      datafileset=yes
   fi
done
if [[ -n $datafileset ]]; then
   if [[ -z $datafile_info ]]; then
      echo "Please enter a datafile name or id as the argument for -f. It may be empty or not all options are given an argument. All options should be given an arguments"
      exit 2
   fi
fi

i=0
for (( i=0; i<$lencommand; i++ ))
do
   if [[ ${fullcommand[$i]} == -p ]]; then
      pdbnameset=yes
   fi
done
if [[ -n $pdbnameset ]]; then
   if [[ -z $pdbname ]]; then
      echo "Please enter a PDB database name as the argument for -p. It may be empty or not all options are given an argument. All options should be given an arguments"
      exit 2
   fi
fi

# Check required parameters
if test $oraclesid && test $datafile_info
then
  :
else
  show_usage 
  exit 1
fi

dbname=$oraclesid

if [[ -z $mount ]]; then
   read -p "The restore of the datafile assumes the current database controlfile or the recovery catalog has the datafile backup information and
the backup files are accessible from this server. If the backup was done using Cohesity Oracle adapter, It 
will use the current Cohesity Adapter NFS mount and the latest archive logs are still on disk on this server.
If the current Cohesity Adapter NFS is not mounted or the latest archive logs aren't on disk, the restore of the datafile will fail.
Please use Cohesity view restore function to NFS mount the backup first before running this datafile restore.

Should the restore continue? " answer
   if [[ $answer != [Yy]* ]]; then
      echo "
Please rerun the restore by providing a mount point which has the latest backup and archivelog. The mount point can be created using Cohesity Oracle view restore option"
      exit 1
   fi
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
host=`hostname -s`

rmanlogin="rman target /"
echo "rman login command is $rmanlogin"

targetc="/"
sqllogin="sqlplus / as sysdba"

if test $oracle_home; then
#  echo *target*
  echo "ORACLE_HOME is $oracle_home"
  ORACLE_HOME=$oracle_home
  if [[ `ls $ORACLE_HOME/bin/rman` ]]; then
    export ORACLE_HOME=$oracle_home
    export PATH=$PATH:$ORACLE_HOME/bin
  else
    echo "ORACLE_HOME \"$ORACLE_HOME\" provided in input is incorrect"
    exit 1
  fi
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


logdir=$DIR/log/$host
runlog=$DIR/log/$host/$dbname.$DATE_SUFFIX.log
stdout=$DIR/log/$host/${dbname}.$DATE_SUFFIX.std
restore_rmanlog=$DIR/log/$host/$dbname.rman-restore.$DATE_SUFFIX.log
restore_rmanfile=$DIR/log/$host/$dbname.rman-restore.$DATE_SUFFIX.rcv
catalog_rmanlog=$DIR/log/$host/$dbname.rman-catalog.$DATE_SUFFIX.log
catalog_rmanfile=$DIR/log/$host/$dbname.rman-catalog.$DATE_SUFFIX.rcv


export ORACLE_SID=$oraclesid
unset ORACLE_PDB_SID

# check whether the database is running
$sqllogin << EOF > /dev/null
   spool $stdout replace
   select name from v\$database;
EOF

if grep -i "ORA-01034" $stdout > /dev/null; then
   echo "Oracle database $dbname is not running. Restore $datafile_info will not start."
   echo " "
   exit 1
fi

#determine whether this database is multi-tenant Database. If it is CDB, make sure pdbname is entered

$sqllogin << EOF > /dev/null
   spool $stdout replace
   select count(*) from v\$pdbs;
EOF

output=""
get_oracle_info $stdout
pdb_count=$output


if [[ $pdb_count -eq 0 ]]; then
   echo "This database is not a multi-tenant database;"
   echo "This database is not a multi-tenant database;" >> $runlog
else
   cdb=yes
   echo "This database is a multi-tenant database;"
   echo "This database is a multi-tenant database;" >> $runlog
   if test $pdbname
   then
     :
   else
      echo "a PDB name needs to be provided. If this database is a root of a CDB database, provide root as the argument for -p plugin"
      exit 1
   fi
fi

}
function pre_restore_datafile { 
   
# check whether the database is in read write mode or not if it is a CDB database
if [[ $cdb == "yes" ]]; then
   $sqllogin << EOF > /dev/null
      spool $stdout replace
      select open_mode from v\$database;
EOF

   output=""
   get_oracle_info $stdout
   open_mode=$output

   echo CDB database $dbname is at $open_mode mode
# If it is in MOUNTED mode, Restore $datafile_info in pdb database $pdbname will not start. 
   if [[ $open_mode == "MOUNTED" ]]; then
      echo "Oracle database $dbname is in MOUNTED mode. Restore $datafile_info in pdb database $pdbname will not start."
      echo " "
      exit 1
   fi

# Check whether this pdb exist if it is not root 
   if [[ $pdbname != "root" && $pdbname != "ROOT" && $pdbname != "Root" ]]; then
      export ORACLE_PDB_SID=$pdbname
   
      $sqllogin << EOF > /dev/null
      spool $stdout replace
      show con_id;
EOF
      output=""
      get_oracle_info $stdout
      conid=$output
   
      echo "con_id is $conid"
      if [[ $conid -eq 1 ]]; then
         echo "The PDB database \"$pdbname\"  provided from the input does not exist in database $dbname. Please find the right PDB name"
         exit 1
      else
	  # check whether this PDB database is open or not
         $sqllogin << EOF > /dev/null
         spool $stdout replace
         select open_mode from v\$database;
EOF
         output="" 
	 get_oracle_info $stdout
	 pdb_open_mode=$output
		 
	 echo "PDB database $pdbname open mode is $pdb_open_mode"
	 if [[ $pdb_open_mode == "MOUNTED" ]]; then
	    echo "Oracle database $pdbname is not in open mode. Restore tablespace $tablespace_info in pdb database $pdbname will not start."
	    exit 1
	 fi
      fi
	  
   else
      echo "The tablespace is in the container of the database"
      conid=1
   fi
fi

echo "determine the datafile_info input is a File ID or File name"
echo "determine the datafile_info input is a File ID or File name" > $runlog
echo "Verify the datafile $datafile_info exist in databaes $dbname"
echo "Verify the datafile $datafile_info exist in databaes $dbname" >> $runlog

if [[ $datafile_info =~ ^[0-9]+$ ]]; then
   echo "The datafile ID is $datafile_info"
   echo "The datafile ID is $datafile_info" >> $runlog
   datafile_id=$datafile_info

   $sqllogin << EOF > /dev/null
   spool $stdout replace
   SET LINES 300
   COL NAME FORMAT a300
   select NAME from v\$datafile where FILE# = '$datafile_id';
EOF

   output=""
   get_oracle_info $stdout
   datafile_name=$output
   
   if [[ -z $datafile_name ]];then
      if [[ -n $pdbname ]]; then
         echo "The datafile $datafile_info from the input doesn't exist in database $dbname PDB database $pdbname. Restore $datafile_info will not start."
	 echo " "
         exit 1
      else
         echo "The datafile $datafile_info from the input doesn't exist in database $dbname. Restore $datafile_info will not start.
If this datafile  $datafile_info is in a PDB database, please enter pdbname as the argument for -p "
         echo " "
         exit 1
      fi
   fi
else
   echo "The datafile name is $datafile_info"
   echo "The datafile name is $datafile_info" >> $runlog
   datafile_name=$datafile_info
   $sqllogin << EOF > /dev/null
   spool $stdout replace
   select FILE# from v\$datafile where NAME = '$datafile_name';
EOF
   output=""
   get_oracle_info $stdout
   datafile_id=$output

   if [[ -z $datafile_id ]];then
      if [[ -n $pdbname ]]; then
         echo "The datafile $datafile_info from the input doesn't exist in database $dbname PDB database $pdbname. Restore $datafile_info will not start."
	 echo " "
         exit 1
      else
         echo "The datafile $datafile_info from the input doesn't exist in database $dbname. Restore $datafile_info will not start.
If this datafile  $datafile_info is in a PDB database, please enter pdbname as the argument for -p "																										
         echo " "
         exit 1
      fi
   fi  
fi

echo "datafile id is $datafile_id and datafile name is $datafile_name"
echo "datafile id is $datafile_id and datafile name is $datafile_name" >> $runlog

#make sure the datafile name is not "SYSTEM", "SYSAUX", "UNDOTBS" type of datafiles
if [[ ${datafile_name^^} =~ "SYSTEM" || ${datafile_name^^} =~ "SYSAUX" || ${datafile_name^^} =~ "UNDOTBS" ]]; then
   echo "
The datafile name can not be SYSTEM, SYSAUX, UNDOTBS type of datafiles
Abort the datafile restore
"
   exit 1
fi

echo "find the current datafile status. If the datafile is online, will try to bring it offline after getting the permission"
echo "find the current datafile status. If the datafile is online, will try to bring it offline after getting the permission" >> $runlog
   
$sqllogin << EOF > /dev/null
   spool $stdout replace
   select STATUS from v\$datafile where FILE#='$datafile_id';
EOF

output=""
get_oracle_info $stdout
online_status=$output   

echo " "
echo datafile $datafile_name status is $online_status
echo " "

if [[ $online_status == "SYSTEM" ]]; then
   echo "The datafile $datafile_name is a SYSTEM datafile. Restoring it requires a database restore"
   echo " " 
   exit 1
fi

if [[ $preview != [Yy]* ]]; then
# If it online, change it offline
   if [[ $online_status == "ONLINE" ]]; then
#   echo "datafile $datafile_name is online"
      read -p "Should this datafile be altered to offline? " answer1
   
      if [[ $answer1 = [Yy]* ]]; then
         echo "The answer is yes, Will alter this datafile offline"
         echo "The answer is yes, Will alter this datafile offline" >> $runlog
		 
         $sqllogin << EOF
         spool $stdout replace
         alter database datafile '$datafile_name' offline;
EOF
         if grep "ERROR" $stdout > /dev/null; then
            echo " "
            echo "Alter datafile $datafile_name command failed. Please bring this datafile offline manually first, then run the script. "
            exit 1
         fi
      else
         echo "The answer is no, Restore $datafile_name will not start."
         echo "The answer is no, Restore $datafile_name will not start." >> $runlog
         echo " "
         exit 0
      fi
   fi
else
   echo " "
   echo "This is preview, will not bring the datafile offline"
   echo " "
fi
}
    
function create_rman_restore_file {

echo "Create rman restore datafile script"

if [[ -n $mount ]]; then
   mountstatus=`mount | grep -i  "${mount}"`
   if [[ -n $mountstatus ]]; then

      echo "
      $mount is mount point
"
      echo "catalog start with '$mount' noprompt;" > $catalog_rmanfile 
   else
      echo "
      $mount is not a mount point, Please provide a valid mount input. Exit the restore
"
      exit 1
   fi
fi

#echo "RUN {" > $restore_rmanfile 
#echo "allocate channel fs0 device type disk;" >> $restore_rmanfile

echo "restore datafile $datafile_id;
recover datafile $datafile_id;
" >> $restore_rmanfile
#release channel fs0;" >> $restore_rmanfile


#echo "
#}" >> $restore_rmanfile

echo "exit;
" >> $restore_rmanfile

echo "finished creating rman restore datafile script"

}

function restore_datafile {

echo "Datafile restore started at " `/bin/date '+%Y%m%d%H%M%S'`
echo "Datafile restore started at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog
echo "ORACLE SID is $oraclesid"

if [[ -n $mount ]]; then
   unset ORACLE_PDB_SID
   rman log $catalog_rmanlog << EOF
   connect target '${targetc}'
   @$catalog_rmanfile
EOF
fi
   
if [[ $cdb == "yes" ]]; then
   if [[ $pdbname != "root" && $pdbname != "ROOT" && $pdbname != "Root" ]]; then
      export ORACLE_PDB_SID=$pdbname
   fi
fi

rman log $restore_rmanlog << EOF
   connect target '${targetc}'
   @$restore_rmanfile
EOF

if [ $? -ne 0 ]; then
   echo "   "
   echo "Datafile $datafile_name restore failed at " `/bin/date '+%Y%m%d%H%M%S'`
   echo "Datafile $datafile_name restore failed at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog
   echo "The last 10 line of rman log output"
   echo " "
   echo "rmanlog file is $restore_rmanlog"
   tail $restore_rmanlog
   exit 1
else
   echo "  "
   echo "Datafile $datafile_name restore finished at " `/bin/date '+%Y%m%d%H%M%S'`
   echo "Datafile $datafile_name restore finished at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog
   echo " "
fi

}

function post_restore_datafile {

echo "The datafile restore is successful, will try to bring $datafile_id online"
echo "The datafile restore is successful, will try to bring $datafile_id online" >> $runlog

#find the new datafile Name
unset ORACLE_PDB_SID
if [[ $cdb == "yes" ]]; then
   if [[ $pdbname != "root" && $pdbname != "ROOT" && $pdbname != "Root" ]]; then
      export ORACLE_PDB_SID=$pdbname  
   fi
fi

$sqllogin << EOF > /dev/null
   spool $stdout replace
   SET LINES 300
   COL NAME FORMAT a300
   select NAME from v\$datafile where FILE# = '$datafile_id';
EOF

output=""
get_oracle_info $stdout
datafile_name_new=$output

$sqllogin << EOF
   spool $stdout replace
   alter database datafile '$datafile_name_new' online;
EOF
if grep "ERROR" $stdout > /dev/null; then
   echo " "
   echo "Alter datafile $datafile_name_new online command in database $dbname failed. Please bring this datafile online manually. "
   echo "Alter datafile $datafile_name_new online command in database $dbname failed. Please bring this datafile online manually. " >> $runlog
   echo " "
else
   echo "Alter datafile $datafile_name_new online command in database $dbname finished. "
   echo "Alter datafile $datafile_name_new online command in database $dbname finished. " >> $runlog
   echo " "
fi

}

setup


if [[ $preview = "yes" || $preview = "Yes" || $preview = "YES" ]]; then
   datafile_id=$datafile_info
   create_rman_restore_file
   echo "   "
   echo ORACLE restore RMAN SCRIPT 
   echo " "
   echo "---------------"
   cat $restore_rmanfile
   echo "---------------"
   echo " "
   exit
fi

pre_restore_datafile
create_rman_restore_file
read -p "Is it ready to restore this datafile? " answer2
if [[ $answer2 = [Yy]* ]]; then
   restore_datafile
   read -p "Should this datafile be altered to online? " answer3
   
   if [[ $answer3 = [Yy]* ]]; then
      echo "The answer is yes, Will alter this datafile online"
      echo "The answer is yes, Will alter this datafile online" >> $runlog
      post_restore_datafile
   fi
else
   echo "datafile $datafile_name is not restored. Need to manually bring it online. 
The RMAN restore script is $restore_rmanfile"
fi
echo "restore time is in rman log " $restore_rmanlog
echo "check the start time and Finished recover time"
