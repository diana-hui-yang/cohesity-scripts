#!/bin/bash
#
# Name:         import-tablespace.bash
#
# Function:     This script import s Oracle tablespaces from another identical database 
#               which has the tablespace. It checks the tablespace first. If it exists in current database,
#               it will drop it first once it is given the permission. It can to used to restore a point-in-time
#				tablespace or a dropped tablespacc when it is combined with Cohesity OracleAdatper clone feature.  
#				First a point in time Cohesity Clone database needs be created first. This script can  
#				be used to export the tablespace from the Cohesity Clone database, then imported to the production database
# Warning:      This script needs to be used in caution.
#               The author accepts no liability for damages resulting from its use.
#
#
# Show Usage: run the command to show the usage
#
# Changes:
# 09/13/23 Diana Yang   New script
#
#################################################################

function show_usage {
echo "usage: import-tablespace.bash -o <Oracle instance name> -t <tablespace name> -p <PDB database name> -d <directory>  -c <clone database> -b <ORACLE_HOME> -w <yes/no>"
echo " "
echo " Required Parameters"
echo " -o : Oracle instance name. If it is not RAC, it is the same as DB name. If it is RAC, it is the instance name like cohcdba2. It is a CDB not PDB"
echo " -t : Oracle tablespace name."
echo " -c : Oracle instance that has the tablespace. If it is not RAC, it is the same as DB name. If it is RAC, it is the instance name like cohcdbb2. It is a CDB not PDB"
echo " -d : A local directory or NFS mount point from Cohesity clone database locaton (like /opt/cohesity/mount_paths/nfs_oracle_mounts/oratestview/oracle_35135289_8258227_path0)"
echo " "
echo " Optional Parameters"
echo " -p : PDB database name. If this database is a root of a CDB database, enter root. Assume the PDB database name is the same on Oracle instance and clone database instance "
echo " -b : ORACLE_HOME (Optional, default is current environment)"
echo " -w : yes means preview rman backup scripts"
}

while getopts ":o:t:c:d:b:p:w:" opt; do
  case $opt in
    o ) oraclesid=$OPTARG;;
    p ) pdbname=$OPTARG;;
    d ) mount=$OPTARG;;
    c ) clonesid=$OPTARG;;
    b ) oracle_home=$OPTARG;;
    t ) tablespace_name=$OPTARG;;
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
   if [[ ${fullcommand[$i]} == -t ]]; then
      tablespaceset=yes
   fi
done
if [[ -n $tablespaceset ]]; then
   if [[ -z $tablespace_name ]]; then
      echo "Please enter a tablespace name as the argument for -t. It may be empty or not all options are given an argument. All options should be given an arguments"
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
if test $oraclesid && test $tablespace_name && test $mount && test $clonesid
then
  :
else
  show_usage 
  exit 1
fi

mkdir -p $mount/expimp_${tablespace_name}
if [ $? -ne 0 ]; then
   echo "create import directory expimp_${tablespace_name} failed. There is a permission issue"
   exit 1
fi

expimp_dir=$mount/expimp_${tablespace_name}

sdbname=$oraclesid  
exportlogin="expdp \"'/ as sysdba'\""
importlogin="impdp \"'/ as sysdba'\""

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
runlog=$DIR/log/$host/$sdbname.$DATE_SUFFIX.log
stdout=$DIR/log/$host/${sdbname}.$DATE_SUFFIX.std
dbadirfile=$DIR/log/$host/$sdbname.dba_directories.$DATE_SUFFIX.sql
dbadirlog=$DIR/log/$host/$sdbname.dba_directories.$DATE_SUFFIX.log
expdpfile=$DIR/log/$host/$sdbname.expdp.$DATE_SUFFIX.sh
impdpfile=$DIR/log/$host/$sdbname.impdp.$DATE_SUFFIX.sh

# check whether the database #oraclesid is running
export ORACLE_SID=$oraclesid
unset ORACLE_PDB_SID

$sqllogin << EOF > /dev/null
   spool $stdout replace
   select name from v\$database;
EOF

if grep -i "ORA-01034" $stdout > /dev/null; then
   echo "Oracle database $sdbname is not running. Restore tablespace $tablespace_name will not start."
   echo " "
   exit 1
fi

# check whether the database $clonesid is running
export ORACLE_SID=$clonesid
unset ORACLE_PDB_SID

$sqllogin << EOF > /dev/null
   spool $stdout replace
   select name from v\$database;
EOF

if grep -i "ORA-01034" $stdout > /dev/null; then
   echo "Oracle database $clonesid is not running. Restore tablespace $tablespace_name will not start."
   echo " "
   exit 1
fi

}

function pre_expimp_tablespace {

#determine whether this database is multi-tenant Database. If it is CDB, make sure pdbname is entered
export ORACLE_SID=$oraclesid
unset ORACLE_PDB_SID

$sqllogin << EOF > /dev/null
   spool $stdout replace
   select count(*) from v\$pdbs;
EOF

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

# check whether the database is in read write mode or not if it is a CDB database

if [[ $cdb == "yes" ]]; then
   $sqllogin << EOF > /dev/null
      spool $stdout replace
      select open_mode from v\$database;
EOF
   get_oracle_info $stdout
   open_mode=$output

   echo CDB database $sdbname is at $open_mode mode
# If it is not in "READ WRITE" mode, Restore $tablespace_name in pdb database $pdbname will not start. 
   if [[ $open_mode != "READ WRITE" ]]; then
      echo "Oracle database $sdbname is not in open mode. Restore tablespace $tablespace_name in pdb database $pdbname will not start."
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
      get_oracle_info $stdout
      conid=$output
   
      echo "con_id is $conid"
      if [[ $conid -eq 1 ]]; then
         echo "The PDB database \"$pdbname\"  provided from the input does not exist in database $sdbname. Please find the right PDB name"
         exit 1
      else
	  # check whether this PDB database is open or not
         $sqllogin << EOF > /dev/null
         spool $stdout replace
         select open_mode from v\$database;
EOF
	 get_oracle_info $stdout
	 pdb_open_mode=$output
		 
	 echo "PDB database $pdbname open mode is $pdb_open_mode"
	 if [[ $pdb_open_mode != "READ WRITE" ]]; then
	    echo "Oracle database $pdbname is not in open mode. Restore tablespace $tablespace_name in pdb database $pdbname will not start."
	    exit 1
	 fi

         # check whether there is a tempfile in this PDB database
         $sqllogin << EOF > /dev/null
         spool $stdout replace
         select count(*) from dba_temp_files;
EOF
	 get_oracle_info $stdout
	 tempcount=$output
		 
	 echo "The number of tempfile in this database $oraclesid PDB database $pdbname is $tempcount"
	 if [[ $tempcount -eq 0 ]]; then
	    echo " "
	    echo "This PDB database $pdbname has no tempfile of its own. The import will fail"
	    echo "Need to create the tempfile in this PDB database. After it is done, run this script again"
	    exit 1
	 fi	    
      fi
	  
   else
      echo "The tablespace is in the container of the database"
      conid=1
   fi
fi


#make sure the tablespace name is not "SYSTEM", "TEMP", "SYSAUX", "UNDOTBS" or tablespace id is not 0, 1, 2, 3
if [[ ${tablespace_name^^} =~ "SYSTEM" || ${tablespace_name^^} =~ "SYSAUX" || ${tablespace_name^^} =~ "TEMP" || ${tablespace_name^^} =~ "UNDO" ]]; then
   echo "
The tablespace name can not be SYSTEM, TEMP, SYSAUX, UNDOTBS
Abort the tablespace restore
"
   exit 1
fi

echo "Will determine whether this tablespace ${tablespace_name} exist in the clone database."
echo "Will determine whether this tablespace ${tablespace_name} exist in the database." >> $runlog

export ORACLE_SID=$clonesid
if [[ $cdb = "yes" ]]; then
   export ORACLE_PDB_SID=$pdbname
fi

$sqllogin << EOF > /dev/null
    spool $stdout replace
    select STATUS from DBA_TABLESPACES where TABLESPACE_NAME='${tablespace_name^^}';
EOF

get_oracle_info $stdout
online_status=$output    

echo " "
echo tablespace $tablespace_name status is $online_status
echo " "

if [[ -n $online_status ]]; then
#   echo "tablespace $tablespace_name currently exists in this database"
#   change the tablespace readonly
   if [[ $online_status != "READ ONLY" ]]; then
      $sqllogin << EOF > /dev/null
         spool $stdout replace
         ALTER TABLESPACE ${tablespace_name^^} READ ONLY;
EOF
      if grep "ERROR" $stdout > /dev/null; then
         echo "Alter tablespace $tablespace_name to readonly failed. Please alter this tablespace manually first, then run the script. "
         exit 1
      fi
   fi
else
   echo "The tablespace $tablespace_name doesn't exist in database $clonesid, import tablespace $tablespace_name will not start."
   echo "The tablespace $tablespace_name doesn't exist in database $clonesid, import tablespace $tablespace_name will not start." >> $runlog
   echo " "
   exit 1
fi

#If the database is multi-tenant database, need determine whether there is a tempfile for this clone PDB database
#Create one if there is no tempfile for this clone PDB database

if [[ $cdb = "yes" ]]; then
   $sqllogin << EOF > /dev/null
      spool $stdout replace
      select count(*) from dba_temp_files;
EOF

   get_oracle_info $stdout
   tempcount=$output
		 
   echo "The number of tempfile in clone database $clonesid PDB database $pdbname is $tempcount"
   if [[ $tempcount -eq 0 ]]; then
      echo " "
      echo "This PDB database $pdbname has no tempfile of its own. Will create the tempfile"
	  
      $sqllogin << EOF > /dev/null
         spool $stdout replace
         col PROPERTY_VALUE for a20
         select property_value from database_properties where property_name='DEFAULT_TEMP_TABLESPACE';
EOF
      get_oracle_info $stdout
      property_value=$output
      tempfile_name=${property_value}_coh
	  
      echo "Will create tempfile ${tempfile_name}"
      $sqllogin << EOF > /dev/null
     	spool $stdout replace
	CREATE TEMPORARY TABLESPACE ${tempfile_name};
	ALTER DATABASE DEFAULT TEMPORARY TABLESPACE ${tempfile_name};
EOF
      if grep "ERROR" $stdout > /dev/null; then
	 echo "Creating tempfile ${tempfile_name} in clone database $clonesid PDB database $pdbname failed. Please create this manually first, then run this script again"
	 echo "Creating tempfile ${tempfile_name} in clone database $clonesid PDB database $pdbname failed. Please create this manually first, then run this script again" >> $runlog
	 echo " "
	 exit 1
      else
	 echo "Creating tempfile ${tempfile_name} in clone database $clonesid PDB database $pdbname is successful"
	 echo "Creating tempfile ${tempfile_name} in clone database $clonesid PDB database $pdbname is successful" >> $runlog
         echo " "
      fi
   fi
fi
	 


echo "Will determine whether this tablespace exist in the database. If it is, will try to drop if after getting the permission"
echo "Will determine whether this tablespace exist in the database. If it is, will try to drop if after getting the permission" >> $runlog

export ORACLE_SID=$oraclesid

# need to drpp the tablespace
$sqllogin << EOF > /dev/null
   spool $stdout replace
   select STATUS from DBA_TABLESPACES where TABLESPACE_NAME='${tablespace_name^^}';
EOF

get_oracle_info $stdout
online_status=$output    

echo " "
echo tablespace $tablespace_name status is $online_status
echo " "

# If it exists, drop the tablespace
if [[ -n $online_status ]]; then
#   echo "tablespace $tablespace_name currently exists in this database"
   read -p "Should this tablespace be dropped?, answer yes if you agree: " answer1
   
   echo $answer1
   if [[ $answer1 = [Yy]* ]]; then
      echo "The answer is yes, Will drop this tablespace "
      echo "The answer is yes, Will drop this tablespace " >> $runlog

      $sqllogin << EOF > /dev/null
         spool $stdout replace
         DROP TABLESPACE ${tablespace_name^^} INCLUDING CONTENTS;
EOF
      if grep "ERROR" $stdout > /dev/null; then
         echo "Drop tablespace $tablespace_name command failed. Please drop this tablespace manually first, then run the script. "
         exit 1
      fi 
   else
      read -p "Is this tablespace $tablespace_name empty tablespace? If it is, no need to drop it. answer yes if it is empty: " answer3
		 
      if [[ $answer3 = [Yy]* ]]; then
         echo "An empty tablespace $tablespace_name has been created, Process continue"
      else
         echo "The answer is no, The tablespace $tablespace_name exsits and is not empty. Restore tablespace $tablespace_name will not start."
         echo "The answer is no, The tablespace $tablespace_name exsits and is not empty. Restore tablespace $tablespace_name will not start." >> $runlog
         echo " "
         exit 0
      fi
   fi
fi
   
if [[ -z $answer3 ]]; then
   echo "An empty tablespace $tablespace_name needs to be created in this database"
   echo "Please create it before continue"
		 
   read -p "Has it been created. answer yes if it is, no to exit: " answer2
   if [[ $answer2 = [Yy]* ]]; then
      echo " "
      echo "An empty tablespace $tablespace_name has been created, Process continue"
   else
      echo "The answer is no. An empty tablespace $tablespace_name needs to be created. Once it is created, rerun the script. "
      exit 0
   fi
fi

}
    
function create_export_import_tablespace {

# create directory path in oracle

echo "create or replace directory COH_DIR as '${expimp_dir}';" >> $dbadirfile
echo "exit;" >> $dbadirfile

# create export and import script
echo "#Export tablespace ${tablespace_name}" >> $expdpfile
echo "#Import tablespace ${tablespace_name}" >> $impdpfile

echo "$exportlogin TABLESPACES=${tablespace_name^^} TRANSPORT_FULL_CHECK=YES DIRECTORY=COH_DIR DUMPFILE=${tablespace_name}.dmp" >> $expdpfile
chmod 750 $expdpfile

echo "$importlogin DIRECTORY=COH_DIR DUMPFILE=${tablespace_name}.dmp">> $impdpfile
chmod 750 $impdpfile

echo "finished creating export and import script"

}

function export_tablespace {

#export the tablespace

echo "Create or replace directory in clone database"  >> $runlog
echo "Create or replace directory in clone database"

export ORACLE_SID=$clonesid
if [[ $cdb = "yes" ]]; then
  export ORACLE_PDB_SID=$pdbname
fi

${sqllogin} @${dbadirfile}

if [ $? -eq 0 ]; then
  echo "dba_directories in Oracle clone database $clonesid was created successfully" >> $runlog
  echo "dba_directories in Oracle clone database $clonesid was created successfully"
else
  echo "dba_directories in Oracle clone database $clonesid failed to be created" >> $runlog
  echo "dba_directories in Oracle clone database $clonesid failed to be created"
  exit 1
fi

# query and save the directory
${sqllogin} << EOF
  spool ${dbadirlog}
  SET LINES 300
  col DIRECTORY_NAME format a20
  col DIRECTORY_PATH format a100
  select DIRECTORY_NAME, DIRECTORY_PATH from dba_directories
  where lower(DIRECTORY_NAME)like '%coh%';
  spool off
  exit
EOF

# export tablespace
echo "Database export from $clonesid $pdbname started at " `/bin/date '+%Y%m%d%H%M%S'`
echo "Database export from $clonesid $pdbname started at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog

$expdpfile

if [ $? -ne 0 ]; then
  echo "Database export from $clonesid $pdbname failed at " `/bin/date '+%Y%m%d%H%M%S'`
  echo "Database export from $clonesid $pdbname failed at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog
  while IFS= read -r line
  do
    echo $line
  done < $expdpfile
  exit 1
else
  echo "Database export from $clonesid $pdbname finished at " `/bin/date '+%Y%m%d%H%M%S'`
  echo "Database export from $clonesid $pdbname finished at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog
fi

}

function import_tablespace {

#import the tablespace

echo "Create or replace directory in target database"  >> $runlog
echo "Create or replace directory in target database"

export ORACLE_SID=$oraclesid
if [[ $cdb = "yes" ]]; then
   export ORACLE_PDB_SID=$pdbname
fi

${sqllogin} @${dbadirfile}

if [ $? -eq 0 ]; then
  echo "dba_directories in Oracle target database $oraclesid was created successfully" >> $runlog
  echo "dba_directories in Oracle target database $oraclesid was created successfully"
else
  echo "dba_directories in Oracle target database $oraclesid failed to be created" >> $runlog
  echo "dba_directories in Oracle target database $oraclesid failed to be created"
  exit 1
fi

# import tablespace
echo "Database import to $oraclesid $pdbname started at " `/bin/date '+%Y%m%d%H%M%S'`
echo "Database import to $oraclesid $pdbname started at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog

$impdpfile

if [ $? -ne 0 ]; then
  echo "Database import to $oraclesid $pdbname failed at " `/bin/date '+%Y%m%d%H%M%S'`
  echo "Database import to $oraclesid $pdbname failed at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog
  while IFS= read -r line
  do
    echo $line
  done < $impdpfile
  exit 1
else
  echo "Database import to $oraclesid $pdbname finished at " `/bin/date '+%Y%m%d%H%M%S'`
  echo "Database import to $oraclesid $pdbname finished at " `/bin/date '+%Y%m%d%H%M%S'` >> $runlog
fi 

}

setup
create_export_import_tablespace
if [[ $preview = "yes" || $preview = "Yes" || $preview = "YES" ]]; then
  echo "   "
  echo ORACLE DBA directory SQL SCRIPT
  echo "---------------"
  echo " "
  cat $dbadirfile
  echo "   "
  echo ORACLE EXPORT SCRIPT
  echo "---------------"
  echo " "
  cat $expdpfile
  echo "---------------"
  echo ORACLE IMPORT SCRIPT
  echo "---------------"
  echo " "
  cat $impdpfile
  echo "---------------"
else
   pre_expimp_tablespace 
   export_tablespace
   import_tablespace
   read -p "Should the export directory be cleaned, answer yes if it should:   " answer4
   
   if [[ $answer4 = [Yy]* ]]; then
      rm $expimp_dir/${tablespace_name}.dmp
   fi
fi
