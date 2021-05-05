#!/bin/bash
#
# Name:         duplicate-ora-coh-sbt.bash
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
# 01/18/21 Diana Yang   Add option to cancel the job
# 04/29/21 Diana Yang   Change syntax to use new sbt library
# 05/03/21 Diana Yang   Add refresh option
#
#################################################################

function show_usage {
echo "usage: duplicate-ora-coh-sbt.bash -r <Target connection> -e <Catalog connection> -b <backup host> -a <target host> -d <Source Oracle_DB_Name> -t <Target Oracle instance name> -y <Cohesity-cluster> -l <file contain duplicate settting>  -j <vip file> -v <view> -s <sbt file name> -p <number of channels> -o <ORACLE_HOME> -c <source PDB> -f <yes/no> -w <yes/no>" 
echo " "
echo " Required Parameters"
echo " -r : Target connection (example: \"<dbuser>/<dbpass>@<target db connection>\")"
echo " -b : backup host"
echo " -d : Source Oracle_DB_Name, If Source is not a RAC database, it is the same as Instance name. If it is RAC, it is DB name, not instance name"
echo " -t : Target Oracle instance name. If it is not RAC, it is the same as DB name. If it is RAC, it is the instance name like cohcdba2"
echo " -y : Cohesity Cluster DNS name"
echo " -l : File contains duplicate setting, example: set newname for database to '/oradata/restore/orcl/%b'; optional if on a alternate server"
echo " -v : Cohesity view"
echo " "
echo " Optional Parameters"
echo " -e : Catalog connection (example: \"<dbuser>/<dbpass>@<catalog connection string>\", optional)"
echo " -a : target host (Optional, default is localhost)"
echo " -i : File contains new setting to spfile. example: SET DB_CREATE_FILE_DEST +DGROUP3"
echo " -p : number of channels (default is 4), optional"
echo " -j : The file lists Cohesity Cluster VIPs (default name is vip-list and default directory is config)"
echo " -s : Cohesity SBT library name including directoy or just directory (default name is libsbt_6_and_7_linux-x86_64.so, default directory is lib) "
echo " -o : ORACLE_HOME (default is current environment), optional"
echo " -c : Source pluggable database (if this input is empty, it is standardalone or CDB database restore)"
echo " -f : yes means force. It will refresh the target database without prompt"
echo " -w : yes means preview rman duplicate scripts"
}

while getopts ":r:e:b:a:d:t:y:l:i:j:v:s:p:o:c:f:w:" opt; do
  case $opt in
    r ) targetc=$OPTARG;;
    e ) catalogc=$OPTARG;;
    b ) shost=$OPTARG;;
    a ) thost=$OPTARG;;
    d ) sdbname=$OPTARG;;
    t ) toraclesid=$OPTARG;;
    l ) ora_pfile=$OPTARG;;
    i ) ora_spfile=$OPTARG;;
    y ) cohesityname=$OPTARG;;
    j ) vipfile=$OPTARG;;
    v ) view=$OPTARG;;
    s ) sbtname=$OPTARG;;
    p ) parallel=$OPTARG;;
    o ) oracle_home=$OPTARG;;
    c ) spdbname=$OPTARG;;
    f ) force=$OPTARG;;
    w ) preview=$OPTARG;;
  esac
done

#echo $shost, $sdbname, $toraclesid, $view, $vipfile
echo "  "

# Check required parameters
#if test $shost && test $sdbname && test $toraclesid && test $tdbdir && test $mount && test $num
#if test $rmanlogin && test $shost && test $sdbname && test $toraclesid && test $view && test $vipfile
if test $shost && test $sdbname && test $toraclesid && test $view
then
  :
else
  show_usage 
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

if [[ -z $targetc && -z $catalogc ]]; then
   echo "Need to provide target database connection string or recover catalog connection string"
   exit 1
fi

if [[ -n $targetc ]]; then
   echo "Will use target conection to duplicate the database"
   catalogc=""
fi

sqllogin="sqlplus / as sysdba"

if test $oracle_home; then
#  echo *auxiliary*
  echo "ORACLE_HOME is $oracle_home"
  ORACLE_HOME=$oracle_home
  export ORACLE_HOME=$oracle_home
  export PATH=$PATH:$ORACLE_HOME/bin
else
  oracle_home=`env | grep ORACLE_HOME | awk -F "=" '{print $2}'`
  if [[ -z $oracle_home ]]; then
     echo " is not defined. Need to specify ORACLE_HOME"
     exit 1
  fi   
fi
export NLS_DATE_FORMAT='DD:MM:YYYY-HH24:MI:SS'
dbpfile=${ORACLE_HOME}/dbs/init${toraclesid}.ora
dbspfile=${ORACLE_HOME}/dbs/spfile${toraclesid}.ora

if [[ $shost = $thost ]]; then
   echo $shost is the same as $thost
   echo ora_pfile is ${ora_pfile}
   if [[ -z `grep -i DB_CREATE_ONLINE_LOG_DEST_ $dbpfile` ]]; then
      if [[ -z ${ora_pfile} || -z `grep -i db_create_file_dest $dbpfile` ]]; then
       	 echo "db_create_file_dest and DB_CREATE_ONLINE_LOG_DEST_n are not defined in init file $dbpfile"
	 echo "and new database files location is not defined in a file which is defined by -f option, example as the following"
	 echo "set newname for database to '+DATAR';"
	 echo "There may be convert option in the init file. It is still okay to continue if you are certain the init file is correct"
		
	 read -p "Continue may overwrite the target database files. Do you want to continue? " answer1
	 if [[ $answer1 = [Nn]* ]]; then
	   exit 1
	 fi
      else
	 if [[ -z ${ora_pfile} && -n `grep -i db_create_file_dest $dbpfile` ]]; then
	   db_create_location=`grep -i db_create_file_dest $dbpfile | awk -F "'" '{print $2}' | awk -F "%" '{print $1}'`
	   if [[ ${db_create_location:0:1} != "+" ]]; then
	      echo "DB_CREATE_ONLINE_LOG_DEST_n is not defined in init file $dbpfile"
              read -p "Continue may overwrite the target database files. Do you want to continue? " answer1
	      if [[ $answer1 = [Nn]* ]]; then
	         exit 1
	      fi
	   fi
	 fi
	 if [[ -n ${ora_pfile} && -z `grep -i db_create_file_dest $dbpfile` ]]; then
	   db_location=`grep -i newname $ora_pfile | grep -v "#" | awk -F "'" '{print $2}' | awk -F "%" '{print $1}'`
	   if [[ ${db_location:0:1} != "+" ]]; then
	      echo "DB_CREATE_ONLINE_LOG_DEST_n is not defined in init file $dbpfile"
              read -p "Continue may overwrite the target database files. Do you want to continue? " answer1
	      if [[ $answer1 = [Nn]* ]]; then
	         exit 1
	      fi
	   fi
        fi
      fi
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
  nslookup $cohesityname | grep -i address | tail -n +2 | awk '{print $2}' > $vipfiletemp
  
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
      sbtname=${sbtname}/libsbt_linux-x86_64.so
      if test ! -f $sbtname; then
         sbtname=${sbtname}/libsbt_6_and_7_linux-x86_64.so
      fi  
   fi
else
   echo "we assume the sbt library is in $DIR/lib"
   sbtname=${DIR}/lib/libsbt_linux-x86_64.so
   if test ! -f $sbtname; then
      sbtname=${DIR}/lib/libsbt_6_and_7_linux-x86_64.so
   fi
fi

if test -f $sbtname; then
   echo "file $sbtname exists, script continue"
else
   echo "file $sbtname does not exist. exit"
   exit 1
fi

drmanlog=$DIR/log/$thost/$toraclesid.rman-duplicate.$DATE_SUFFIX.log
drmanfiled=$DIR/log/$thost/$toraclesid.rman-duplicate.$DATE_SUFFIX.rcv

#trim log directory
find $DIR/log/$thost -type f -mtime +7 -exec /bin/rm {} \;

if [ $? -ne 0 ]; then
  echo "del old logs in $DIR/log/$thost failed"
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

function duplicate_prepare {

if [[ -z $dbpfile ]]; then
   echo "there is no dbpfile"
   exit 1
fi

# get adump directory from dbpfile and create it if the directory doesn't exist
adump_directory=`grep -i audit_file_dest $dbpfile | awk -F "'" '{print $2}' | awk -F "%" '{print $1}'`
# remove all space in $adump_directory variable
adump_directory=`echo $adump_directory | xargs`
echo "check adump directory. Creat it if it does not exist"
if [[ ! -d ${adump_directory} ]]; then
   echo "${adump_directory} does not exist, create it"
   mkdir -p ${adump_directory}

   if [ $? -ne 0 ]; then
      echo "create new directory ${adump_directory} failed"
      exit 1
   fi
fi

# check db_create_file_dest location and create it if it is a directory and it doesn't exist
db_create_location=`grep -i db_create_file_dest $dbpfile | awk -F "'" '{print $2}' | awk -F "%" '{print $1}'`
if [[ -n $db_create_location ]]; then
   echo db_create_location is $db_create_location
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
if [[ -z $spdbname ]]; then
  if [[ ! -z $ora_pfile ]]; then
    echo "ora_pfile is $ora_pfile"
    db_location=`grep -i newname $ora_pfile | grep -v "#" | awk -F "'" '{print $2}' | awk -F "%" '{print $1}'`
    arrdbloc=($db_location)
    lendbloc=${#arrdbloc[@]}
	
    for (( i=0; i<$lendbloc; i++ )); do
# check whether the directory is empty or the file exist or not
       if [[ -d ${arrdbloc[$i]} ]]; then
          lsout1=`ls -al ${arrdbloc[$i]} | grep '^-'`
          if [[ -n $lsout1 ]]; then 
             echo "The directory ${arrdbloc[$i]} has files. exit"
             exit 1
          fi
       fi

       if [[ -f  ${arrdbloc[$i]} ]]; then
          echo "file ${arrdbloc[$i]} exist. exit"
          exit 1
       fi
		  
# get the directory
       newdbdir=`echo ${arrdbloc[$i]} | awk 'BEGIN{FS=OFS="/"}{NF--; print}'`
       echo $newdbdir
# check whether it is ASM or dirctory
       if [[ ${newdbdir:0:1} != "+" ]]; then
          if [[ ! -d ${newdbdir} ]]; then
             echo "Directory ${newdbdir} does not exist, create it"
	     mkdir -p ${newdbdir}
	  fi
  
          if [ $? -ne 0 ]; then
             echo "create new directory ${newdbdir} failed"
             exit 1
          fi
       fi
    done 
  else
    echo "there is no ora_pfile"
  fi
fi

# test whether duplicate database is open or not. 
# If it is open, needs to shutdown it down and start the duplicate database in nomount mode
# If it is not open, start the duplicate database in nomount mode
runoid=`ps -ef | grep pmon | awk 'NF>1{print $NF}' | grep -i $toraclesid | awk -F "_" '{print $3}'`

if [[ ${runoid} != ${toraclesid} ]]; then
   echo "Oracle database $toraclesid is not up"
   echo "start the database in nomount mode"
   rman target / << EOF
   startup nomount;
EOF
else
   if [[ $force = [Yy]* ]]; then
      echo "Oracle database is up. Will shut it down and start in nomount mode"
      echo "The duplicated database will be refreshed with new data"
      $sqllogin << EOF
      shutdown immediate;
      startup nomount
EOF
   else
      read -p "Oracle database is up, Should this database be refreshed with new data? " answer2
      if [[ $answer2 = [Nn]* ]]; then
         exit 1		 
      else
         $sqllogin << EOF
         shutdown immediate;
         startup nomount
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
             allocate_database[$j]="allocate auxiliary CHANNEL c$j TYPE 'SBT_TAPE' PARMS 'SBT_LIBRARY=$sbtname,SBT_PARMS=(mount_path=$ip:/$view,vips=$ip,gflag_name=use_fixed_dedup_chunking,gflag_value=true)';"
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
if [[ ! -z $ora_pfile ]]; then
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

if [[ ! -z $ora_spfile ]]; then
  if test -f $ora_spfile; then
    if [[ -z $spdbname ]]; then
       echo "duplicate database $sdbname to $toraclesid" >> $drmanfiled
    else
       echo "duplicate database $sdbname to $toraclesid pluggable database $spdbname" >> $drmanfiled
    fi
    grep -v "^#" < $ora_spfile | { while IFS= read -r spara; do
       para=`echo $spara | xargs`
       echo $spara >> $drmanfiled
    done }
#    echo "nofilenamecheck;" >> $drmanfiled
  else
     echo "$ora_spfile does not exist"
     exit 1
  fi
else
  if [[ -z $spdbname ]]; then
     echo "duplicate database $sdbname to $toraclesid nofilenamecheck;" >> $drmanfiled
  else
     echo "duplicate database $sdbname to $toraclesid pluggable database $spdbname nofilenamecheck;" >> $drmanfiled
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

if [[ -n targetc ]]; then
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

if [ $? -ne 0 ]; then
  echo "Database duplicatep failed at " `/bin/date '+%Y%m%d%H%M%S'`
  echo "If Oracle duplicate job fails, Check whether Oracle database $toraclesid started in nomount mode"
  echo "If Oracle duplicate job fails and it is PDB restore, Check whether Oracle database $toraclesid is started"
  echo "We have seen that Oracle reports failure, but the duplication is actually successful."
  ls -l ${oracle_home}/dbs/spfile*
  echo "The last 10 line of rman log output"
  echo " "
  echo "rmanlog file is $drmanlog"
  tail $drmanlog 
  exit 1
else
  echo "Database duplicate finished at " `/bin/date '+%Y%m%d%H%M%S'`
fi

}

setup
if [[ $preview != [Yy]* ]]; then
   echo prepare duplication
   echo " "
   duplicate_prepare
fi
create_rman_duplicate_file
if [[ $preview = "yes" || $preview = "Yes" || $preview = "YES" ]]; then
   echo ORACLE DATABASE DUPLICATE SCRIPT
   echo " "
   cat $drmanfiled
else
   duplicate
fi
