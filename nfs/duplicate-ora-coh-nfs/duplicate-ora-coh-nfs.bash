#!/bin/bash
#
# Name:         duplicate-ora-coh-nfs.bash
#
# Function:     This script duplicate Oracle database from Oracle backup 
#               in nfs mount.
#
#
# Show Usage: run the command to show the usage
#
# Changes:
# 06/16/2020 Diana Yang   New script (duplicate using target database)
# 07/06/2020 Diana Yang   Add duplicate option from backup location
# 07/23/2020 Diana Yang   Add duplicate option from point in time backup location
#
#################################################################

function show_usage {
echo "usage: duplicate-ora-coh-nfs.bash -r <RMAN login> -b <backup host> -a <target host> -s <Source Oracle_DB_Name> -t <Target Oracle database> -l <file contain duplicate settting> -i <file contain setting to new spfile> -m <mount-prefix> -n <number of mounts> -p <number of channels> -o <ORACLE_HOME> -c <pluggable database> -w <yes/no>" 
echo " "
echo " Required Parameters"
echo " -b : backup host" 
echo " -s : Source Oracle_DB_Name, If Source is not a RAC database, it is the same as Instance name. If it is RAC, it is DB name, not instance name" 
echo " -t : Target Oracle instance name. If it is not RAC, it is the same as DB name. If it is RAC, it is the instance name like cohcdba2"
echo " -l : File contains duplicate settting, example: set newname for database to '/oradata/restore/orcl/%b'; Provide full path"
echo " -m : mount-prefix (like /coh/ora)"
echo " -n : number of mounts"
echo " "
echo " Optional Parameters"
echo " -a : target host (Optional, default is localhost)"
echo " -i : File contains new setting to spfile. example: SET DB_CREATE_FILE_DEST +DGROUP3, Provide full path"
echo " -p : number of channels (Optional, default is same as the number of mounts4)"
echo " -o : ORACLE_HOME (Optional, default is current environment)"
echo " -c : pluggable database (if this input is empty, it is CDB database restore"
echo " -f : yes means force. It will refresh the target database without prompt"
echo " -w : yes means preview rman duplicate scripts"
echo "
"
}

while getopts ":r:b:a:s:t:l:m:n:p:i:o:c:f:w:" opt; do
  case $opt in
    r ) rmanlogin=$OPTARG;;
    b ) shost=$OPTARG;;
    a ) thost=$OPTARG;;
    s ) sdbname=$OPTARG;;
    t ) toraclesid=$OPTARG;;
    l ) ora_pfile=$OPTARG;;
    i ) ora_spfile=$OPTARG;;
    m ) mount=$OPTARG;;
    n ) num=$OPTARG;;
    p ) parallel=$OPTARG;;
    o ) oracle_home=$OPTARG;;
    c ) pdbname=$OPTARG;;
	f ) force=$OPTARG;;
    w ) preview=$OPTARG;;
  esac
done

#echo $rmanlogin $sdbname, $mount, $shost, $num

# Check required parameters
#if test $shost && test $sdbname && test $toraclesid && test $tdbdir && test $mount && test $num
if test $shost && test $sdbname && test $toraclesid && test $mount && test $num
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
  echo "no input for parallel, set parallel to be $num."
  parallel=$num
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

if [[ ! -f $dbpfile ]]; then
   echo "there is no pfile $dbpfile"
   exit 1
fi

if [[ -n $ora_pfile ]]; then
   if [[ ! -f $ora_pfile ]]; then
      echo "there is no $ora_pfile. It is file defined by -l plugin"
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
    echo "create log directory $DIR/log/$thost failed. There is a permission issue"
    exit 1
  fi
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
}

function duplicate_prepare {


if [[ $shost = $thost ]]; then
   echo $shost is the same as $thost
   echo ora_pfile is ${ora_pfile}
   if [[ -z `grep -i DB_CREATE_ONLINE_LOG_DEST_ $dbpfile` ]]; then
      if [[ -z ${ora_pfile} || -z `grep -i db_create_file_dest $dbpfile` ]]; then
       	 echo "db_create_file_dest and DB_CREATE_ONLINE_LOG_DEST_n are not defined in init file $dbpfile"
	 echo "and new database files location is not defined in a file which is defined by -l option, example as the following"
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

function create_softlink {

# get itime from $ora_pfile file
# covert the time to numeric 
if [[ ! -z $ora_pfile ]];then
   itime=`grep to_date $ora_pfile | grep -v "#" |  awk -F "'" '{print $2}'`
   echo "itime is $itime"

   if [[ -z $itime ]]; then
      itime=`/bin/date '+%Y%m%d%H%M%S'`
      echo itime is $itime
      ptime=$itime
      echo "itime is $itime,  point-in-time restore time $ptime"  
   else   
      ptime=`/bin/date -d "$itime" '+%Y%m%d%H%M%S'`
      echo "itime is $itime,  point-in-time restore time $ptime"
   fi
else
   itime=`/bin/date '+%Y%m%d%H%M%S'`
   echo itime is $itime
   ptime=$itime
   echo "itime is $itime,  point-in-time restore time $ptime"  
fi

#create softlink of the right control file
cd ${mount}1/$shost/$sdbname/controlfile

echo "get point-in-time controlfile"

for bfile in *c-*.ctl; do
   bitime=`ls -l $bfile | awk '{print $6 " " $7 " " $8}'`
   btime=`/bin/date -d "$bitime" '+%Y%m%d%H%M%S'`
#     echo file time $btime
#     echo ptime $ptime
   if [[ $ptime -lt $btime ]]; then
     controlfile=$bfile
     break
   else
     controlfile1=$bfile
   fi
done

if [[ -z $controlfile ]]; then
   if [[ -z $controlfile1 ]]; then
     echo "The cnntrolfile for database $dbname at $ptime is not found"
     exit 1
   else
     echo "The controlfile1 is $controlfile1"
     ln -s ${mount}1/$shost/$sdbname/controlfile/$controlfile1 $backup_location/controlfile/$controlfile1
   fi
else
   if [[ -z $controlfile1 ]]; then
     echo "The cnntrolfile1 for database $dbname at $ptime is not found"
   else
     echo "The controlfile1 is $controlfile1"
     ln -s ${mount}1/$shost/$sdbname/controlfile/$controlfile1 $backup_location/controlfile/$controlfile1
   fi
   echo "The controlfile is $controlfile"
   ln -s ${mount}1/$shost/$sdbname/controlfile/$controlfile $backup_location/controlfile/$controlfile 
fi

#create softlink of the data files

## first we need to choose the point-in-time datafile directory
cd ${mount}1/$shost/$sdbname

dirtimelist=`ls -d datafile* | awk -F "." '{print $2}'`
d=0
for dtime in $dirtimelist; do
   if [[ $ptime -lt $dtime ]]; then
      time2=$dtime
      break
   else
      time1=$dtime
   fi
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
	  echo "$mount${i} is mount point"
      echo " "
	
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
    cd ..
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
fi

if [[ ! -z $ora_spfile ]]; then
  if test -f $ora_spfile; then
    if [[ -z $pdbname ]]; then
       echo "duplicate target database to $toraclesid BACKUP LOCATION '$backup_location'" >> $drmanfiled
    else
       echo "duplicate target database to $toraclesid pluggable database $pdbname BACKUP LOCATION '$backup_location'" >> $drmanfiled
    fi
    echo "SPFILE" >> $drmanfiled
    grep -v "^#" < $ora_spfile | { while IFS= read -r spara; do
       para=`echo $spara | xargs echo -n`
       echo $spara >> $drmanfiled
    done }
    echo "nofilenamecheck;" >> $drmanfiled
  else
     echo "$ora_spfile does not exist"
     exit 1
  fi
else
  if [[ -z $pdbname ]]; then
     echo "duplicate target database to $toraclesid BACKUP LOCATION '$backup_location' nofilenamecheck;" >> $drmanfiled
  else
     echo "duplicate target database to $toraclesid pluggable database $pdbname BACKUP LOCATION '$backup_location' nofilenamecheck;" >> $drmanfiled
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

echo "Database duplicate started at " `/bin/date '+%Y%m%d%H%M%S'`
echo "ORACLE SID is $ORACLE_SID"

rman log $drmanlog << EOF
connect auxiliary /
@$drmanfiled
EOF

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
create_softlink
create_rman_duplicate_file
if [[ $preview = "yes" || $preview = "Yes" || $preview = "YES" ]]; then
   echo ORACLE DATABASE DUPLICATE SCRIPT
   echo " "
   cat $drmanfiled
else
   duplicate
fi
