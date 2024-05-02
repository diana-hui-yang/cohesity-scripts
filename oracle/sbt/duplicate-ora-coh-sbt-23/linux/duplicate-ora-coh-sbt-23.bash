#!/bin/bash
#
# Name:         duplicate-ora-coh-sbt-23.bash
#
# Function:     This script duplicates an Oracle database from an Oracle backup 
#               using backup-ora-coh-sbt-23.bash. This script requires recovery database or 
#				source database to be available while running the duplication
#
#
# Show Usage: run the command to show the usage
#
# Changes:
# 08/07/20 Diana Yang   New script (duplicate using target database)
# 08/21/20 Diana Yang   Add more conditions
# 10/30/20 Diana Yang   Standardlize name. Remove "-f" and "-s" as required parameter
# 11/11/20 Diana Yang   Remove the need to manually create vip-list file
# 01/18/21 Diana Yang   Add option to cancel the job
# 04/29/21 Diana Yang   Change syntax to use new sbt library
# 05/03/21 Diana Yang   Add refresh option
# 09/13/21 Diana Yang   Add encryption-in-flight
# 09/13/21 Diana Yang   Add an option to use SunRPC
# 04/07/22 Diana Yang   Change the input plugin to be consistent with restore script
# 04/27/22 Diana Yang   Add noresume option 
# 01/15/23 Diana Yang   Add new option to allow new PDB name during duplication
# 01/15/23 Diana Yang   Remove the requirement for -h and -d
#
#################################################################

function show_usage {
echo "usage: duplicate-ora-coh-sbt-23.bash -r <Source ORACLE connection> -h <backup host> -c <Catalog ORACLE connection> -i <Target Oracle_DB_Name> -y <Cohesity-cluster> -b <file contain restore settting> -t <point-in-time> -e <sequence> -j <vip file> -v <view> -q <catalog view> -s <sbt file name> -p <number of channels> -o <ORACLE_HOME> -u <source PDB> -n <new PDB name> -l <yes/no> -a <Auxiliary database> -f <yes/no> -m <noresume> -w <yes/no> -g <yes/no> -k <cert path> -x <yes/no>" 
echo " "
echo " Required Parameters"
echo " -i : Target Oracle instance name (Oracle duplicate database)" 
echo " -r : Source Oracle connection (example: \"sys/<password>@<target db connection>\" or \"<dbuser>/<dbpass>@<target connection string> as sysbackup\")"
echo " -h : Source host - Oracle database host that the backup was run." 
echo " -y : Cohesity Cluster DNS name"
echo " -v : Cohesity View that is configured to be the target for Oracle backup"
echo " -q : Cohesity View that is configured to be the Cohesity catalog for Oracle backup"
echo " "
echo " Optional Parameters"
echo " -e : Log sequence number of thread 1. Either point-in-time or log sequence number. Can't be both."
echo " -c : RMAN Catalog connection (example: \"<dbuser>/<dbpass>@<catalog connection string>\", optional)"
echo " -t : Point in Time (format example: \"2019-01-27 13:00:00\")"
echo " -b : File contains restore location setting, example: set newname for database to '/oradata/restore/orcl/%b'; "
echo " -p : number of channels (default is 4), optional"
echo " -j : The file lists Cohesity Cluster VIPs (default name is vip-list and default directory is config)"
echo " -s : Cohesity SBT library name including directoy or just directory (default name is libsbt_6_and_7_linux-x86_64.so, default directory is lib) "
echo " -o : ORACLE_HOME (default is current environment), optional"
echo " -u : Source pluggable database (if this input is empty, it is standardalone or CDB database restore)"
echo " -n : Destination pluggable database"
echo " -l : yes means plugging the pdb database with copy option. The default is nocopy which means the database file structure will not be moved from auxiliary database to target database"
echo " -a : Temporary Auxiliary CDB database for the purpose of restoring a pluggable database to target database by preservaing the existing data in target database"
echo " -f : yes means force. It will refresh the target database without prompt"
echo " -m : yes mean Oracle duplicate use noresume, default is no"
echo " -g : yes means encryption-in-flight is used. The default is no"
echo " -k : encryption certificate file directory, default directory is lib"
echo " -x : yes means gRPC is used. no means SunRPC is used. The default is yes"
echo " -w : yes means preview rman duplicate scripts"
}

while getopts ":r:c:h:d:i:y:b:t:e:j:v:q:s:p:o:u:n:l:a:f:m:g:k:x:w:" opt; do
  case $opt in
    r ) targetc=$OPTARG;;
    c ) catalogc=$OPTARG;;
    h ) shost=$OPTARG;;
    d ) sdbname=$OPTARG;;
    i ) toraclesid=$OPTARG;;
    b ) ora_pfile=$OPTARG;;
    t ) itime=$OPTARG;;
    e ) sequence=$OPTARG;;
    y ) cohesityname=$OPTARG;;
    j ) vipfile=$OPTARG;;
    v ) view=$OPTARG;;
    q ) cata_view=$OPTARG;;
    s ) sbtname=$OPTARG;;
    p ) parallel=$OPTARG;;
    o ) oracle_home=$OPTARG;;
    u ) pdbname=$OPTARG;;
    n ) npdbname=$OPTARG;;
    l ) pdbcopy=$OPTARG;;
    a ) adbname=$OPTARG;;
    f ) force=$OPTARG;;
    m ) noresume=$OPTARG;;
    g ) encryption=$OPTARG;;
    k ) encrydir=$OPTARG;;
    x ) grpctype=$OPTARG;;
    w ) preview=$OPTARG;;
  esac
done

#echo $shost, $sdbname, $toraclesid, $view, $preview, $cohesityname, $itime 
#echo "  "

# Check required parameters
# check whether "\" is in front of "
fullcommand=($@)
lencommand=${#fullcommand[@]}
#echo $lencommand
i=0
for (( i=0; i<$lencommand; i++ ))
do
   if [[ ${fullcommand[$i]} == *\"* ]]; then
      echo "Error:  \ shouldn't be part of input. Please remove \."
      exit 2 
   fi
done

#if test $toraclesid 
if test $toraclesid && test $view
then
  :
else
  show_usage 
  exit 1
fi

# check some input syntax
i=0
for (( i=0; i<$lencommand; i++ ))
do
   if [[ ${fullcommand[$i]} == -f ]]; then
      forceset=yes
   fi
done
if [[ -n $forceset ]]; then
   if [[ -z $force ]]; then
      echo "Error: Please enter 'yes' as the argument for -f. It may be empty or not all options are given an argument. All options should be given an arguments"
      exit 2
   else
      if [[ $force != [Yy]* ]]; then
         echo "Error: 'yes' should be provided after -f in syntax, other answer is not valid"
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
      echo "Error: Please enter 'yes' as the argument for -w. It may be empty or not all options are given an argument. All options should be given an arguments"
      exit 2
   else
      if [[ $preview != [Yy]* ]]; then
         echo "Error: 'yes' should be provided after -w in syntax, other answer is not valid"
	 exit 2
      fi 
   fi
fi

i=0
for (( i=0; i<$lencommand; i++ ))
do
   if [[ ${fullcommand[$i]} == -l ]]; then
      pdbcopyset=yes
   fi
done
if [[ -n $pdbcopyset ]]; then
   echo pdbcopy is $pdbcopy
   if [[ -z $pdbcopy ]]; then
      echo "Error: Please enter 'yes' or 'no' as the argument for -l. It may be empty or not all options are given an argument. All options should be given an arguments"
      exit 2
   else
      if [[ $pdbcopy != [Yy]* && $pdbcopy != [Nn]* ]]; then
         echo "Error: 'yes' or 'no' should be provided after -l in syntax, other answer is not valid"
	 exit 2
      fi 
   fi
fi

if test $view && test $cata_view
then
  if [[ $view != [A-Za-z]* ]]; then
     echo "The argument for -v is view. It should be the view name, not a digit"
     exit 1
  fi
  if [[ $cata_view != [A-Za-z]* ]]; then
     echo "The argument for -q is catalog view. It should be the view name, not a digit"
     exit 1
  fi 
else
  show_usage 
  exit 1
fi

if [[ -n $npdbname && -z $adbname ]]; then
   echo "Error: An auxiliary database need to be used to restore a PDB in a new CDB with a new PDB name"
   exit 1
fi

function setup {

if test $thost
then
  :
else
  thost=`hostname -s`
fi

if test $parallel
then
  :
else
  echo "no input for parallel, set parallel to be 4"
  parallel=4
fi

for (( i=0; i<$lencommand; i++ ))
do
   if [[ ${fullcommand[$i]} == -x ]]; then
      grpctypeset=yes
   fi
done
if [[ -n $grpctypeset ]]; then
   if [[ -z $grpctype ]]; then
      echo "Error: Please enter 'yes' or 'no' as the argument for -x. It may be empty or not all options are given an argument. All options should be given an arguments"
      exit 2
   else
      if [[ $grpctype != [Yy]* && $grpctype != [Nn]* ]]; then
         echo "Error: 'yes' or 'no' needs to be provided after -x in syntax, other answer is not valid"
	 exit 2
      fi
   fi
else
   if [[ -z $grpctype ]]; then
      grpctype=yes
   fi   
fi

for (( i=0; i<$lencommand; i++ ))
do
   if [[ ${fullcommand[$i]} == -g ]]; then
      encryptionset=yes
   fi
done
if [[ -n $encryptionset ]]; then
   if [[ -z $encryption ]]; then
      echo "Error: Please enter 'yes' or 'no' as the argument for -g. It may be empty or not all options are given an argument. All options should be given an arguments"
      exit 2
   else
      if [[ $encryption != [Yy]* && $encryption != [Nn]* ]]; then
         echo "Error: 'yes' or 'no' needs to be provided after -x in syntax, other answer is not valid"
	 exit 2
      fi
   fi 
fi

for (( i=0; i<$lencommand; i++ ))
do
   if [[ ${fullcommand[$i]} == -k ]]; then
      encrydirset=yes
   fi
done
if [[ -n $encrydirset ]]; then
   if [[ -z $encrydir ]]; then
      echo "Error: Please enter the encryption key absoluate path as the argument for -k. It may be empty or not all options are given an argument. All options should be given an arguments"
      exit 2
   else
      if [[ $encrydir != / ]]; then
         echo "Error: Encryption key absoluate path should be provided"
	 exit 2
      fi
   fi
fi

for (( i=0; i<$lencommand; i++ ))
do
   if [[ ${fullcommand[$i]} == -t ]]; then
      itimeset=yes
   fi
done
if [[ -n $itimeset ]]; then
   if [[ -z $itime ]]; then
      echo "Error: Please enter a time as the argument for -t. It may be empty or not all options are given an argument. All options should be given an arguments"
      exit 2
   else
      if [[ $itime == *\"* ]]; then
         echo "Error: There should not be \ after -t in syntax. It should be -t \"date time\", example like \"2019-01-27 13:00:00\" "
	 exit 2
      fi
   fi 
fi

for (( i=0; i<$lencommand; i++ ))
do
   if [[ ${fullcommand[$i]} == -e ]]; then
      sequenceset=yes
   fi
done
if [[ -n $sequenceset ]]; then
   if [[ -z $sequence ]]; then
      echo "Error: Please enter a sequence number as the argument for -e. It may be empty or not all options are given an argument. All options should be given an arguments"
      exit 2
   else
      if [[ $sequence =~ ^[0-9]+$ ]]; then
         echo "sequence is $sequence "
      else
         echo "Error: The the argument for -e should be a digit"
	 exit 2
      fi
   fi 
fi

if [[ -n $itime && -n $sequence ]]; then
   echo "Error: Either time or sequence be entered. This script does not take both argements"
   exit 2
fi

for (( i=0; i<$lencommand; i++ ))
do
   if [[ ${fullcommand[$i]} == -m ]]; then
      noresumeset=yes
   fi
done
if [[ -n $noresumeset ]]; then
   if [[ -z $noresume ]]; then
      echo "Error: Please enter yes or no as the argument for -m. It may be empty or not all options are given an argument. All options should be given an arguments"
      exit 2
   else
      if [[ $noresume != [Yy]* && $noresume != [Nn]* ]]; then
         echo "Error: 'yes' or 'no' should be provided after -m in syntax, other answer is not valid"
	 exit 2
      fi
   fi 
fi

if [[ -z $targetc && -z $catalogc ]]; then
   echo "Error: Need to provide target database connection string or recover catalog connection string"
   exit 1
fi

#if [[ -n $shost ]]; then
#   echo "-h option is no longer required. Source host is obtained from the argument for -r"
#fi

if [[ -n $sdbname ]]; then
   echo "-d option is no longer required. Source database is obtained from the argument for -r"
fi

if test $oracle_home; then
#  echo *auxiliary*
  echo "ORACLE_HOME is $oracle_home"
  ORACLE_HOME=$oracle_home
  export ORACLE_HOME=$oracle_home
  export PATH=$PATH:$ORACLE_HOME/bin
else
  oracle_home=`env | grep ORACLE_HOME | awk -F "=" '{print $2}'`
  if [[ -z $oracle_home ]]; then
     echo "Error: ORACLE_HOME is not defined. Need to specify ORACLE_HOME"
     exit 1
  fi   
fi

# test source database connection
if [[ -n $targetc ]]; then
   rmanr=`rman << EOF
   connect target '${targetc}'
   exit;
EOF`

   echo $rmanr | grep -i connected
   
   if [ $? -ne 0 ]; then
      echo "rman connection using $targetc is incorrect
           "
      echo $rmanr
      echo "Error: 
           Source Oracle connection syntax should be 
          \"sys/<password>@<target database connect string>\" or
	  \"<dbuser>/<dbpass>@<target connection string> as sysbackup\""
      exit 1
   else
      echo "rman target connection is sucessful. Continue"
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
      echo "Error: 
           catalogc syntax can be like \"/\" or
          \"<catalog dd user>/<password>@<catalog database connect string>\""
      exit 1
   else
      echo "rman catalog connect is successful. Continue"
   fi
fi

if [[ -n $targetc ]]; then
   echo "Will use target conection to duplicate the database"
   catalogc=""
#getting sqlplus login
   cred=`echo $targetc | awk -F @ '{print $1}'`
   conn=`echo $targetc | awk -F @ '{print $2}' | awk '{print $1}'`
   systype=`echo $targetc | awk -F @ '{print $2}' | awk 'NF>1{print $NF}'`
   if [[ -z $shost ]]; then
      if [[ $conn =~ '/' ]]; then
         shost=`echo $conn | awk -F '/' '{print $1}'`
         if [[ $shost =~ ':' ]]; then
            shost=`echo $shost | awk -F ':' '{print $1}'`
         fi
      else
         shost=`tnsping $conn | grep HOST | cut -d\  -f 14 | sed 's/).*//g'`
      fi
   else
      hostdefinded=yes
   fi
   if [[ $shost =~ '.' ]]; then
       shostshort=`echo $shost | awk -F '.' '{print $1}'`
   else
       shostshort=$shost
   fi
   if [[ -z $systype ]]; then
      systype=sysdba
   fi
   ssqllogin="sqlplus ${cred}@${conn} as $systype"
fi

echo "The backup was taken from host $shost"

sqllogin="sqlplus / as sysdba"

export NLS_DATE_FORMAT='DD:MM:YYYY-HH24:MI:SS'

if [[ -n $ora_pfile ]]; then
   if [[ ! -f $ora_pfile ]]; then
      echo "Error: there is no $ora_pfile. It is file defined by -l plugin"
      exit 1
   fi
fi

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

if [[ ! -d $DIR/log/$thost ]]; then
  echo " $DIR/log/$thost does not exist, create it"
  mkdir -p $DIR/log/$thost
  
  if [ $? -ne 0 ]; then
    echo "Error: create log directory $DIR/log/$thost failed. There is a permission issue"
    exit 1
  fi
fi

if [[ ! -d $DIR/config ]]; then
  echo " $DIR/config does not exist, create it"
  mkdir -p $DIR/config
  
  if [ $? -ne 0 ]; then
    echo "Error: create log directory $DIR/config failed. There is a permission issue"
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
         echo "Error: Encryption Certification is not found in directory ${encrydir}. Exit"
         exit 1
      fi
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
     echo "Error: file $vipfile provided does not exist"
     exit 1
  fi
else
  vipfiletemp=${DIR}/config/${toraclesid}-vip-list-temp
  vipfile=${DIR}/config/${toraclesid}-vip-list
  echo "Cohesity Cluster name is $cohesityname. VIPS will be collected and stored in $vipfile"
  nslookup $cohesityname | grep -i address | tail -n +2 | awk '{print $2}' > $vipfiletemp
  
  if [[ ! -s $vipfiletemp ]]; then
     echo "Error: Cohesity Cluster name $cohesityname provided here is not in DNS"
     exit 1
  fi

  shuf $vipfiletemp > $vipfile
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
   echo "Error: file $sbtname does not exist. exit"
   exit 1
fi

if [[ ! -f $DIR/tools/sbt_list ]]; then
   echo "Error: $DIR/tools/sbt_list file does not exist. Please copy sbt_list tool to $DIR/tools directory"
   exit 1
fi

stdout=$DIR/log/$thost/$toraclesid.dup.$DATE_SUFFIX.std
pdbplug=$DIR/log/$thost/$toraclesid.$pdbname.$DATE_SUFFIX.xml
drmanlog=$DIR/log/$thost/$toraclesid.rman-duplicate.$DATE_SUFFIX.log
drmanfiled=$DIR/log/$thost/$toraclesid.rman-duplicate.$DATE_SUFFIX.rcv
destroylog=$DIR/log/$thost/$adbname.destroy.$DATE_SUFFIX.log
plug_bash=$DIR/log/$thost/$adbname.plug.$DATE_SUFFIX.bash
pluglog=$DIR/log/$thost/$toraclesid.plug.$DATE_SUFFIX.log
plug_aux_log=$DIR/log/$thost/$toraclesid.aux.plug.$DATE_SUFFIX.log
unplug_bash=$DIR/log/$thost/$adbname.unplug.$DATE_SUFFIX.bash
unpluglog=$DIR/log/$thost/$adbname.unplug.$DATE_SUFFIX.log
destroy_aux_bash=$DIR/log/$thost/$adbname.delete_aux.$DATE_SUFFIX.bash
destroy_aux_log=$DIR/log/$thost/$adbname.delete_aux.$DATE_SUFFIX.log

#trim log directory
#find $DIR/log/$thost -type f -mtime +7 -exec /bin/rm {} \;

#if [ $? -ne 0 ]; then
#  echo "del old logs in $DIR/log/$thost failed"
#  exit 2
#fi

# Get source sdbname
$ssqllogin << EOF > /dev/null
   spool $stdout replace
   select name from v\$database;
EOF

if [ $? -ne 0 ]; then
   echo "Some part of this connection string \"$ssqllogin\" is incorrect"
   exit 1
fi

i=0
while IFS= read -r line
do
  if [[ $i -eq 1 ]]; then
     sdbname=`echo $line | xargs`
     i=$[$i+1]
  fi
  if [[ $line =~ "-" ]];then
     i=$[$i+1]
  fi
done < $stdout

echo "source database is $sdbname"

$ssqllogin << EOF > /dev/null
   spool $stdout replace
   select name, value from v\$parameter where name='cluster_database';
EOF
if grep -i "true" $stdout; then
   echo "Oracle database $sdbname is a RAC database"
   if [[ -z $hostdefinded ]]; then
      echo "scanname should be provided after -h option for RAC database"
      echo "  "
      exit 1
   fi
   
   $ssqllogin << EOF > /dev/null
   spool $stdout replace
   select INST_NAME FROM V\$ACTIVE_INSTANCES;
EOF
   
   i=0
   while IFS= read -r line
   do
     if [[ $i -ge 1 ]]; then
        snode=`echo $line | xargs | awk -F ":" '{print $1}'`
	if [[ $snode =~ '.' ]]; then
           snodeshort=`echo $snode | awk -F '.' '{print $1}'`
        else
	   snodeshort=$snode
	   if [[ $thost = $snodeshort ]]; then
              echo "The target host is the host where the backup database is running on" 
	      samehost=yes
	   fi
        fi
        i=$[$i+1]
     fi
     if [[ $line =~ "-" ]];then
        i=$[$i+1]
     fi
   done < $stdout
else
   if [[ $thost = $shostshort ]]; then
      echo "The target host is the host where the backup database is running on"
      samehost=yes
   fi
fi

# get cohesity cluster VIP
i=1
while IFS= read -r ip; do
    
   ip=`echo $ip | xargs`    	
   if [[ -n $ip ]]; then
      break   
   else
      i=$[$i+1]
   fi 
done < $vipfile


if [[ -n $adbname ]]; then
#check the target database is up running when auxiliary database is provided
   export ORACLE_SID=${toraclesid}
   sqlplus / as sysdba << EOF > /dev/null
      spool $stdout replace
      select name from v\$database;
EOF
   if grep -i "ORA-01034" $stdout > /dev/null; then
      echo "Error: Target database ${toraclesid} is not up running. If restoring CDB database ${toraclesid} is desired, remove -a option"
      exit 1
   fi

# if it is PDB backup using auxiliary database, need to check whether the target database has directory structure using GUID of the pdb that needs to be duplicated
   # Get guid of the PDB
   $ssqllogin << EOF > /dev/null
      spool $stdout replace
      select guid from v\$pdbs where name='${pdbname^^}';
EOF

   i=0
   while IFS= read -r line
   do
     if [[ $i -eq 1 ]]; then
        pdbguid=`echo $line | xargs`
        i=$[$i+1]
     fi
     if [[ $line =~ "-" ]];then
        i=$[$i+1]
     fi
   done < $stdout

   echo "the GUID is $pdbguid"
   
   # check whether the target database has directory structure using GUID of the pdb that needs to be duplicated and auxiliary database name
   export ORACLE_SID=$toraclesid
   sqlplus / as sysdba << EOF > /dev/null
      spool $stdout replace
      select name from v\$datafile;
EOF
 
   if [ $? -ne 0 ]; then
      echo "Error: database $toraclesid is not up running"
      exit 1
   fi
   
   if [[ $force != [Yy]* ]]; then
      if grep -i $pdbguid $stdout > /dev/null && grep -i $adbname $stdout > /dev/null ; then
         echo " "
         echo "The datafile names of the target database $toraclesid have \"GUID\" of the pdb name $pdbname and the \"auxiliary database name\" $adbname"
         echo "The query of the datafile names in the target database ${toraclesid} is in file $stdout"
	 echo "Running duplication may overwrite the existing data"
         echo " "
         read -p "Please type yes if you want to continue this duplication?  " answer4
         if [[ $answer4 != [Yy]* ]]; then
            echo "
A new auxiliary database name is needed to restore this pdb database.  
"
            exit
         fi
      fi
   fi	  
fi

# check whether the pdb that needs to be duplicated exists on target database
if [[ -n $adbname ]]; then
   if [[ -z $npdbname ]]; then
      npdbname=$pdbname
   fi
   echo "new pdb name is the same as original pdb name $pdbname"
   # Get all PDB database name in target database
   export ORACLE_SID=$toraclesid
   sqlplus / as sysdba << EOF > /dev/null
      spool $stdout replace
      select name from v\$pdbs;
EOF

   while IFS= read -r line
   do
     pdbname_target=`echo $line | xargs`
     if [[ ${pdbname_target} = ${npdbname^^} ]]; then
        echo "pdbname on target dataase is ${pdbname_target}"
        echo "Error: Pluggable database ${npdbname^^} already exists in target database $toraclesid"
	exit 1
     fi
   done < $stdout
fi

# if a restore time or sequence number were not provided when restoring to a different server, need to find the last backed up archive log sequence
if [[ -z $samehost ]]; then
   if [[ -z $itime && -z $sequence ]]; then
      echo "A restore time or sequence number were not provided. We will use the last backed up archive log sequence"
	 
# Get the last backed up archive log sequence
$ssqllogin << EOF > /dev/null
   spool $stdout replace
   select SEQUENCE#,THREAD#,FIRST_TIME from v\$backup_redolog where FIRST_TIME > sysdate-7 order by FIRST_TIME desc;
EOF

      if [ $? -ne 0 ]; then
         echo "Error: Some part of this connection string \"$ssqllogin\" is incorrect"
         exit 1
      fi


      i=0
      while IFS= read -r line
      do
         if [[ $i -eq 4 ]]; then
            sequence=`echo $line | awk '{print $1}' | xargs`
	    thread=`echo $line | awk '{print $2}' | xargs`
            break 
         fi
         i=$[$i+1]
      done < $stdout 
	  
      echo "The last backed up archive log sequence is $sequence, thread is $thread"
   fi
fi

if [[ -n $adbname ]]; then
   export ORACLE_SID=$adbname
else
   export ORACLE_SID=$toraclesid
fi

}

function check_create_oracle_init_file {

dbpfile=${ORACLE_HOME}/dbs/init${ORACLE_SID}.ora
dbspfile=${ORACLE_HOME}/dbs/spfile${ORACLE_SID}.ora

if [[ ! -f ${dbpfile} ]]; then
    echo "Error: The oracle pfile $dbpfile doesn't exist. Please check the instance name or create the pfile first."
    exit 2
fi

}

function duplicate_prepare {

#check pfile 
if [[ $force != [Yy]* ]]; then
   if [[ -n $samehost ]]; then
      echo The server $shost where the backups were taken is the server that duplicate database will be running on
#     echo ora_pfile is ${ora_pfile}
      if [[ -z `grep -i db_create_file_dest $dbpfile` && -z `grep -i db_file_name_convert $dbpfile` ]]; then
         echo "db_create_file_dest and db_file_name_convert are not defined in init file $dbpfile"
         echo " "
         read -p "Continue MAY overwrite the target database files. Do you want to continue? " answer1
         if [[ $answer1 = [Nn]* ]]; then
            exit
         fi
      else
         if [[ -n `grep -i db_create_file_dest $dbpfile` ]]; then
            db_create_location=`grep -i db_create_file_dest $dbpfile | awk -F "'" '{print $2}' | awk -F "%" '{print $1}'`
         fi
      fi
      if [[ -n ${ora_pfile} ]]; then
         db_location=`grep -i newname $ora_pfile | grep -v "#" | awk -F "'" '{print $2}' | awk -F "%" '{print $1}'`
      fi
   fi
fi

# get adump directory from dbpfile and create it if the directory doesn't exist
adump_directory=`grep -i audit_file_dest $dbpfile | awk -F "'" '{print $2}' | awk -F "%" '{print $1}'`
# remove all space in $adump_directory variable
adump_directory=`echo $adump_directory | xargs`
if [[ -n ${adump_directory} ]]; then
   echo "check adump directory. Create it if it does not exist"
   if [[ ! -d ${adump_directory} ]]; then
      echo "${adump_directory} does not exist, create it"
      mkdir -p ${adump_directory}

      if [ $? -ne 0 ]; then
         echo "Error: create new directory ${adump_directory} failed"
         exit 1
      fi
   fi
fi

# check db_create_file_dest location and create it if it is a directory and it doesn't exist
if [[ -n $db_create_location ]]; then
#   echo db_create_location is $db_create_location
# remove all space in $db_location variable
   db_create_location=`echo $db_create_location | xargs`
   echo db_create_location is $db_create_location
# check whether it is ASM or dirctory
   if [[ ${db_create_location:0:1} != "+" ]]; then
      echo "new db_create_location is a directory"
      if [[ ! -d ${db_create_location} ]]; then
         echo "${db_create_location} does not exist, create it"
         mkdir -p ${db_create_location}

         if [ $? -ne 0 ]; then
            echo "Error: create new directory ${db_create_location} failed"
            exit 1
         fi
      fi
   fi
fi



# setup restore location
# get restore location from $ora_pfile and create it if it is a directory and it doesn't exist
if [[ -z $pdbname ]]; then
  if [[ -n $ora_pfile ]]; then
    echo "ora_pfile is $ora_pfile"
    db_location=`grep -i newname $ora_pfile | grep -v "#" | awk -F "'" '{print $2}' | awk -F "%" '{print $1}'`
    arrdbloc=($db_location)
    lendbloc=${#arrdbloc[@]}
	
    for (( i=0; i<$lendbloc; i++ )); do
# check whether the directory is empty or the file exist or not
       if [[ -d ${arrdbloc[$i]} ]]; then
          lsout1=`ls -al ${arrdbloc[$i]} | grep '^-'`
          if [[ -n $lsout1 ]]; then 
             echo "The directory ${arrdbloc[$i]} has files."
#             exit 1
          fi
       fi

       if [[ -f  ${arrdbloc[$i]} ]]; then
          echo "file ${arrdbloc[$i]} exist."
#          exit 1
       fi
		  
# get the directory
       newdbdir=`echo ${arrdbloc[$i]} | awk 'BEGIN{FS=OFS="/"}{NF--; print}'`
       echo $newdbdir
# check whether it is ASM or dirctory
       if [[ ${newdbdir:0:1} != "+" ]]; then
          if [[ ! -d ${newdbdir} ]]; then
             echo "Directory ${newdbdir} does not exist, create it"
	     mkdir -pv ${newdbdir}
	  fi
  
          if [ $? -ne 0 ]; then
             echo "Error: create new directory ${newdbdir} failed"
             exit 1
          fi
       fi
    done 
  fi
fi

# test whether auxiliary database or target database is open or not. 
# If it is open, needs to shutdown it down and start the auxiliary or target database in nomount mode
# If it is not open, start the auxiliary or target database in nomount mode
runoid=`ps -ef | grep pmon | awk 'NF>1{print $NF}' | grep -i $ORACLE_SID | awk -F "pmon_" '{print $2}'`

if [[ ${runoid} != ${ORACLE_SID} ]]; then
   echo "Oracle database ${ORACLE_SID} is not up"
   echo "start the database in nomount mode"
   $sqllogin << EOF
      startup nomount pfile=${dbpfile}
EOF
else
   if [[ $force = [Yy]* ]]; then
      echo "Oracle database is up. Will shut it down and start in nomount mode"
      echo "The duplicated database will be refreshed with new data"
      $sqllogin << EOF
         shutdown immediate;
         startup nomount pfile=${dbpfile}
EOF
   else
      echo " "
      if [[ -n $pdbname ]]; then
	 if [[ -z $adbname ]]; then
	     read -p "Auxiliary database is not provided. Should target database ${ORACLE_SID} be refreshed with new data? " answer2
	 else
	     read -p "Auxiliary database is up, should database ${ORACLE_SID} be refreshed with new data? " answer2
	 fi
      else
         read -p "Oracle database is up, Should target database ${ORACLE_SID} be refreshed with new data? " answer2
      fi
      if [[ $answer2 = [Nn]* ]]; then
	     echo "If this is PDB duplication, using a auxiliary database allows the target database ${ORACLE_SID} up running"
         exit	 
      else
         $sqllogin << EOF
            shutdown immediate;
            startup nomount pfile=${dbpfile}
EOF
      fi
   fi
fi

}

function create_rman_duplicate_file {

echo "Create rman duplicate file"
echo "RUN {" >> $drmanfiled

j=0
while [ $j -lt $parallel ]; do
   while IFS= read -r ip; do
      ip=`echo $ip | xargs`    	
      if [[ -n $ip ]]; then
         if [[ $j -lt $parallel ]]; then
	    if [[ $encryption = [Yy]* ]]; then
	       if [[ $grpctype = [Yy]* ]]; then
                  allocate_database[$j]="allocate auxiliary CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,gflag_name=use_fixed_dedup_chunking,gflag_value=true,sbt_certificate_file=${encrycert})';"
               else
		  allocate_database[$j]="allocate auxiliary CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,gflag_name=use_fixed_dedup_chunking,gflag_value=true,gflag-name=sbt_use_grpc,gflag-value=false,sbt_certificate_file=${encrycert})';"
	       fi
	    else
	       if [[ $grpctype = [Yy]* ]]; then
                  allocate_database[$j]="allocate auxiliary CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,gflag_name=use_fixed_dedup_chunking,gflag_value=true)';"
               else
                  allocate_database[$j]="allocate auxiliary CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(data_view=$view,catalog_view=$cata_view,vips=$ip,gflag_name=use_fixed_dedup_chunking,gflag_value=true,gflag-name=sbt_use_grpc,gflag-value=false)';"
               fi
            fi			   
         fi
         j=$[$j+1]
      fi
   done < $vipfile
done

for (( i=0; i < ${#allocate_database[@]}; i++ )); do
   echo ${allocate_database[$i]} >> $drmanfiled
done

#echo "ora_pfile is $ora_pfile"
#more $ora_pfile
if [[ -n $ora_pfile ]]; then
  if test -f $ora_pfile; then
    grep -v "^#" < $ora_pfile | { while IFS= read -r para; do
       para=`echo $para | xargs echo -n`
       echo $para >> $drmanfiled
    done }
  else
    echo "Error: $ora_pfile does not exist"
    exit 1
  fi
fi

if [[ -n $itime ]]; then
   echo "Oracle recovery point-in-time is define. Set duplicate time until time $itime"
   echo "SET UNTIL TIME \"to_date('$itime', ''YYYY/MM/DD HH24:MI:SS')\";"
   echo "set until time \"to_date('$itime','YYYY/MM/DD HH24:MI:SS')\";" >> $drmanfiled
fi

if [[ -n $sequence ]]; then
   if [[ -n $thread ]]; then
       echo "Oracle recovery point-in-time is define. Set recover time until sequence $sequence thread $thread"
       echo "set until sequence $sequence thread $thread;" >> $drmanfiled
   else
      echo "Oracle recovery point-in-time is define. Set recover time until sequence $sequence thread 1"
      echo "set until sequence $sequence thread 1;" >> $drmanfiled
   fi
fi

if [[ -z $pdbname ]]; then
   if [[ -n $samehost ]]; then
      if [[ $noresume = [Yy]* ]]; then
         echo "duplicate database '$sdbname' to '${ORACLE_SID}' noresume;" >> $drmanfiled
      else
         echo "duplicate database '$sdbname' to '${ORACLE_SID}';" >> $drmanfiled
      fi
   else
      if [[ $noresume = [Yy]* ]]; then
         echo "duplicate database '$sdbname' to '${ORACLE_SID}' noresume nofilenamecheck;" >> $drmanfiled
      else
         echo "duplicate database '$sdbname' to '${ORACLE_SID}' nofilenamecheck;" >> $drmanfiled
      fi
   fi
else
   if [[ -n $samehost ]]; then
      if [[ $noresume = [Yy]* ]]; then
         echo "duplicate database '$sdbname' to '${ORACLE_SID}' pluggable database '$pdbname' noresume;" >> $drmanfiled
      else 
         echo "duplicate database '$sdbname' to '${ORACLE_SID}' pluggable database '$pdbname';" >> $drmanfiled
      fi
   else
      if [[ $noresume = [Yy]* ]]; then
         echo "duplicate database '$sdbname' to '${ORACLE_SID}' pluggable database '$pdbname' noresume nofilenamecheck;" >> $drmanfiled
      else
         echo "duplicate database '$sdbname' to '${ORACLE_SID}' pluggable database '$pdbname' nofilenamecheck;" >> $drmanfiled
      fi
   fi
fi  

echo "
}
exit;
" >> $drmanfiled

echo "finished creating rman duplicate file"
}

function pdbnew_create {

# create a bash scripts that unplug the new pdb database from the auxiliary database
echo "#!/bin/bash

echo \"unplug the new pdb database $pdbname from $adbname started at  \" \`/bin/date '+%Y%m%d%H%M%S'\`
export ORACLE_HOME=$oracle_home
export PATH=$PATH:$ORACLE_HOME/bin
export NLS_DATE_FORMAT='DD:MM:YYYY-HH24:MI:SS'
export ORACLE_SID=$adbname
$sqllogin << EOF > $unpluglog
   alter pluggable database $pdbname close immediate;
   alter pluggable database $pdbname unplug into '$pdbplug';
   drop pluggable database $pdbname keep datafiles;
EOF

grep -i error $unpluglog -A2 -B2

if [ \$? -eq 0 ]; then
   echo \"Error: Unpluggin pdb database from database $adbname failed at  \" \`/bin/date '+%Y%m%d%H%M%S'\`
   echo \"Need to check the error before proceeding \"
   exit 1
else
   echo \"The unplug of pdb database $pdbname from $adbname is successful at  \" \`/bin/date '+%Y%m%d%H%M%S'\`.
fi
" >> $unplug_bash

chmod 750 $unplug_bash
echo " "
echo "unplug pdb database $pdbname in CDB database $ORACLE_SID"
echo "unplug $pdbname bash script is created. It is $unplug_bash"

# create new guid for new pdbname
# create a bash scripts that plug the new pdb database to target database $toraclesid

if [[ $pdbcopy != [Yy]* ]]; then
   echo "#!/bin/bash

echo \"plug the new pdb database $pdbname to $toraclesid started at  \" \`/bin/date '+%Y%m%d%H%M%S'\`
export ORACLE_HOME=$oracle_home
export PATH=$PATH:$ORACLE_HOME/bin
export NLS_DATE_FORMAT='DD:MM:YYYY-HH24:MI:SS'
export ORACLE_SID=$toraclesid
" >> $plug_bash
   if [[ -n $npdbname ]]; then
      echo "
$sqllogin << EOF > $pluglog
    create pluggable database $npdbname as clone using '$pdbplug' tempfile reuse nocopy;
    alter pluggable database $npdbname open;
EOF
" >> $plug_bash
   else
      echo "
$sqllogin << EOF > $pluglog
    create pluggable database $pdbname as clone using '$pdbplug' tempfile reuse nocopy;
    alter pluggable database $pdbname open;
EOF 
" >> $plug_bash
   fi
else

  echo "#!/bin/bash

echo \"plug the new pdb database $pdbname to $toraclesid started at  \" \`/bin/date '+%Y%m%d%H%M%S'\`
export ORACLE_HOME=$oracle_home
export PATH=$PATH:$ORACLE_HOME/bin
export NLS_DATE_FORMAT='DD:MM:YYYY-HH24:MI:SS'
export ORACLE_SID=$toraclesid
" >> $plug_bash
   if [[ -n $npdbname ]]; then
      echo "
$sqllogin << EOF > $pluglog
    create pluggable database $npdbname as clone using '$pdbplug';
    alter pluggable database $npdbname open;
EOF
" >> $plug_bash
   else
      echo "
$sqllogin << EOF > $pluglog
    create pluggable database $pdbname as clone using '$pdbplug';
    alter pluggable database $pdbname open;
EOF
" >> $plug_bash
   fi
  
  echo "
export ORACLE_SID=$adbname
$sqllogin << EOF > $plug_aux_log
    create pluggable database $pdbname using '$pdbplug' tempfile reuse nocopy;
EOF
" >> $plug_bash
fi

echo "
grep -i error $pluglog -A2 -B2

if [ \$? -eq 0 ]; then
   echo \"Error: Pluggin pdb database to database $toraclesid failed \" \`/bin/date '+%Y%m%d%H%M%S'\`
   echo \"Will not delete auxiliary database $adbname. \"
   exit 1
else
   echo \"The plug of pdb database to database $toraclesid is successful \" \`/bin/date '+%Y%m%d%H%M%S'\`.
fi

grep -i error $plug_aux_log -A2 -B2

if [ \$? -eq 0 ]; then
   echo \"Error: Pluggin pdb database back to database $adbname failed \" \`/bin/date '+%Y%m%d%H%M%S'\`
   echo \"Will not delete auxiliary database $adbname. \"
   exit 1
else
   echo \"The plug of pdb database to database $toraclesid and $adbname is successful \" \`/bin/date '+%Y%m%d%H%M%S'\`. Will Destroy the auxiliary database $adbname next.
fi
" >> $plug_bash

chmod 750 $plug_bash
echo " "
if [[ -n $npdbname ]]; then
   echo "create new pdb database $npdbname on target database $toraclesid"
   echo "plug $npdbname bash script is created. It is $plug_bash"
else
   echo "create new pdb database $pdbname on target database $toraclesid"
   echo "plug $pdbname bash script is created. It is $plug_bash"
fi
}

function destroy_aux_create {

echo "
Delete auxiliary database $adbname after pdb $pdbname restore is successful"

echo "#!/bin/bash

echo \"save auxiliary database $adbname pfile before destroy it\"
cp ${ORACLE_HOME}/dbs/init${adbname}.ora ${ORACLE_HOME}/dbs/init${adbname}.save.ora
cp ${ORACLE_HOME}/dbs/init${adbname}.ora $DIR/log/$thost/init${adbname}.save.ora
echo \"Destroy auxiliary database $adbname started at  \" \`/bin/date '+%Y%m%d%H%M%S'\`
export ORACLE_HOME=$oracle_home
export PATH=$PATH:$ORACLE_HOME/bin
export NLS_DATE_FORMAT='DD:MM:YYYY-HH24:MI:SS'
export ORACLE_SID=$adbname
$sqllogin << EOF
   shutdown immediate
EOF

# test whether auxiliary database is  still open or not. 
# If it is open, will exit
runoid=`ps -ef | grep pmon | awk 'NF>1{print $NF}' | grep -i $adbname | awk -F "pmon_" '{print $2}'`

if [[ \${runoid} != \${adbname} ]]; then
   echo "Oracle database ${adbname} is not up"
   echo "start the database in  mount exclusive"
   $sqllogin << EOF
      startup mount exclusive;
      Alter system enable restricted session;
EOF
   rman log $destroylog << EOF
     connect target /
     drop database including backups noprompt;
EOF
   
   if [ \$? -eq 0 ]; then
      echo \"auxiliary database $adbname is dropped successful. \" \`/bin/date '+%Y%m%d%H%M%S'\`
   else
      echo \"Error: drop auxiliary database $adbname failed. \" \`/bin/date '+%Y%m%d%H%M%S'\`
      exit 1
   fi
else
    echo \"auxiliary database $adbname is still up \"
fi
" >> $destroy_aux_bash

chmod 750 $destroy_aux_bash

echo "Delete auxiliary database $adbname bash script is created. It is $destroy_aux_bash"
echo " "

}


function duplicate {

echo "Database duplicate started at " `/bin/date '+%Y%m%d%H%M%S'`
echo "ORACLE SID is $ORACLE_SID"

if [[ -n $targetc ]]; then
   rman log $drmanlog << EOF
   connect auxiliary /
   connect target '${targetc}'
   @$drmanfiled
EOF
fi

if [[ -n $catalogc ]]; then
   rman log $drmanlog << EOF
   connect auxiliary /
   connect catalog '${catalogc}'
   @$drmanfiled
EOF
fi

if [[ `grep -i error ${drmanlog}` ]]; then
  if [[ `grep -i "c0 not allocated" $drmanlog` ]]; then
     echo "Database duplicate finished at " `/bin/date '+%Y%m%d%H%M%S'`
  else
     echo "Database duplicate failed at " `/bin/date '+%Y%m%d%H%M%S'`
	 echo "spfile is"
     ls -l ${oracle_home}/dbs/spfile${toraclesid}.ora
     echo "Check rmanlog file $drmanlog"
     echo "The last 10 line of rman log output"
     echo " "
     tail $drmanlog
	 echo " "
     echo "Error: Once the error is identified and corrected, you can rerun the duplicate command. 
Please make sure the target or auxiliary database is shutdown and the files associated with database removed before the rerun.
Please verify it is the target or auxiliary database by running the following the SQLPLUS command \"select name from v\$database;\" and \"select open_mode from v\$database;\"
before shutdown the auxiliary database.
	 "
     exit 1
   fi
else
  echo "Database duplicate finished at " `/bin/date '+%Y%m%d%H%M%S'`
fi

}

setup
if [[ $preview != [Yy]* ]]; then
   echo prepare duplication
   echo " "
   check_create_oracle_init_file
   if [[ $force = [Yy]* ]]; then
      duplicate_prepare
   else
      echo "The init file $dbpfile needs to be created first. The successful of this duplication depends on the content of that file.
	       "
      if [[ -z $pdbname ]]; then
         read -p "It is reommended to clean up the the files associated with database $toraclesid first. Please type yes if you want to continue this duplication? " answer3
         if [[ $answer3 != [Yy]* ]]; then
            exit
         fi
      fi
      duplicate_prepare
   fi
fi
create_rman_duplicate_file
if [[ $preview = [Yy]* ]]; then
   echo " "
   echo ORACLE DATABASE DUPLICATE RMAN script is $drmanfiled
   echo " "
   if [[ -n $adbname ]]; then
      pdbnew_create
      destroy_aux_create
   fi
else
   if [[ $force = [Yy]* ]]; then
      duplicate
      if [[ -n $adbname ]]; then
         pdbnew_create
         destroy_aux_create
         $unplug_bash
         $plug_bash
         $destroy_aux_bash
      fi
   else
      duplicate
      if [[ -n $adbname ]]; then
         pdbnew_create 
         destroy_aux_create
         $unplug_bash		 
         if [[ -z $pdbcopy ]]; then
	     read -p "This plug operation will not move the database file structure from auxiliary database to target database. Please type yes if you want to continue this plug operation? " answer5
             if [[ $answer5 != [Yy]* ]]; then
	        echo "The plug script $plug_bash can be modify and run it manually. Once it is successful, $destroy_aux_bash can run to delete the auxiliary database manually"
	        exit
	     else
                $plug_bash
                $destroy_aux_bash
	     fi
          else
             $plug_bash
             $destroy_aux_bash
	  fi
      fi
   fi
fi
