#!/bin/bash
#
# Name:         restore-ora-coh-sbt.bash
#
# Function:     This script restore Oracle database from Oracle backup 
#               using Cohesity SBT tape backup script backup-ora-coh-sbt.bash.
#
#
# Show Usage: run the command to show the usage
#
# Changes:
# 07/25/20 Diana Yang   New script (restore to target database)
# 07/31/20 Diana Yang   Add controlfile restore
# 08/06/20 Diana Yang   Rename this file from restore-ora-coh-dedup.bash to restore-ora-coh-sbt.bash
# 08/16/20 Diana Yang   All set newname during restore
# 10/30/20 Diana Yang   Standardlize name. Remove "-f" and "-s" as required parameter
# 11/11/20 Diana Yang   Remove the need to manually create vip-list file
# 03/13/21 Diana Yang   Add an option to use recovery catalog for restore
# 04/29/21 Diana Yang   Change syntax to use new sbt library
# 09/13/21 Diana Yang   Add encryption-in-flight
# 09/13/21 Diana Yang   Add an option to use SunRPC
# 04/04/22 Diana Yang   Check init file before restore
#
#################################################################

function show_usage {
echo "usage: restore-ora-coh-sbt.bash -h <backup host> -c <Catalog connection> -i <Oracle instance name> -d <Oracle_DB_Name> -y <Cohesity-cluster> -t <point-in-time> -l <yes/no> -j <vip file> -v <view> -s <sbt file name> -p <number of channels> -o <ORACLE_HOME> -f <yes/no> -w <yes/no> -g <yes/no> -k <cert path> -x <yes/no>"
echo " "
echo " Required Parameters"
echo " -i : Oracle instance name. If it is not RAC, it is the same as DB name. If it is RAC, it is the instance name like cohcdba2"
echo " -d : Source Oracle_DB_Name, only required if it is RAC. It is DB name, not instance name"
echo " -y : Cohesity Cluster DNS name"
echo " -v : Cohesity view"
echo " -f : yes means force. It will restore Oracle database. Without it, it will just run RMAN validate (Optional)"
echo " "
echo " Optional Parameters"
echo " -h : Oracle database host that the backup was run. (default is current host), optional"
echo " -c : Catalog connection (example: \"<dbuser>/<dbpass>@<catalog connection string>\", optional)"
echo " -t : Point in Time (format example: \"2019-01-27 13:00:00\"), optional"
echo " -l : yes means complete restore including control file, no means not restoring controlfile"
echo " -p : number of channels (default is 4), optional"
echo " -j : The file lists Cohesity Cluster VIPs (default name is vip-list and default directory is config)"
echo " -s : Cohesity SBT library name including directoy or just directory (default name is libsbt_6_and_7_linux-x86_64.so, default directory is lib) "
echo " -o : ORACLE_HOME (default is current environment), optional"
echo " -g : yes means encryption-in-flight is used. The default is no"
echo " -k : encryption certificate file directory, default directory is lib"
echo " -x : yes means gRPC is used. no means SunRPC is used. The default is yes"
echo " -w : yes means preview rman backup scripts"
}

while getopts ":h:c:i:d:t:y:l:j:v:s:p:o:f:g:k:x:w:" opt; do
  case $opt in
    h ) shost=$OPTARG;;
    c ) catalogc=$OPTARG;;
    i ) oraclesid=$OPTARG;;
    d ) dbname=$OPTARG;;
    t ) itime=$OPTARG;;
    y ) cohesityname=$OPTARG;;
    l ) full=$OPTARG;;
    j ) vipfile=$OPTARG;;
    v ) view=$OPTARG;;
    s ) sbtname=$OPTARG;;
    p ) parallel=$OPTARG;;
    o ) oracle_home=$OPTARG;;
    f ) force=$OPTARG;;
    g ) encryption=$OPTARG;;
    k ) encrydir=$OPTARG;;
    x ) grpctype=$OPTARG;;
    w ) preview=$OPTARG;;
  esac
done

#echo $oraclesid  $full $view $sbtname $vipfile

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

#if test $host && test $dbname && test $mount && test $numm
if test $oraclesid  && test $view 
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
      echo "Please enter 'yes' as the argument for -f. It may be empty or not all options are given an argument. All options should be given an arguments"
      exit 2
   else
      if [[ $force != [Yy]* ]]; then
         echo "'yes' should be provided after -f in syntax, other answer is not valid"
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
   if [[ ${fullcommand[$i]} == -l ]]; then
      fullset=yes
   fi
done
if [[ -n $fullset ]]; then
   if [[ -z $full ]]; then
      echo "Please enter 'yes' as the argument for -l. It may be empty or not all options are given an argument. All options should be given an arguments"
      exit 2
   else
      if [[ $full != [Yy]* ]]; then
         echo "'yes' should be provided after -l in syntax, other answer is not valid"
	 exit 2
      fi
   fi 
fi

function setup {
host=`hostname -s`
if test $shost
then
  :
else
  shost=$host
fi

if test $dbname
then
  : 
else
  echo "Oracle instance name ${oraclesid} is provided. If it is RAC or Standby database, please provide Oracle database name" 
  dbname=$oraclesid
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
      echo "Please enter 'yes' or 'no' as the argument for -x. It may be empty or not all options are given an argument. All options should be given an arguments"
      exit 2
   else
      if [[ $grpctype != [Yy]* && $grpctype != [Nn]* ]]; then
         echo "'yes' or 'no' needs to be provided after -x in syntax, other answer is not valid"
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
      echo "Please enter 'yes' or 'no' as the argument for -g. It may be empty or not all options are given an argument. All options should be given an arguments"
      exit 2
   else
      if [[ $encryption != [Yy]* && $encryption != [Nn]* ]]; then
         echo "'yes' or 'no' needs to be provided after -x in syntax, other answer is not valid"
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
      echo "Please enter the encryption key absoluate path as the argument for -k. It may be empty or not all options are given an argument. All options should be given an arguments"
      exit 2
   else
      if [[ $encrydir != / ]]; then
         echo "Encryption key absoluate path should be provided"
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
      echo "Please enter a time as the argument for -t. It may be empty or not all options are given an argument. All options should be given an arguments"
      exit 2
   else
      if [[ $itime == *\"* ]]; then
         echo "There should not be \ after -t in syntax. It should be -t \"date time\", example like \"2019-01-27 13:00:00\" "
	 exit 2
      fi
   fi 
fi


#if [[ -n $itime && $full != [Yy]* ]]; then
#  echo "Point in time restore requires restore controlfile The option -l should be yes"
#  exit 1
#fi

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
  vipfile=${DIR}/config/${oraclesid}-vip-list
  echo "Cohesity Cluster name is $cohesityname. VIPS will be collected and stored in $vipfile"
  nslookup $cohesityname | grep -i address | tail -n +2 | awk '{print $2}' > $vipfile
  
  if [[ ! -s $vipfile ]]; then
     echo "Cohesity Cluster name $cohesityname provided here is not in DNS"
     exit 1
  fi

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

if [[ ! -f $DIR/tools/sbt_list ]]; then
   echo "$DIR/tools/sbt_list file does not exist. Please copy sbt_list tool to $DIR/tools directory"
   exit 1
fi
   
restore_rmanlog=$DIR/log/$host/$dbname.rman-restore.$DATE_SUFFIX.log
restore_rmanfile=$DIR/log/$host/$dbname.rman-restore.$DATE_SUFFIX.rcv
recover_rmanlog=$DIR/log/$host/$dbname.rman-recover.$DATE_SUFFIX.log
recover_rmanfile=$DIR/log/$host/$dbname.rman-recover.$DATE_SUFFIX.rcv
controlfile_list=$DIR/log/$host/$dbname.controlfile.$DATE_SUFFIX.list
spfile_rmanlog=$DIR/log/$host/$dbname.rman-spfile.$DATE_SUFFIX.log
spfile_rmanfile=$DIR/log/$host/$dbname.rman-spfile.$DATE_SUFFIX.rcv
controlfile_rmanlog=$DIR/log/$host/$dbname.rman-controlfile.$DATE_SUFFIX.log
controlfile_rmanfile=$DIR/log/$host/$dbname.rman-controlfile.$DATE_SUFFIX.rcv
incarnation=$DIR/log/$host/$dbname.incar_list
stdout=$DIR/log/$host/${dbname}.$DATE_SUFFIX.std

# setup restore location

# covert the time to numeric 
if [[ -z $itime ]]; then
  ptime=`/bin/date '+%Y%m%d%H%M%S'`
  echo "current time is `/bin/date`,  point-in-time restore time $ptime"  
else   
  ptime=`/bin/date -d "$itime" '+%Y%m%d%H%M%S'`
  echo "itime is $itime,  point-in-time restore time $ptime"
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

export ORACLE_SID=$oraclesid
}

function check_create_oracle_init_file {

if [[ ! -f $ORACLE_HOME/dbs/init${oraclesid}.ora ]]; then
    echo "The oracle pfile $ORACLE_HOME/dbs/init${oraclesid}.ora doesn't exist. Please check the instance name or create the pfile first."
	exit 2
fi

}

function create_rman_restore_controlfile_nocatalog {

# find the right controlfile backup

echo "Let's find the right controfile backup file"

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

#echo $ip
${DIR}/tools/sbt_list --view=$view/$shost/${dbname^^} --vips=$ip | sort -nk1 | grep -i ${dbname}_c- > ${controlfile_list}
if [[ ! -s ${controlfile_list} ]]; then
   ${DIR}/tools/sbt_list --view=$view/$shost/${dbname} --vips=$ip | sort -nk1 | grep -i ${dbname}_c- > ${controlfile_list}
   if [[ ! -s ${controlfile_list} ]]; then
      ${DIR}/tools/sbt_list --view=$view/$shost/${oraclesid^^} --vips=$ip | sort -nk1 | grep -i ${dbname}_c- > ${controlfile_list}
      if [[ ! -s ${controlfile_list} ]]; then
         ${DIR}/tools/sbt_list --view=$view/$shost/${oraclesid} --vips=$ip | sort -nk1 | grep -i ${dbname}_c- > ${controlfile_list}
         if [[ ! -s ${controlfile_list} ]]; then
            echo "
	    controlfile is not found in $view/$shost/$dbname or $view/$shost/${dbname^^} or $view/$shost/$oraclesid or $view/$shost/${oraclesid^^}. 
   	    Please verify the arguments provided to -i and -d, and -h options
	    "
	    exit 2
	 else
            backupdir=${shost}/${oraclesid}
         fi			
      else
         backupdir=${shost}/${oraclesid^^}
      fi
   else
      backupdir=${shost}/${dbname}
   fi
else
   backupdir=${shost}/${dbname^^}
fi
#echo "${DIR}/tools/sbt_list --view=$view/$shost/$dbname --vips=$ip | sort -nk1 | grep ${dbname^^}_c-"

while IFS= read -r line; do
   line=`echo $line | xargs`
   bitime=`echo $line | awk '{print $1}'`
   btime=`/bin/date -d "${bitime/-/ }" '+%Y%m%d%H%M%S'`
   if [[ $ptime -lt $btime ]]; then
      controlfile=`echo $line | awk '{print $3}'`
      oribtime=${btime::${#btime}-2}
      break
   else
      controlfile1=`echo $line | awk '{print $3}'`
      oribtime1=${btime::${#btime}-2}
   fi
done < ${controlfile_list}

if [[ -z $controlfile ]]; then
   if [[ -z $controlfile1 ]]; then
     echo "The controlfile for database $dbname at $ptime is not found"
     exit 1
   else
     controlfile=$controlfile1
     oribtime=$oribtime1
   fi
fi

echo "The controlfile is $controlfile"

# get DBID
dbid=`echo $controlfile | awk -F "-" '{print $2}'`
echo "dbid of this database is $dbid"

echo "will create spfile rman backup script"
echo controlfile backup file is $controlfile

if [[ $encryption = [Yy]* ]]; then
   if [[ $grpctype = [Yy]* ]]; then
      echo "
run {
set dbid $dbid;
allocate CHANNEL c1 TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view/${backupdir},vips=$ip,gflag_name=use_fixed_dedup_chunking,gflag_value=true,sbt_certificate_file=${encrycert})';
restore spfile from '$controlfile';
release CHANNEL c1;
}
" >> $spfile_rmanfile
   else	
      echo "
run {
set dbid $dbid;
allocate CHANNEL c1 TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view/${backupdir},vips=$ip,gflag_name=use_fixed_dedup_chunking,gflag_value=true,gflag-name=sbt_use_grpc,gflag-value=false,sbt_certificate_file=${cert})';
restore spfile from '$controlfile';
release CHANNEL c1;
}
" >> $spfile_rmanfile
   fi
else
   if [[ $grpctype = [Yy]* ]]; then
      echo "
run {
set dbid $dbid;
allocate CHANNEL c1 TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view/${backupdir},vips=$ip,gflag_name=use_fixed_dedup_chunking,gflag_value=true)';
restore spfile from '$controlfile';
release CHANNEL c1;
}
" >> $spfile_rmanfile
   else 
      echo "
run {
set dbid $dbid;
allocate CHANNEL c1 TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view/${backupdir},vips=$ip,gflag_name=use_fixed_dedup_chunking,gflag_value=true,gflag-name=sbt_use_grpc,gflag-value=false)';
restore spfile from '$controlfile';
release CHANNEL c1;
}
" >> $spfile_rmanfile
   fi
fi

echo "will create controlfile rman backup script"
if [[ $encryption = [Yy]* ]]; then
   if [[ $grpctype = [Yy]* ]]; then
      echo "
run {
allocate CHANNEL c1 TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view/${backupdir},vips=$ip,gflag_name=use_fixed_dedup_chunking,gflag_value=true,sbt_certificate_file=${cert})';
restore CONTROLFILE from '$controlfile';
release CHANNEL c1;
}
" >> $controlfile_rmanfile
   else
      echo "
run {
allocate CHANNEL c1 TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view/${backupdir},vips=$ip,gflag_name=use_fixed_dedup_chunking,gflag_value=true,gflag-name=sbt_use_grpc,gflag-value=false,sbt_certificate_file=${cert})';
restore CONTROLFILE from '$controlfile';
release CHANNEL c1;
}
" >> $controlfile_rmanfile
   fi
else
   if [[ $grpctype = [Yy]* ]]; then
      echo "
run {
allocate CHANNEL c1 TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view/${backupdir},vips=$ip,gflag_name=use_fixed_dedup_chunking,gflag_value=true)';
restore CONTROLFILE from '$controlfile';
release CHANNEL c1;
}
" >> $controlfile_rmanfile
   else
	  echo "
run {
allocate CHANNEL c1 TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view/${backupdir},vips=$ip,gflag_name=use_fixed_dedup_chunking,gflag_value=true,gflag-name=sbt_use_grpc,gflag-value=false)';
restore CONTROLFILE from '$controlfile';
release CHANNEL c1;
}
" >> $controlfile_rmanfile
   fi
fi

}

function create_rman_restore_controlfile_catalog {

# find DBID

#echo "need to get DBID"

#read -p "Enter the DBID of this database: " dbid
  
# Check Cohesity IP connection
i=1
while IFS= read -r ip; do
    
   ip=`echo $ip | xargs`    	
   if [[ -n $ip ]]; then
      break   
   else
      i=$[$i+1]
   fi 
done < $vipfile

# get dbid
#echo "need to get DBID"
${DIR}/tools/sbt_list --view=$view/$shost/${dbname^^} --vips=$ip | sort -nk1 | grep -i ${dbname}_c- > ${controlfile_list}
if [[ ! -s ${controlfile_list} ]]; then
   ${DIR}/tools/sbt_list --view=$view/$shost/${dbname} --vips=$ip | sort -nk1 | grep -i ${dbname}_c- > ${controlfile_list}
   if [[ ! -s ${controlfile_list} ]]; then
      ${DIR}/tools/sbt_list --view=$view/$shost/${oraclesid^^} --vips=$ip | sort -nk1 | grep -i ${dbname}_c- > ${controlfile_list}
      if [[ ! -s ${controlfile_list} ]]; then
	 ${DIR}/tools/sbt_list --view=$view/$shost/${oraclesid} --vips=$ip | sort -nk1 | grep -i ${dbname}_c- > ${controlfile_list}
         if [[ ! -s ${controlfile_list} ]]; then
            echo "
	    controlfile is not found in $view/$shost/$dbname or $view/$shost/${dbname^^} or $view/$shost/$oraclesid or $view/$shost/${oraclesid^^}. 
            Please verify the arguments provided to -i and -d, and -h options
	    "
	    exit 2
	 else
            backupdir=${shost}/${oraclesid}
         fi			
      else
         backupdir=${shost}/${oraclesid^^}
      fi
   else
      backupdir=${shost}/${dbname}
   fi
else
backupdir=${shost}/${dbname^^}
fi

while IFS= read -r line; do
   line=`echo $line | xargs`
   bitime=`echo $line | awk '{print $1}'`
   btime=`/bin/date -d "${bitime/-/ }" '+%Y%m%d%H%M%S'`
   if [[ $ptime -lt $btime ]]; then
      controlfile=`echo $line | awk '{print $3}'`
	  oribtime=${btime::${#btime}-2}
      break
   else
      controlfile1=`echo $line | awk '{print $3}'`
	  oribtime1=${btime::${#btime}-2}
   fi
done < ${controlfile_list}

if [[ -z $controlfile ]]; then
   if [[ -z $controlfile1 ]]; then
     echo "The controlfile for database $dbname at $ptime is not found"
     exit 1
   else
     controlfile=$controlfile1
     oribtime=$oribtime1
   fi
fi

echo "The controlfile is $controlfile"

# get DBID
dbid=`echo $controlfile | awk -F "-" '{print $2}'`
echo "dbid of this database is $dbid"

echo "will create spfile rman backup script"
if [[ $encryption = [Yy]* ]]; then
   if [[ $grpctype = [Yy]* ]]; then
      echo "
run {
set dbid $dbid;
allocate CHANNEL c1 TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,gflag_name=use_fixed_dedup_chunking,gflag_value=true,sbt_certificate_file=${encrycert})';
restore spfile FROM AUTOBACKUP;
release CHANNEL c1;
}
" >> $spfile_rmanfile
   else
      echo "
run {
set dbid $dbid;
allocate CHANNEL c1 TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,gflag_name=use_fixed_dedup_chunking,gflag_value=true,gflag-value=false,sbt_certificate_file=${encrycert})';
restore spfile FROM AUTOBACKUP;
release CHANNEL c1;
}
" >> $spfile_rmanfile
   fi
else
   if [[ $grpctype = [Yy]* ]]; then
      echo "
run {
set dbid $dbid;
allocate CHANNEL c1 TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,gflag_name=use_fixed_dedup_chunking,gflag_value=true)';
restore spfile FROM AUTOBACKUP;
release CHANNEL c1;
}
" >> $spfile_rmanfile
   else
     echo "
run {
set dbid $dbid;
allocate CHANNEL c1 TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,gflag_name=use_fixed_dedup_chunking,gflag_value=true,gflag-name=sbt_use_grpc,gflag-value=false)';
restore spfile FROM AUTOBACKUP;
release CHANNEL c1;
}
" >> $spfile_rmanfile
   fi
fi
   

echo "will create controlfile rman backup script"
if [[ $encryption = [Yy]* ]]; then
   if [[ $grpctype = [Yy]* ]]; then
      echo "
run {
allocate CHANNEL c1 TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,gflag_name=use_fixed_dedup_chunking,gflag_value=true,sbt_certificate_file=${encrycert})';
restore CONTROLFILE FROM AUTOBACKUP;
release CHANNEL c1;
}
" >> $controlfile_rmanfile
   else
      echo "
run {
allocate CHANNEL c1 TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,gflag_name=use_fixed_dedup_chunking,gflag_value=true,gflag-name=sbt_use_grpc,gflag-value=false,sbt_certificate_file=${encrycert})';
restore CONTROLFILE FROM AUTOBACKUP;
release CHANNEL c1;
}
" >> $controlfile_rmanfile
   fi
else
   if [[ $grpctype = [Yy]* ]]; then
      echo "
run {
allocate CHANNEL c1 TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,gflag_name=use_fixed_dedup_chunking,gflag_value=true)';
restore CONTROLFILE FROM AUTOBACKUP;
release CHANNEL c1;
}
" >> $controlfile_rmanfile
   else
     echo "
run {
allocate CHANNEL c1 TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,gflag_name=use_fixed_dedup_chunking,gflag_value=true,gflag-name=sbt_use_grpc,gflag-value=false)';
restore CONTROLFILE FROM AUTOBACKUP;
release CHANNEL c1;
}
" >> $controlfile_rmanfile
   fi
fi
     

}

function reset_incarnation_afterrestore {

echo "incarnation after restore"
$rmanlogin log $incarnation << EOF
list incarnation of database;
exit;
EOF

incar_num2=`grep -i $dbname  $incarnation | grep -i CURRENT | awk '{print $2}'`
echo "Oracle database incarnation is $incar_num2"

if [[ $incar_num1 != $incar_num2 ]]; then
   echo "reset database incarnation"
   $rmanlogin  << EOF
   reset database to incarnation $incar_num1;
   exit;
EOF
else
   echo "no need to reset database incarnation"
fi

echo "incarnation after reset"
$rmanlogin log $incarnation << EOF
list incarnation of database;
exit;
EOF

incar_num3=`grep -i $dbname  $incarnation | grep -i CURRENT | awk '{print $2}'`
echo "Oracle database incarnation is $incar_num3"

}

function create_rman_restore_database_file {

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

echo "Create rman restore database file"
if [[ $encryption = [Yy]* ]]; then
   if [[ $grpctype = [Yy]* ]]; then
       echo "ALLOCATE CHANNEL FOR MAINTENANCE DEVICE TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,gflag_name=use_fixed_dedup_chunking,gflag_value=true,sbt_certificate_file=${encrycert})';
       RUN {" >> $restore_rmanfile
   else 
       echo "ALLOCATE CHANNEL FOR MAINTENANCE DEVICE TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,gflag_name=use_fixed_dedup_chunking,gflag_value=true,gflag-name=sbt_use_grpc,gflag-value=false,sbt_certificate_file=${encrycert})';
	   RUN {" >> $restore_rmanfile
   fi
else
   if [[ $grpctype = [Yy]* ]]; then
       echo "ALLOCATE CHANNEL FOR MAINTENANCE DEVICE TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,gflag_name=use_fixed_dedup_chunking,gflag_value=true)';
	   RUN {" >> $restore_rmanfile
   else
       echo "ALLOCATE CHANNEL FOR MAINTENANCE DEVICE TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,gflag_name=use_fixed_dedup_chunking,gflag_value=true,gflag-name=sbt_use_grpc,gflag-value=false)';
	   RUN {" >> $restore_rmanfile
   fi
fi

j=0
while [ $j -lt $parallel ]; do

   while IFS= read -r ip; do
    
      ip=`echo $ip | xargs`    	
      if [[ -n $ip ]]; then
        	      	
         if [[ $j -lt $parallel ]]; then
	    if [[ $encryption = [Yy]* ]]; then
	       if [[ $grpctype = [Yy]* ]]; then
	    	  allocate_database[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,gflag_name=use_fixed_dedup_chunking,gflag_value=true,sbt_certificate_file=${encrycert})';"
	       else
	          allocate_database[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,gflag_name=use_fixed_dedup_chunking,gflag_value=true,gflag-name=sbt_use_grpc,gflag-value=false,sbt_certificate_file=${encrycert})';"
	       fi
            else
	       if [[ $grpctype = [Yy]* ]]; then
                  allocate_database[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,gflag_name=use_fixed_dedup_chunking,gflag_value=true)';"
               else
                  allocate_database[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,gflag_name=use_fixed_dedup_chunking,gflag_value=true,gflag-name=sbt_use_grpc,gflag-value=false)';"
               fi
            fi				
            unallocate[$j]="release channel c$j;"
         fi
         j=$[$j+1]
      fi
   done < $vipfile
done


for (( i=0; i < ${#allocate_database[@]}; i++ )); do
   echo ${allocate_database[$i]} >> $restore_rmanfile
done

if [[ -n $itime ]]; then
   echo "Oracle recovery point-in-time is define. Set recover time until $itime"
   echo "SET UNTIL TIME \"to_date('$itime', ''YYYY/MM/DD HH24:MI:SS')\";"
   echo "set until time \"to_date('$itime','YYYY/MM/DD HH24:MI:SS')\";" >> $restore_rmanfile
fi

if [[ -z $force ]]; then
   echo "restore database validate; " >> $restore_rmanfile
else
   echo "restore database;" >> $restore_rmanfile
fi


for (( i=0; i < ${#unallocate[@]}; i++ )); do
   echo ${unallocate[$i]} >> $restore_rmanfile
done

echo "
}
" >> $restore_rmanfile

echo "finished creating rman restore database file"
}

function create_rman_recover_database_file {

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

echo "Create rman restore database file"
if [[ $encryption = [Yy]* ]]; then
   if [[ $grpctype = [Yy]* ]]; then
       echo "ALLOCATE CHANNEL FOR MAINTENANCE DEVICE TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,gflag_name=use_fixed_dedup_chunking,gflag_value=true,sbt_certificate_file=${encrycert})';
       RUN {" >> $recover_rmanfile
   else 
       echo "ALLOCATE CHANNEL FOR MAINTENANCE DEVICE TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,gflag_name=use_fixed_dedup_chunking,gflag_value=true,gflag-name=sbt_use_grpc,gflag-value=false,sbt_certificate_file=${encrycert})';
	   RUN {" >> $recover_rmanfile
   fi
else
   if [[ $grpctype = [Yy]* ]]; then
       echo "ALLOCATE CHANNEL FOR MAINTENANCE DEVICE TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,gflag_name=use_fixed_dedup_chunking,gflag_value=true)';
	   RUN {" >> $recover_rmanfile
   else
       echo "ALLOCATE CHANNEL FOR MAINTENANCE DEVICE TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,gflag_name=use_fixed_dedup_chunking,gflag_value=true,gflag-name=sbt_use_grpc,gflag-value=false)';
	   RUN {" >> $recover_rmanfile
   fi
fi

j=0
while [ $j -lt $parallel ]; do

   while IFS= read -r ip; do
    
      ip=`echo $ip | xargs`    	
      if [[ -n $ip ]]; then
        	      	
         if [[ $j -lt $parallel ]]; then
	    if [[ $encryption = [Yy]* ]]; then
	       if [[ $grpctype = [Yy]* ]]; then
	    	  allocate_database[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,gflag_name=use_fixed_dedup_chunking,gflag_value=true,sbt_certificate_file=${encrycert})';"
	       else
	          allocate_database[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,gflag_name=use_fixed_dedup_chunking,gflag_value=true,gflag-name=sbt_use_grpc,gflag-value=false,sbt_certificate_file=${encrycert})';"
	       fi
            else
	       if [[ $grpctype = [Yy]* ]]; then
                  allocate_database[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,gflag_name=use_fixed_dedup_chunking,gflag_value=true)';"
               else
                  allocate_database[$j]="allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,gflag_name=use_fixed_dedup_chunking,gflag_value=true,gflag-name=sbt_use_grpc,gflag-value=false)';"
               fi
            fi				
            unallocate[$j]="release channel c$j;"
         fi
         j=$[$j+1]
      fi
   done < $vipfile
done


for (( i=0; i < ${#allocate_database[@]}; i++ )); do
   echo ${allocate_database[$i]} >> $recover_rmanfile
done

if [[ -n $itime ]]; then
   echo "Oracle recovery point-in-time is define. Set recover time until $itime"
   echo "SET UNTIL TIME \"to_date('$itime', ''YYYY/MM/DD HH24:MI:SS')\";"
   echo "set until time \"to_date('$itime','YYYY/MM/DD HH24:MI:SS')\";" >> $recover_rmanfile
fi

echo "recover database;" >> $recover_rmanfile

for (( i=0; i < ${#unallocate[@]}; i++ )); do
   echo ${unallocate[$i]} >> $recover_rmanfile
done

echo "
}
" >> $recover_rmanfile

if [[ $force != [Yy]* ]]; then
  echo "
  exit;
  " >> $recover_rmanfile
else
  if [[ $full = [Yy]* ]]; then
    echo "
    alter database open resetlogs;
    exit;
    " >> $recover_rmanfile
  else
    if [[ -n $itime ]]; then
       echo "
       alter database open resetlogs;
       exit;
       " >> $recover_rmanfile
    else
       echo "
       alter database open;
       exit;
       " >> $recover_rmanfile
    fi	   
  fi
fi

echo "finished creating rman recover database file"
}


function restore_controlfile {
	
echo "will restore controlfile"
echo "check whether the database is up"
runoid=`ps -ef | grep pmon | awk 'NF>1{print $NF}' | grep -i $oraclesid | awk -F "pmon_" '{print $2}'`
sidlist=($runoid)
match=no
for (( i=0; i<${#sidlist[@]}; i++ ))
do 
   if [[ ${sidlist[$i]} == $oraclesid ]]; then 
      match=yes
   fi
done

if [[ $match != "yes" ]]; then
   echo "Oracle database $oraclesid is not up"
   echo "start the database in nomount, restore spfile, and restart the database in nomount"
   $sqllogin << EOF
   startup nomount;
EOF

   echo "spfile restore started at " `/bin/date '+%Y%m%d%H%M%S'`

   if [[ -z $catalogc ]]; then
      rman log $spfile_rmanlog << EOF
      connect target '${targetc}'
      @$spfile_rmanfile
EOF
   else
      rman log $spfile_rmanlog << EOF
      connect target '${targetc}'
      connect catalog '${catalogc}'
      @$spfile_rmanfile
EOF
   fi

   $sqllogin << EOF
   shutdown immediate;
   startup nomount
EOF
else
   echo "Oracle database $oraclesid is up"
   echo "shutdown the database first"
   echo "start the database in nomount, restore spfile, and restart the database in nomount"
   $sqllogin << EOF
   shutdown immediate;
   startup nomount;
EOF
   if [[ -z $catalogc ]]; then
      rman log $spfile_rmanlog << EOF
      connect target '${targetc}'
      @$spfile_rmanfile
EOF
   else
      rman log $spfile_rmanlog << EOF
      connect target '${targetc}'
      connect catalog '${catalogc}'
      @$spfile_rmanfile
EOF
   fi
   
   $sqllogin << EOF
   shutdown immediate;
   startup nomount
EOF
fi

echo "The database should be up. If not, exit"
runoid=`ps -ef | grep pmon | awk 'NF>1{print $NF}' | grep -i $oraclesid | awk -F "pmon_" '{print $2}'`
sidlist=($runoid)
match=no
for (( i=0; i<${#sidlist[@]}; i++ ))
do 
   if [[ ${sidlist[$i]} == $oraclesid ]]; then 
      match=yes
   fi
done

if [[ $match != "yes" ]]; then
   echo "Oracle database $oraclesid is not up"
   exit 1 
fi

echo "restore controlfile $controlfile"

if [[ -z $catalogc ]]; then
   rman log $controlfile_rmanlog << EOF
   connect target '${targetc}'
   @$controlfile_rmanfile
EOF
else
   rman log $controlfile_rmanlog << EOF
   connect target '${targetc}'
   connect catalog '${catalogc}'
   @$controlfile_rmanfile
EOF
fi

if [ $? -ne 0 ]; then
  echo "   "
  echo "restore controlfile $controlfile failed at " `/bin/date '+%Y%m%d%H%M%S'`
  ls -l ${ORACLE_HOME}/dbs/spfile*
  echo "The last 10 line of rman log output"
  echo " "
  echo "rmanlog file is $controlfile_rmanlog"
  tail $controlfile_rmanlog
  exit 1
else
  echo "  "
  echo "restore controlfile finished at " `/bin/date '+%Y%m%d%H%M%S'`
fi

echo "Change database to mount mode"
$sqllogin << EOF
alter database mount;
EOF

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

if [[ $open_mode != "MOUNTED" ]]; then
   echo "database is not in mount open mode"
   exit 1
fi
echo "incarnation after new controlfile"
$rmanlogin log $incarnation << EOF
list incarnation of database;
exit;
EOF

incar_num1=`grep -i $dbname  $incarnation | grep -i CURRENT | awk '{print $2}'`
echo "Oracle database incarnation is $incar_num1"

grep -i error $controlfile_rmanlog
  
if [ $? -eq 0 ]; then
   echo "Controlfile restore failed"
   exit 1
fi

}

function restore_database_validate {

echo "Database restore validate started at " `/bin/date '+%Y%m%d%H%M%S'`
echo "ORACLE SID is $oraclesid"

if [[ -z $catalogc ]]; then
    rman log $restore_rmanlog << EOF
    connect target '${targetc}'
    @$restore_rmanfile
EOF
else
    rman log $restore_rmanlog << EOF
    connect target '${targetc}'
    connect catalog '${catalogc}'
    @$restore_rmanfile
EOF
fi


if [ $? -ne 0 ]; then
    echo "   "
    echo "Database restore validate failed at " `/bin/date '+%Y%m%d%H%M%S'`
    ls -l ${ORACLE_HOME}/dbs/spfile*
	echo "The last 10 line of rman log output"
    echo " "
    echo "rmanlog file is $restore_rmanlog"
    tail $restore_rmanlog
    exit 1
else
    echo "  "
    echo "Database restore validate finished at " `/bin/date '+%Y%m%d%H%M%S'`
fi

}

function restore_database {

echo "Database restore started at " `/bin/date '+%Y%m%d%H%M%S'`
echo "ORACLE SID is $oraclesid"
if [[ -f $stdout ]]; then
   rm $stdout
fi
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

if [[ $open_mode != "MOUNTED" ]]; then
   echo "Oracle database $oraclesid is not in mount open mode"
   echo "start the database in mount mode"
   $sqllogin << EOF
   shutdown immediate;
   startup mount;
EOF
  if [[ -z $catalogc ]]; then
      rman log $restore_rmanlog << EOF
      connect target '${targetc}'
      @$restore_rmanfile
EOF
      rman log $recover_rmanlog << EOF
      connect target '${targetc}'
      @${recover_rmanfile}
EOF
   else
      rman log $restore_rmanlog << EOF
      connect target '${targetc}'
      connect catalog '${catalogc}'
      @$restore_rmanfile
EOF
      rman log $recover_rmanlog << EOF
      connect target '${targetc}'
      connect catalog '${catalogc}'
      @${recover_rmanfile}
EOF
   fi


   if [ $? -ne 0 ]; then
     echo "   "
     echo "Database restore failed at " `/bin/date '+%Y%m%d%H%M%S'`
     ls -l ${ORACLE_HOME}/dbs/spfile*
     echo "The last 10 line of rman log output"
     echo " "
     echo "rmanlog file is $restore_rmanlog"
     tail $restore_rmanlog
     exit 1
   else
     echo "  "
     echo "Database restore finished at " `/bin/date '+%Y%m%d%H%M%S'`
   fi
else
   echo "Oracle database $oraclesid is in mount open mode"
   if [[ $force = [Yy]* ]]; then
     if [[ $full != [Yy]* ]]; then
       read -p "The restore will overwrite the database $dbname. Type YES or yes to confirm or any other keys to cancel: " answer3
     else
       answer3=yes
     fi
   else
      answer3=yes
   fi

   if [[ $answer3 = [Yy]* ]]; then
      if [[ -z $catalogc ]]; then
        rman log $restore_rmanlog << EOF
        connect target '${targetc}'
        @$restore_rmanfile
EOF
        rman log $recover_rmanlog << EOF
        connect target '${targetc}'
        @${recover_rmanfile}
EOF
      else
        rman log $restore_rmanlog << EOF
        connect target '${targetc}'
        connect catalog '${catalogc}'
        @$restore_rmanfile
EOF
        rman log $recover_rmanlog << EOF
        connect target '${targetc}'
        connect catalog '${catalogc}'
        @${recover_rmanfile}
EOF
      fi

      if [ $? -ne 0 ]; then
        echo "   "
        echo "Database restore failed at " `/bin/date '+%Y%m%d%H%M%S'`
        ls -l ${ORACLE_HOME}/dbs/spfile*
        echo "The last 10 line of rman log output"
        echo " "
        echo "rmanlog file is $restore_rmanlog"
        tail $restore_rmanlog
        tail $recover_rmanlog
        exit 1
      else
        echo "  "
        echo "Database restore finished at " `/bin/date '+%Y%m%d%H%M%S'`
      fi
   else
      echo "restore will not start at this point"
      exit 1
   fi
fi
}

function check_fra_empty {

#check whether FRA is empty or not if FRA uses file directory, not ASM"
echo "chec whether FRA is empty or not if FRA uses file directory, not ASM"
if [[ -f $stdout ]]; then
   rm $stdout
fi
$sqllogin << EOF > /dev/null
   spool $stdout replace
   select name from v\$recovery_file_dest;
EOF

i=0
while IFS= read -r line
do
  if [[ $i -eq 1 ]]; then
     fra=`echo $line | xargs`
     i=$[$i+1]
  fi
  if [[ $line =~ "-" ]];then
     i=$[$i+1]
  fi
done < $stdout

echo FRA area is $fra

if [[ ${fra:0:1} != "+" ]]; then
   echo "The recovery area $fra is a directory"
   dirsize=`du -sh $fra | awk '{print $1}'`

   if [[ $dirsize != 0 ]]; then 
      read -p "The recovery area $fra is empty. Please clean the directory, then Type YES or yes to continue: " answer4
   
      if [[ $answer4 != [Yy]* ]]; then
         echo "stop the restore"
	     exit 1
      fi
   fi
fi
 
}


setup

if [[ $preview = "yes" || $preview = "Yes" || $preview = "YES" ]]; then
   if [[ $full = [Yy]* ]]; then
      if [[ -n $catalogc ]]; then
         create_rman_restore_controlfile_catalog
      else
         create_rman_restore_controlfile_nocatalog
      fi
      echo "   "
      echo ORACLE spfile restore RMAN SCRIPT 
      echo " "
      echo "---------------"
      cat $spfile_rmanfile
      echo " "
      echo ORACLE controlfile restore RMAN SCRIPT 
      echo "---------------"
      cat $controlfile_rmanfile
      echo "---------------"	  
   fi
   create_rman_restore_database_file
   echo "   "
   echo ORACLE restore RMAN SCRIPT 
   echo " "
   echo "---------------"
   cat $restore_rmanfile
   echo "---------------"
   create_rman_recover_database_file
   echo "   "
   echo ORACLE restore RMAN SCRIPT 
   echo " "
   echo "---------------"
   cat $recover_rmanfile
   echo "---------------"
   exit
fi

if [[ $force != [Yy]* ]]; then
   create_rman_restore_database_file
   echo "run rman restore validate. It will NOT overwrite currect database" 
   echo " "
   restore_database_validate
   echo "restore validate time is in rman log " $restore_rmanlog
   echo "check the start time and Finished restore time"
   exit
fi

if [[ $full = [Yy]* ]]; then
   echo "The following procedure will restore spfile, controlfiles, and datafiles"
   check_create_oracle_init_file
   if [[ $host == $shost ]]; then
      read -p "The database $dbname will be overwritten. Type YES or yes to confirm or any other keys to cancel: " answer2
      if [[ $answer2 = [Yy]* ]]; then
         if [[ -n $catalogc ]]; then
            create_rman_restore_controlfile_catalog
         else
            create_rman_restore_controlfile_nocatalog
         fi
         restore_controlfile      
      else
         echo "Restore database $dbname isn't executed."
         exit 0
      fi
   else
      echo "The database $dbname will be overwritten." 
      if [[ -n $catalogc ]]; then
          create_rman_restore_controlfile_catalog
      else
          create_rman_restore_controlfile_nocatalog
      fi
      restore_controlfile
   fi
   check_fra_empty
fi
create_rman_restore_database_file
create_rman_recover_database_file
restore_database
echo "restore time is in rman log " $restore_rmanlog " and " $recover_rmanlog
echo "check the start and finish time in the logs"

