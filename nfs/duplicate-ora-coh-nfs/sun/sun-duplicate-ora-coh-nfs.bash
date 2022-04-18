#!/bin/bash
#
# Name:         sun-duplicate-ora-coh-nfs.bash
#
# Function:     This script duplicate Oracle database from Oracle backup 
#               in nfs mount.
# Warning:      Restore can overwrite the existing database. This script needs to be used in caution.
#               The author accepts no liability for damages resulting from its use.
#
#
# Show Usage: run the command to show the usage
#
# Changes:
# 06/16/2020 Diana Yang   New script (duplicate using target database)
# 07/06/2020 Diana Yang   Add duplicate option from backup location
# 07/23/2020 Diana Yang   Add duplicate option from point in time backup location
# 05/03/2021 Diana Yang   Add refresh option
# 10/24/2021 Diana Yang   Add using target database to do duplication
# 10/25/2021 Diana Yang   Use gfind, gawk, and "hostname"
# 11/02/2021 Diana Yang   Use gdate
# 12/02/2021 Diana Yang   Use "nofilenamecheck" only on alternate server
# 04/15/2022 Diana Yang   Change the input plugin to be consistent with restore script. Major syntax changes 
#
#################################################################

function show_usage {
echo "usage: sun-duplicate-ora-coh-nfs.bash -r <Source ORACLE connection> -h <backup host> -c <Catalog ORACLE connection> -i <Target Oracle_DB_Name> -d <Source Oracle database> -b <file contain duplicate settting> -m <mount-prefix> -n <number of mounts> -t <point-in-time> -e <sequence> -p <number of channels> -o <ORACLE_HOME> -u <source PDB> -f <yes/no> -w <yes/no>" 
echo " "
echo " Required Parameters"
echo " -i : Target Oracle instance name (Oracle duplicate database)" 
echo " -r : Source Oracle connection (example: \"<dbuser>/<dbpass>@<target db connection>\")"
echo " -h : Source host - Oracle database host that the backup was run." 
echo " -d : Source Oracle_DB_Name (database backup was taken). It is DB name, not instance name if it is RAC or DataGuard"
echo " -t : Point in Time (format example: \"2019-01-27 13:00:00\")"
echo " -e : Sequence"
echo " -m : mount-prefix (like /coh/ora)"
echo " -n : number of mounts"
echo " "
echo " Optional Parameters"
echo " -c : Catalog connection (example: \"<dbuser>/<dbpass>@<catalog connection string>\", optional)"
echo " -b : File contains restore location setting, example: set newname for database to '/oradata/restore/orcl/%b'; "
echo " -p : number of channels (Optional, default is same as the number of mounts4)"
echo " -o : ORACLE_HOME (Optional, default is current environment)"
echo " -u : pluggable database (if this input is empty, it is standardalone or CDB database restore)"
echo " -f : yes means force. It will refresh the target database without prompt"
echo " -w : yes means preview rman duplicate scripts"
echo "
"
}

while getopts ":r:c:h:i:d:t:e:b:m:n:p:o:u:f:w:" opt; do
  case $opt in
    r ) targetc=$OPTARG;; 
    c ) catalogc=$OPTARG;;
    h ) shost=$OPTARG;;
    d ) sdbname=$OPTARG;;
    i ) toraclesid=$OPTARG;;
    b ) ora_pfile=$OPTARG;;
    t ) itime=$OPTARG;;
    e ) sequence=$OPTARG;;
    m ) mount=$OPTARG;;
    n ) num=$OPTARG;;
    p ) parallel=$OPTARG;;
    o ) oracle_home=$OPTARG;;
    u ) pdbname=$OPTARG;;
    f ) force=$OPTARG;;
    w ) preview=$OPTARG;;
  esac
done

#echo $rmanlogin $sdbname, $mount, $shost, $num

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

#if test $shost && test $sdbname && test $toraclesid && test $tdbdir && test $mount && test $num
if test $shost && test $toraclesid && test $mount && test $num
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
  thost=`hostname`
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
  echo "no input for parallel, set parallel to be $num."
  parallel=$num
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
elif [[ -z $itime ]]; then
   if [[ -z $targetc ]]; then
      echo "When point-in-time is not specified which is the argument for -t, Source Oracle connection is required. It is the argument for -r"
      exit 2
   fi 
fi

if [[ -z $targetc && -z $catalogc ]]; then
   echo "RMAN source database connection and recovery catalog connection are not provided. The RMAN duplicate command will use BACKUP LOCATION option"
fi

if [[ -n $targetc ]]; then
   echo "Will use target conection to duplicate the database"
   catalogc=""
#getting sqlplus login
   cred=`echo $targetc | gawk -F @ '{print $1}'`
   conn=`echo $targetc | gawk -F @ '{print $2}' | gawk '{print $1}'`
   sysbackupy=`echo $targetc | gawk -F @ '{print $2}' | gawk 'NF>1{print $NF}'`
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
  oracle_home=`env | grep ORACLE_HOME | gawk -F "=" '{print $2}'`
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
DIR=`echo $DIRcurrent |  gawk 'BEGIN{FS=OFS="/"}{NF--; print}'`
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

stdout=$DIR/log/$host/$toraclesid.$DATE_SUFFIX.std
drmanlog=$DIR/log/$thost/$toraclesid.rman-duplicate.$DATE_SUFFIX.log
drmanfiled=$DIR/log/$thost/$toraclesid.rman-duplicate.$DATE_SUFFIX.rcv


#trim log directory
#find $DIR/log/$thost -type f -mtime +7 -exec /bin/rm {} \;

#if [ $? -ne 0 ]; then
#  echo "del old logs in $DIR/log/$thost failed"
#  exit 2
#fi

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

if [[ ! -d "${mount}1/$shost/$sdbname/archivelog" ]]; then
   echo "Directory ${mount}1/$shost/$sdbname/archivelog does not exist, no backup files. Check the arguments for -m, -h and -d"
   exit 1
fi
	
#echo ${mount}1/$shost/$sdbname/archivelog

if [[ $force != [Yy]* ]]; then
   if [[ $shost = $thost ]]; then
      echo $shost is the same as $thost
#     echo ora_pfile is ${ora_pfile}
      if [[ -z `grep -i db_create_file_dest $dbpfile` && -z `grep -i db_file_name_convert $dbpfile` ]]; then
         echo "db_create_file_dest and db_file_name_convert are not defined in init file $dbpfile"
         echo " "
         read -p "Continue MAY overwrite the target database files. Do you want to continue? " answer1
         if [[ $answer1 = [Nn]* ]]; then
            exit 1
         fi
      else
         if [[ -n `grep -i db_create_file_dest $dbpfile` ]]; then
            db_create_location=`grep -i db_create_file_dest $dbpfile | gawk -F "'" '{print $2}' | gawk -F "%" '{print $1}'`
         fi
      fi
      if [[ -n ${ora_pfile} ]]; then
         db_location=`grep -i newname $ora_pfile | grep -v "#" | gawk -F "'" '{print $2}' | gawk -F "%" '{print $1}'`
      fi
      if [[ -z `grep -i DB_CREATE_ONLINE_LOG_DEST_ $dbpfile` ]]; then
         echo "DB_CREATE_ONLINE_LOG_DEST_n are not defined in init file $dbpfile"
         echo " "
         read -p "Continue may overwrite the target database files. Do you want to continue? " answer1
         if [[ $answer1 = [Nn]* ]]; then
            exit 1
         fi
      fi
   fi
fi


# get adump directory from dbpfile and create it if the directory doesn't exist
adump_directory=`grep -i audit_file_dest $dbpfile | gawk -F "'" '{print $2}' | gawk -F "%" '{print $1}'`
# remove all space in $adump_directory variable
adump_directory=`echo $adump_directory | xargs`
if [[ -n ${adump_directory} ]]; then
   echo "check adump directory. Creat it if it does not exist"
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
if [[ -z $spdbname ]]; then
  if [[ ! -z $ora_pfile ]]; then
    echo "ora_pfile is $ora_pfile"
    db_location=`grep -i newname $ora_pfile | grep -v "#" | gawk -F "'" '{print $2}' | gawk -F "%" '{print $1}'`
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
       newdbdir=`echo ${arrdbloc[$i]} | gawk 'BEGIN{FS=OFS="/"}{NF--; print}'`
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
  else
    echo "there is no ora_pfile"
  fi
fi

# test whether duplicate database is open or not. 
# If it is open, needs to shutdown it down and start the duplicate database in nomount mode
# If it is not open, start the duplicate database in nomount mode
runoid=`ps -ef | grep pmon | gawk 'NF>1{print $NF}' | grep -i $toraclesid | gawk -F "pmon_" '{print $2}'`

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

function create_softlink {

if [[ ! -d "${mount}1/$shost/$sdbname/archivelog" ]]; then
   echo "Directory ${mount}1/$shost/$sdbname/archivelog does not exist, no backup files. Check the arguments for -m, -h and -d"
   exit 1
fi

# setup backup location
echo "create link location if it does not exist"
backup_location=/tmp/orarestore/$thost/$toraclesid
echo backup_location is $backup_location
if [[ ! -d ${backup_location} ]]; then
   mkdir -vp ${backup_location}/controlfile
   mkdir -vp ${backup_location}/datafile
   mkdir -vp ${backup_location}/archivelog
else
   /bin/rm -r ${backup_location}/*
   mkdir -vp ${backup_location}/controlfile
   mkdir -vp ${backup_location}/datafile
   mkdir -vp ${backup_location}/archivelog
fi

# get itime from $ora_pfile file
# covert the time to numeric
if [[ -n $itime ]]; then
   if [[ -n $ora_pfile ]];then
      itime1=`grep to_date $ora_pfile | grep -v "#" |  gawk -F "'" '{print $2}'`
      echo "itime1 is $itime1"

      if [[ -n $itime1 ]]; then
	 echo "Point-in-time is specified in an argument for syntax -t.  \"to_date\" needs to be removed from file $ora_pfile"
	 exit 1
      fi
   else   
      ptime=`/bin/gdate -d "$itime" '+%Y%m%d%H%M%S'`
      echo "itime is $itime,  point-in-time restore time $ptime"
   fi
else
   if [[ -n $ora_pfile ]];then
      itime=`grep to_date $ora_pfile | grep -v "#" |  gawk -F "'" '{print $2}'`
      echo "itime is $itime"

      if [[ -z $itime ]]; then
         ptime=`/bin/gdate '+%Y%m%d%H%M%S'`
         echo "current time is `/bin/gdate`,  point-in-time restore time $ptime"  
      else   
         ptime=`/bin/gdate -d "$itime" '+%Y%m%d%H%M%S'`
         echo "itime is $itime,  point-in-time restore time $ptime"
      fi
   else
      ptime=`/bin/gdate '+%Y%m%d%H%M%S'`
      echo "current time is `/bin/gdate`,  point-in-time restore time $ptime"
   fi	  
fi

#create softlink of the right control file
#cd ${mount}1/$shost/$sdbname/controlfile

#echo "get point-in-time controlfile"

#for bfile in *c-*.ctl; do
#   bitime=`ls -l $bfile | gawk '{print $6 " " $7 " " $8}'`
#   btime=`/bin/gdate -d "$bitime" '+%Y%m%d%H%M%S'`
##     echo file time $btime
##     echo ptime $ptime
#   if [[ $ptime -lt $btime ]]; then
#     controlfile=$bfile
#	 oribtime=${btime::${#btime}-2}
#     break
#   else
#     controlfile1=$bfile
#	 oribtime1=${btime::${#btime}-2}
#   fi
#done
#
#if [[ -z $controlfile ]]; then
#   if [[ -z $controlfile1 ]]; then
#     echo "The cnntrolfile for database $dbname at $ptime is not found"
#     exit 1
#   else
#     echo "The controlfile is $controlfile1"
#	 controlfile=$controlfile1
#   fi
#fi
#ln -s ${mount}1/$shost/$sdbname/controlfile/$controlfile $backup_location/controlfile/$controlfile 

# create softlink of the backed up controlfile 
cd ${mount}1/$shost/$sdbname/controlfile

num_cfile=`ls | wc -l`
cfile=(`ls`)
#echo ${cfile[0]}
i=1
j=0
while [ $i -le $num ]; do
  
  if [[ $j -lt $num_cfile ]]; then
     ln -s ${mount}${i}/$shost/$sdbname/controlfile/${cfile[$j]} $backup_location/controlfile/${cfile[$j]}
  fi

  i=$[$i+1]
  j=$[$j+1]


  if [[ $i -gt $num && $j -le $num_cfile ]]; then 
     i=1
  fi
  
done


#create softlink of the data files

## first we need to choose the point-in-time datafile directory
cd ${mount}1/$shost/$sdbname

dirtimelist=`ls -d datafile* | gawk -F "." '{print $2}'`
d=0
for dtime in $dirtimelist; do
   if [[ $ptime -lt $dtime ]]; then
      if [[ $d -eq 0 ]]; then
         echo "There is no backup done before the specified time $itime in $ora_pfile"
	  exit 1
      else
         time2=$dtime
         break
      fi
   else
      time1=$dtime
   fi
   d=$[$d+1]
done
#echo time2 is $time2
#echo time1 is $time1

## create softlink of the data files in datafile directory
if [[ -z $time2 ]]; then
   datafiledir=(datafile.${time1})
   echo first datafile directory is ${mount}1/$shost/$sdbname/${datafiledir[1]}
else
   datafiledir=(datafile.${time1} datafile.${time2})
   echo first datafile directory is ${mount}1/$shost/$sdbname/${datafiledir[1]}
   echo second datafile directory is ${mount}1/$shost/$sdbname/${datafiledir[2]} 
fi

for (( z=0; z < ${#datafiledir[@]}; z++ )); do
  
  if [[ ! -d ${backup_location}/${datafiledir[$z]} ]]; then
     echo ${backup_location}/${datafiledir[$z]}
     mkdir -p ${backup_location}/${datafiledir[$z]}
  fi
   
  echo ${mount}1/$shost/$sdbname/${datafiledir[$z]}
  
  cd ${mount}1/$shost/$sdbname/${datafiledir[$z]}

  num_dfile=`ls *| wc -l`
  dfile=(`ls *`)
  i=1
  j=0
  while [ $i -le $num ]; do
    mountstatus=`mount | grep -i  "${mount}${i}"`
    if [[ -n $mountstatus ]]; then
#      echo "$mount${i} is mount point"
#      echo " "
	
      if [[ $j -lt $num_dfile ]]; then
        ln -s ${mount}${i}/$shost/$sdbname/${datafiledir[$z]}/${dfile[$j]} $backup_location/${datafiledir[$z]}/${dfile[$j]}
      fi

      i=$[$i+1]
      j=$[$j+1]


      if [[ $i -gt $num && $j -le $num_dfile ]]; then 
        i=1
      fi
    else
      echo "$mount${i} is not a mount point. duplicate will not start"
      echo "The mount prefix may not be correct or"
      echo "The input of the number of mount points $num may exceed the actuall number of mount points"
      df -h ${mount}*
      exit 1
    fi
  done
done

#create softlink of the archivelogs
cd ${mount}1/$shost/$sdbname/archivelog

num_afile=`ls | wc -l`
afile=(`ls`)
#echo ${afile[0]}
i=1
j=0
while [ $i -le $num ]; do
  
  if [[ $j -lt $num_afile ]]; then
     ln -s ${mount}${i}/$shost/$sdbname/archivelog/${afile[$j]} $backup_location/archivelog/${afile[$j]}
  fi

  i=$[$i+1]
  j=$[$j+1]


  if [[ $i -gt $num && $j -le $num_afile ]]; then 
     i=1
  fi
  
done
}

function create_rman_duplicate_file_localdisk {

echo "Create rman duplicate file"
echo "RUN {" >> $drmanfiled

i=1
j=0
while [ $i -le $num ]; do

  if [[ $j -lt $parallel ]]; then
     allocate_database[$j]="allocate auxiliary channel fs$j device type disk;"
     unallocate[j]="release channel fs$j;"
  fi

  i=$[$i+1]
  j=$[$j+1]


  if [[ $i -gt $num && $j -le $parallel ]]; then 
     i=1
  fi
done

for (( i=0; i < ${#allocate_database[@]}; i++ )); do
   echo ${allocate_database[$i]} >> $drmanfiled
done

#echo "ora_pfile is $ora_pfile"
#more $ora_pfile
cd ${DIR}
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

if [[ ! -z $ora_spfile ]]; then
  if test -f $ora_spfile; then
    if [[ -z $pdbname ]]; then
       echo "duplicate target database to '$toraclesid' BACKUP LOCATION '$backup_location'" >> $drmanfiled
    else
       echo "duplicate target database to '$toraclesid' pluggable database '$pdbname' BACKUP LOCATION '$backup_location'" >> $drmanfiled
    fi
    if [[ $shost == $thost ]]; then
       echo ";" >> $drmanfiled
    else
       echo "nofilenamecheck;" >> $drmanfiled
    fi
  else
     echo "$ora_spfile does not exist"
     exit 1
  fi
else
  if [[ -z $pdbname ]]; then
     if [[ $shost == $thost ]]; then
        echo "duplicate target database to '$toraclesid' BACKUP LOCATION '$backup_location';" >> $drmanfiled
     else
        echo "duplicate target database to '$toraclesid' BACKUP LOCATION '$backup_location' nofilenamecheck;" >> $drmanfiled
     fi
  else
     if [[ $shost == $thost ]]; then
        echo "duplicate target database to '$toraclesid' pluggable database '$pdbname' BACKUP LOCATION '$backup_location';" >> $drmanfiled
     else
        echo "duplicate target database to '$toraclesid' pluggable database '$pdbname' BACKUP LOCATION '$backup_location' nofilenamecheck;" >> $drmanfiled
     fi
  fi
fi  

for (( i=0; i < ${#unallocate[@]}; i++ )); do
   echo ${unallocate[$i]} >> $drmanfiled
done

echo "}" >> $drmanfiled
echo "exit;" >> $drmanfiled

echo "finished creating rman duplicate file"
}

function create_rman_duplicate_file {

echo "Create rman duplicate file"
echo "RUN {" >> $drmanfiled

i=1
j=0
while [ $i -le $num ]; do

  if [[ $j -lt $parallel ]]; then
     allocate_database[$j]="allocate auxiliary channel fs$j device type disk;"
     unallocate[j]="release channel fs$j;"
  fi

  i=$[$i+1]
  j=$[$j+1]


  if [[ $i -gt $num && $j -le $parallel ]]; then 
     i=1
  fi
done

for (( i=0; i < ${#allocate_database[@]}; i++ )); do
   echo ${allocate_database[$i]} >> $drmanfiled
done

#echo "ora_pfile is $ora_pfile"
#more $ora_pfile
cd ${DIR}
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


if [[ ! -z $ora_spfile ]]; then
  if test -f $ora_spfile; then
    if [[ -z $pdbname ]]; then
       echo "duplicate database '$sdbname' to '$toraclesid'" >> $drmanfiled
    else
       echo "duplicate database '$sdbname' to '$toraclesid' pluggable database $spdbname" >> $drmanfiled
    fi
    if [[ $shost == $thost ]]; then
       echo ";" >> $drmanfiled
    else
       echo "nofilenamecheck;" >> $drmanfiled
    fi	  
  else
     echo "$ora_spfile does not exist"
     exit 1
  fi
else
  if [[ -z $pdbname ]]; then
     if [[ $shost == $thost ]]; then
        echo "duplicate database '$sdbname' to '$toraclesid';" >> $drmanfiled
     else
        echo "duplicate database '$sdbname' to '$toraclesid' nofilenamecheck;" >> $drmanfiled
     fi
  else
     if [[ $shost == $thost ]]; then
        echo "duplicate database '$sdbname' to '$toraclesid' pluggable database '$spdbname';" >> $drmanfiled
     else
        echo "duplicate database '$sdbname' to '$toraclesid' pluggable database '$spdbname' nofilenamecheck;" >> $drmanfiled
     fi
  fi
fi  

for (( i=0; i < ${#unallocate[@]}; i++ )); do
   echo ${unallocate[$i]} >> $drmanfiled
done

echo "}" >> $drmanfiled
echo "exit;" >> $drmanfiled

echo "finished creating rman duplicate file"
}

function duplicate {

echo "Database duplicate started at " `/bin/gdate '+%Y%m%d%H%M%S'`
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

if [[ -z $targetc && -z $catalogc ]]; then
   rman log $drmanlog << EOF
   connect auxiliary /
   @$drmanfiled
EOF
fi

if [[ `grep -i error ${drmanlog}` ]]; then
   if [[ `grep -i "fs0 not allocated" $drmanlog` ]]; then
      echo "Database duplicate finished at " `/bin/gdate '+%Y%m%d%H%M%S'`
      if [[ -z $targetc && -z $catalogc ]];then
         echo clean the softlink
#         if [[ -n ${backup_location} ]]; then
#            /bin/rm -r ${backup_location}/*
#         fi
      fi
   else
      echo "Database duplicatep failed at " `/bin/gdate '+%Y%m%d%H%M%S'`
      echo clean the softlink
#      if [[ -n ${backup_location} ]]; then
#         /bin/rm -r ${backup_location}/*
#      fi
      echo "spfile is"
      ls -l ${oracle_home}/dbs/spfile${toraclesid}.ora
      echo "Check rmanlog file $drmanlog"
      echo "The last 10 line of rman log output"
      echo " "
      tail $drmanlog 
      echo " "
      echo "Once the error is identified and corrected, you can rerun the duplicate command. 
Please make sure the auxiliary database is shutdown and the spfile ${oracle_home}/dbs/spfile${toraclesid}.ora is removed before the resun.
Please verify it is the auxiliary database by run the following the SQLPLUS command \"select name from v\$database;\" and \"select open_mode from v\$database;\"
before shutdown the auxiliary database.
	  "
      exit 1
   fi
else
  echo "Database duplicate finished at " `/bin/gdate '+%Y%m%d%H%M%S'`
  if [[ -z $targetc && -z $catalogc ]];then
     echo clean the softlink
#     if [[ -n ${backup_location} ]]; then
#        /bin/rm -r ${backup_location}/*
#     fi
  fi
fi

}

setup

if [[ $preview != [Yy]* ]]; then
   echo prepare duplication
   echo " "
   check_create_oracle_init_file
   duplicate_prepare
fi
if [[ -z $targetc && -z $catalogc ]];then
   echo prepare duplication
   echo " "
   create_softlink
   create_rman_duplicate_file_localdisk
else
   create_rman_duplicate_file
fi
if [[ $preview = [Yy]* ]]; then
   echo ORACLE DATABASE DUPLICATE SCRIPT
   echo " "
   cat $drmanfiled
else
   duplicate
fi
