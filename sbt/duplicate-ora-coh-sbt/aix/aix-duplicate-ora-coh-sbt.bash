#!/bin/bash
#
# Name:         aix-duplicate-ora-coh-sbt.bash
#
# Function:     This script duplicate Oracle database from Oracle backup 
#               using backup-ora-coh-sbt.bash. This script needs recovery database or 
#				source database to run duplication since this backup uses sbt
#
#
# Show Usage: run the command to show the usage
#
# Changes:
# 08/07/20 Diana Yang   New script (duplicate using target database)
# 08/21/20 Diana Yang   Add more conditions
# 10/30/20 Diana Yang   Standardlize name. Remove "-f" and "-s" as required parameter
# 11/11/20 Diana Yang   Remove the need to manually create vip-list file
# 05/03/21 Diana Yang   Add refresh option
# 04/07/22 Diana Yang   Change the input plugin to be consistent with restore script. Major syntax changes.
# 01/29/22 Diana Yang   Change awk to /opt/freeware/bin/gawk
# 03/29/22 Diana Yang   Change sbtname to libsbt_aix_powerpc.so
# 04/04/22 Diana Yang   Check init file before duplication
# 04/27/22 Diana Yang   Add noresume option 
#
#################################################################

function show_usage {
echo "usage: aix-duplicate-ora-coh-sbt.bash -r <Source ORACLE connection> -h <backup host> -c <Catalog ORACLE connection> -i <Target Oracle_DB_Name> -d <Source Oracle database> -y <Cohesity-cluster> -b <file contain restore settting> -t <point-in-time> -e <sequence> -j <vip file> -v <view> -s <sbt file name> -p <number of channels> -o <ORACLE_HOME> -u <source PDB> -f <yes/no> -m <noresume> -w <yes/no> -g <yes/no> -k <cert path>" 
echo " "
echo " Required Parameters"
echo " -i : Target Oracle instance name (Oracle duplicate database)" 
echo " -r : Source Oracle connection (example: \"<dbuser>/<dbpass>@<target db connection>\")"
echo " -h : Source host - Oracle database host that the backup was run." 
echo " -d : Source Oracle_DB_Name (database backup was taken). It is DB name, not instance name if it is RAC or DataGuard"
echo " -t : Point in Time (format example: \"2019-01-27 13:00:00\")"
echo " -y : Cohesity Cluster DNS name"
echo " -v : Cohesity view"
echo " "
echo " Optional Parameters"
echo " -e : Log sequence number. Either point-in-time or log sequence number. Can't be both."
echo " -c : Catalog connection (example: \"<dbuser>/<dbpass>@<catalog connection string>\", optional)"
echo " -b : File contains restore location setting, example: set newname for database to '/oradata/restore/orcl/%b'; "
echo " -p : number of channels (default is 4), optional"
echo " -j : The file lists Cohesity Cluster VIPs (default name is vip-list and default directory is config)"
echo " -s : Cohesity SBT library name including directoy or just directory (default name is libsbt_6_and_7_linux-x86_64.so, default directory is lib) "
echo " -o : ORACLE_HOME (default is current environment), optional"
echo " -u : Source pluggable database (if this input is empty, it is standardalone or CDB database restore)"
echo " -f : yes means force. It will refresh the target database without prompt"
echo " -g : yes means encryption-in-flight is used. The default is no"
echo " -k : encryption certificate file directory, default directory is lib"
echo " -w : yes means preview rman duplicate scripts"
}

while getopts ":r:c:h:d:i:y:b:t:e:j:v:s:p:o:u:f:m:g:k:w:" opt; do
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
    s ) sbtname=$OPTARG;;
    p ) parallel=$OPTARG;;
    o ) oracle_home=$OPTARG;;
    u ) pdbname=$OPTARG;;
    f ) force=$OPTARG;;
    m ) noresume=$OPTARG;;
    g ) encryption=$OPTARG;;
    k ) encrydir=$OPTARG;;
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
      echo " \ shouldn't be part of input. Please remove \."
      exit 2 
   fi
done

#if test $shost && test $sdbname && test $toraclesid 
if test $shost && test $toraclesid && test $view
then
  :
else
  show_usage 
  exit 1
fi

if [[ -z $sdbname ]]; then
   echo "Please enter the Source Oracle_DB_Name (database backup was taken) after -d in syntax. It is DB name, not instance name if it is RAC or DataGuard"
   echo "In next version of the script, this name will be queried from the source database"
   exit 2
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

function setup {

if test $thost
then
  :
else
  thost=`hostname -s`
fi

if [[ $thost != $shost ]]; then
   if [[ -z $itime && -z $sequence ]]; then
     echo "A restore time or sequence number should be provided. It needs to be the time or sequence number before the last archive log backup"
     echo "In next version of the script, the sequence of the last archivelog backup will be used if no number is provided"
     exit 2
   fi
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

for (( i=0; i<$lencommand; i++ ))
do
   if [[ ${fullcommand[$i]} == -e ]]; then
      sequenceset=yes
   fi
done
if [[ -n $sequenceset ]]; then
   if [[ -z $sequence ]]; then
      echo "Please enter a sequence number as the argument for -e. It may be empty or not all options are given an argument. All options should be given an arguments"
      exit 2
   else
      if [[ $sequence =~ ^[0-9]+$ ]]; then
         echo "sequence is $sequence "
      else
         echo "The the argument for -e should be a digit"
	 exit 2
      fi
   fi 
fi

if [[ -n $itime && -n $sequence ]]; then
   echo "Either time or sequence be entered. This script does not take both argements"
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
      echo "Please enter yes or no as the argument for -m. It may be empty or not all options are given an argument. All options should be given an arguments"
      exit 2
   else
      if [[ $noresume != [Yy]* && $noresume != [Nn]* ]]; then
         echo "'yes' or 'no' should be provided after -m in syntax, other answer is not valid"
	 exit 2
      fi
   fi 
fi

if [[ -z $targetc && -z $catalogc ]]; then
   echo "Need to provide target database connection string or recover catalog connection string"
   exit 1
fi

if [[ -n $targetc ]]; then
   echo "Will use target conection to duplicate the database"
   catalogc=""
#getting sqlplus login
   cred=`echo $targetc | /opt/freeware/bin/gawk -F @ '{print $1}'`
   conn=`echo $targetc | /opt/freeware/bin/gawk -F @ '{print $2}' | /opt/freeware/bin/gawk '{print $1}'`
   sysbackupy=`echo $targetc | /opt/freeware/bin/gawk -F @ '{print $2}' | /opt/freeware/bin/gawk 'NF>1{print $NF}'`
   if [[ -z $sysbackupy ]]; then
      ssqllogin="sqlplus ${cred}@${conn} as sysdba"
   else
      ssqllogin="sqlplus ${cred}@${conn} as sysbackup"
   fi
fi

sqllogin="sqlplus / as sysdba"

if test $oracle_home; then
#  echo *auxiliary*
  echo "ORACLE_HOME is $oracle_home"
  ORACLE_HOME=$oracle_home
  export ORACLE_HOME=$oracle_home
  export PATH=$PATH:$ORACLE_HOME/bin
else
  oracle_home=`env | grep ORACLE_HOME | /opt/freeware/bin/gawk -F "=" '{print $2}'`
  if [[ -z $oracle_home ]]; then
     echo " is not defined. Need to specify ORACLE_HOME"
     exit 1
  fi   
fi
export NLS_DATE_FORMAT='DD:MM:YYYY-HH24:MI:SS'
dbpfile=${ORACLE_HOME}/dbs/init${toraclesid}.ora
dbspfile=${ORACLE_HOME}/dbs/spfile${toraclesid}.ora


if [[ -n $ora_pfile ]]; then
   if [[ ! -f $ora_pfile ]]; then
      echo "there is no $ora_pfile. It is file defined by -l plugin"
      exit 1
   fi
fi

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

if [[ ! -d $DIR/log/$thost ]]; then
  echo " $DIR/log/$thost does not exist, create it"
  mkdir -p $DIR/log/$thost
  
  if [ $? -ne 0 ]; then
    echo "create log directory $DIR/log/$thost failed. There is a permission issue"
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
  vipfiletemp=${DIR}/config/${toraclesid}-vip-list-temp
  vipfile=${DIR}/config/${toraclesid}-vip-list
  echo "Cohesity Cluster name is $cohesityname. VIPS will be collected and stored in $vipfile"
  nslookup $cohesityname | grep -i address | tail -n +2 | /opt/freeware/bin/gawk '{print $2}' > $vipfiletemp
  
  if [[ ! -s $vipfiletemp ]]; then
     echo "Cohesity Cluster name $cohesityname provided here is not in DNS"
     exit 1
  fi

  shuf $vipfiletemp > $vipfile
fi

if [[ -n $sbtname ]]; then
   if [[ $sbtname == *".so" ]]; then
      echo "we will use the sbt library provided $sbtname"
   else  
      echo "This may be a directory"
      sbtname=${sbtname}/libsbt_aix_powerpc.so
   fi
else
    echo "we assume the sbt library is in $DIR/lib"
    sbtname=${DIR}/lib/libsbt_aix_powerpc.so
fi

#check whether sbt library is in $DIR/lib
if [ ! -f $sbtname ]; then
   echo "The sbt library is not in $DIR/lib, Let's check the directory /opt/cohesity/plugins/sbt/lib"
#check whether sbt library is in /opt/cohesity/plugins/sbt/lib
   sbtname=/opt/cohesity/plugins/sbt/lib/libsbt_aix_powerpc.so
   if [ ! -f $sbtname ]; then
      echo "file $sbtname does not exist. exit"
      exit 1
   else
      echo "The sbt library is $sbtname"
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

stdout=$DIR/log/$host/$toraclesid.$DATE_SUFFIX.std
drmanlog=$DIR/log/$thost/$toraclesid.rman-duplicate.$DATE_SUFFIX.log
drmanfiled=$DIR/log/$thost/$toraclesid.rman-duplicate.$DATE_SUFFIX.rcv

#trim log directory
#find $DIR/log/$thost -type f -mtime +7 -exec /bin/rm {} \;

#if [ $? -ne 0 ]; then
#  echo "del old logs in $DIR/log/$thost failed"
#  exit 2
#fi

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

# test whether backup files exist
backupdir=`$DIR/tools/sbt_list --view=$view/$shost --vips=$ip | grep ${sdbname}`
if [[ -z ${backupdir} ]]; then
   echo "The directory ${shost}/${sdbname} doesn't exist in view ${view} of this Cohesity Cluster. Please check the input"
   exit 2
fi

export ORACLE_SID=$toraclesid

# test target connection
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
      echo "
           targetc syntax can be like \"/\" or
          \"sys/<password>@<target database connect string>\""
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
      echo "
           catalogc syntax can be like \"/\" or
          \"<catalog dd user>/<password>@<catalog database connect string>\""
      exit 1
   else
      echo "rman catalog connect is successful. Continue"
   fi
fi

}

function check_create_oracle_init_file {

dbpfile=${ORACLE_HOME}/dbs/init${toraclesid}.ora
dbspfile=${ORACLE_HOME}/dbs/spfile${toraclesid}.ora

if [[ ! -f ${dbpfile} ]]; then
    echo "The oracle pfile $ORACLE_HOME/dbs/init${toraclesid}.ora doesn't exist. Please check the instance name or create the pfile first."
    exit 2
fi

}

function duplicate_prepare {

#check pfile 
if [[ $force != [Yy]* ]]; then
   if [[ $shost = $thost ]]; then
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
            db_create_location=`grep -i db_create_file_dest $dbpfile | /opt/freeware/bin/gawk -F "'" '{print $2}' | /opt/freeware/bin/gawk -F "%" '{print $1}'`
         fi
      fi
      if [[ -n ${ora_pfile} ]]; then
         db_location=`grep -i newname $ora_pfile | grep -v "#" | /opt/freeware/bin/gawk -F "'" '{print $2}' | /opt/freeware/bin/gawk -F "%" '{print $1}'`
      fi
   fi
fi

# get adump directory from dbpfile and create it if the directory doesn't exist
adump_directory=`grep -i audit_file_dest $dbpfile | /opt/freeware/bin/gawk -F "'" '{print $2}' | /opt/freeware/bin/gawk -F "%" '{print $1}'`
# remove all space in $adump_directory variable
adump_directory=`echo $adump_directory | xargs`
if [[ -n ${adump_directory} ]]; then
   echo "check adump directory. Create it if it does not exist"
   if [[ ! -d ${adump_directory} ]]; then
      echo "${adump_directory} does not exist, create it"
      mkdir -p ${adump_directory}

      if [ $? -ne 0 ]; then
         echo "create new directory ${adump_directory} failed"
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
            echo "create new directory ${db_create_location} failed"
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
    db_location=`grep -i newname $ora_pfile | grep -v "#" | /opt/freeware/bin/gawk -F "'" '{print $2}' | /opt/freeware/bin/gawk -F "%" '{print $1}'`
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
       newdbdir=`echo ${arrdbloc[$i]} | /opt/freeware/bin/gawk 'BEGIN{FS=OFS="/"}{NF--; print}'`
       echo $newdbdir
# check whether it is ASM or dirctory
       if [[ ${newdbdir:0:1} != "+" ]]; then
          if [[ ! -d ${newdbdir} ]]; then
             echo "Directory ${newdbdir} does not exist, create it"
	     mkdir -pv ${newdbdir}
	  fi
  
          if [ $? -ne 0 ]; then
             echo "create new directory ${newdbdir} failed"
             exit 1
          fi
       fi
    done 
  fi
fi

# test whether duplicate database is open or not. 
# If it is open, needs to shutdown it down and start the duplicate database in nomount mode
# If it is not open, start the duplicate database in nomount mode
runoid=`ps -ef | grep pmon | /opt/freeware/bin/gawk 'NF>1{print $NF}' | grep -i $toraclesid | /opt/freeware/bin/gawk -F "pmon_" '{print $2}'`

if [[ ${runoid} != ${toraclesid} ]]; then
   echo "Oracle database $toraclesid is not up"
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
      read -p "Oracle database is up, Should this database be refreshed with new data? " answer2
      if [[ $answer2 = [Nn]* ]]; then
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
                  allocate_database[$j]="allocate auxiliary CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,gflag_name=use_fixed_dedup_chunking,gflag_value=true,sbt_certificate_file=${encrycert})';"
               else
		  allocate_database[$j]="allocate auxiliary CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,gflag_name=use_fixed_dedup_chunking,gflag_value=true,gflag-name=sbt_use_grpc,gflag-value=false,sbt_certificate_file=${encrycert})';"
	       fi
	    else
	       if [[ $grpctype = [Yy]* ]]; then
                  allocate_database[$j]="allocate auxiliary CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,gflag_name=use_fixed_dedup_chunking,gflag_value=true)';"
               else
                  allocate_database[$j]="allocate auxiliary CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,gflag_name=use_fixed_dedup_chunking,gflag_value=true,gflag-name=sbt_use_grpc,gflag-value=false)';"
               fi
            fi			   
   	    unallocate[$j]="release channel c$j;"
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
    echo "$ora_pfile does not exist"
    exit 1
  fi
fi

if [[ -n $itime ]]; then
   echo "Oracle recovery point-in-time is define. Set duplicate time until $itime"
   echo "SET UNTIL TIME \"to_date('$itime', ''YYYY/MM/DD HH24:MI:SS')\";"
   echo "set until time \"to_date('$itime','YYYY/MM/DD HH24:MI:SS')\";" >> $drmanfiled
fi

if [[ -n $sequence ]]; then
echo "Oracle recovery point-in-time is define. Set recover time until $itime"
   echo "SET until sequence $sequence thread 1;"
   echo "set until sequence $sequence thread 1;" >> $drmanfiled
fi

if [[ -z $pdbname ]]; then
   if [[ $shost == $thost ]]; then
      if [[ $noresume = [Yy]* ]]; then
         echo "duplicate database '$sdbname' to '$toraclesid' noresume;" >> $drmanfiled
      else
         echo "duplicate database '$sdbname' to '$toraclesid';" >> $drmanfiled
      fi
   else
      if [[ $noresume = [Yy]* ]]; then
         echo "duplicate database '$sdbname' to '$toraclesid' noresume nofilenamecheck;" >> $drmanfiled
      else
         echo "duplicate database '$sdbname' to '$toraclesid' nofilenamecheck;" >> $drmanfiled
      fi
   fi
else
   if [[ $shost == $thost ]]; then
      if [[ $noresume = [Yy]* ]]; then
         echo "duplicate database '$sdbname' to '$toraclesid' pluggable database '$pdbname' noresume;" >> $drmanfiled
      else 
         echo "duplicate database '$sdbname' to '$toraclesid' pluggable database '$pdbname';" >> $drmanfiled
      fi
   else
      if [[ $noresume = [Yy]* ]]; then
         echo "duplicate database '$sdbname' to '$toraclesid' pluggable database '$pdbname' noresume nofilenamecheck;" >> $drmanfiled
      else
         echo "duplicate database '$sdbname' to '$toraclesid' pluggable database '$pdbname' nofilenamecheck;" >> $drmanfiled
      fi
   fi
fi  

for (( i=0; i < ${#unallocate[@]}; i++ )); do
   echo ${unallocate[$i]} >> $drmanfiled
done

echo "
}
exit;
" >> $drmanfiled

echo "finished creating rman duplicate file"
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
     echo "Once the error is identified and corrected, you can rerun the duplicate command. 
Please make sure the auxiliary database is shutdown and the files associated with database $toraclesid removed before the rerun.
Please verify it is the auxiliary database by running the following the SQLPLUS command \"select name from v\$database;\" and \"select open_mode from v\$database;\"
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
      read -p "It is reommended to clean up the the files associated with database $toraclesid first. Please type yes if you want to continue this duplication? " answer3
      if [[ $answer3 != [Yy]* ]]; then
         exit
      fi
      duplicate_prepare
   fi
fi
create_rman_duplicate_file
if [[ $preview = [Yy]* ]]; then
   echo ORACLE DATABASE DUPLICATE SCRIPT
   echo " "
   cat $drmanfiled
else
   duplicate
fi
