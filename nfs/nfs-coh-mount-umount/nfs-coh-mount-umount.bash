#!/bin/bash
#
# Name:         nfs-coh-mount-umount.bash
#
# Function:     This script needs user to have sudo privilege to mount and umount  
#		        It mounts and umounts the same Cohesity view on Linux server using Cohesity VIPs.
#	            The number of mounts is the number of nodes in Cohesity cluster.
#
# Show Usage: run the command to show the usage
#
# Changes:
# 01/20/21 Diana Yang   New script
#
#################################################################

function show_usage {
echo "usage: nfs-coh-mount-umount.bash -f <vip file> -v <view> -p <mount-prefix> -m <yes/no>"
echo " -y : Cohesity Cluster DNS name"
echo " -v : Cohesity view"
echo " -p : mount-prefix (like /coh/ora)"
echo " -m : yes means mount Cohesity view, no means umount Cohesity view"
}

while getopts ":y:v:p:m:" opt; do
  case $opt in
    y ) cohesityname=$OPTARG;;
    v ) view=$OPTARG;;
    p ) mount=$OPTARG;;
	m ) action=$OPTARG;;
  esac
done

#echo  $cohesityname, $view, $mount

# Check required parameters
if test $cohesityname && test $view && test $mount && test $action
then
  :
else
  show_usage 
  exit 1
fi

DIRcurrent=$0
DIR=`echo $DIRcurrent |  awk 'BEGIN{FS=OFS="/"}{NF--; print}'`
if [[ ${DIR::1} != "/" ]]; then
  if [[ $DIR = '.' ]]; then
    DIR=`pwd`
  else
    DIR=`pwd`/${DIR}
  fi
fi

function create_vipfile {

if [[ ! -d $DIR/config ]]; then
  echo " $DIR/config does not exist, create it"
  mkdir -p $DIR/config
  
  if [ $? -ne 0 ]; then
    echo "create log directory $DIR/config failed. There is a permission issue"
    exit 1
  fi   
fi

vipfiletemp=${DIR}/config/vip-list-temp
vipfile=${DIR}/config/vip-list
echo "Cohesity Cluster name is $cohesityname. VIPS will be collected and stored in $vipfile"
nslookup $cohesityname | grep -i address | tail -n +2 | awk '{print $2}' > $vipfiletemp 
  
if [[ ! -s $vipfiletemp ]]; then
  echo "Cohesity Cluster name $cohesityname provided here is not in DNS"
  exit 1
fi

shuf $vipfiletemp > $vipfile

if [[ -z $num ]]; then
  num=`wc -l $vipfile | awk '{print $1}'`
fi

}

function mount_coh {

echo "mount Cohesity view if they are not mounted yet"
j=1
while IFS= read -r ip; do
    
   ip=`echo $ip | xargs echo -n`   
	  
   if [[ $j -le $num ]]; then
# check whether mountpoint exist

     if [[ ! -d ${mount}$j ]]; then
       echo "Directory ${mount}${j} does not exist, create it"
       if sudo mkdir -p ${mount}${j}; then
         echo "directory ${mount}${j} is created"
       else
         echo "creating directory ${mount}${j}. There is a permission issue"
         exit 1
       fi
     fi

# check whether this mount point is being used

     mount_cnt=`df -h ${mount}$j | grep -wc "${mount}$j$"`

# If not mounted, mount this IP	to the mountpoint
     if [ "$mount_cnt" -lt 1 ]; then
       echo "== "
       echo "mount point $mount_cnt is not mounted. Mount it at" `/bin/date '+%Y%m%d%H%M%S'`
       if sudo mount -o intr,hard,rsize=1048576,wsize=1048576,proto=tcp,vers=3,nolock $ip:/${view} ${mount}$j; then
          echo "mount ${mount}${j} is sucessfull at " `/bin/date '+%Y%m%d%H%M%S'`
       else
          echo "mount ${mount}${j} failed at " `/bin/date '+%Y%m%d%H%M%S'`
          exit 1
       fi  
     else      
       echo "== "
       echo "mount point $mount_cnt is already mounted"	   
     fi
     j=$[$j+1]
   fi
     
done < $vipfile   

}

function umount_coh {

# check whether any backup for this database is running 
status=`ps -efww | grep -w ${script_name} | grep -w ${dbname} |wc -l`
 echo "status=$status"
if [ "$status" -gt 2 ]; then
   echo "== "
   echo " $dbname database backup is still running at " `/bin/date '+%Y%m%d%H%M%S'`
   echo " will not run umount"
else
   echo "== "
   echo " will umount Cohesity NFS mountpoint"
   j=1
   while IFS= read -r ip; do
    
     ip=`echo $ip | xargs echo -n`   
	  
     if [[ $j -le $num ]]; then
        echo "== "
        if sudo umount ${mount}$j; then
           echo "umount ${mount}${j} is sucessfull at " `/bin/date '+%Y%m%d%H%M%S'`
        else
           echo "umount ${mount}${j} failed at " `/bin/date '+%Y%m%d%H%M%S'`	 
        fi
        j=$[$j+1]	  
     fi
   done < $vipfile
fi

}

create_vipfile
case $action in
  [Yy]* ) mount_coh;;
  [Nn]* ) umount_coh;;
  *     ) echo "The switch after -m $action needs to be yes or no";;
esac

