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
# 02/06/21 Diana Yang   Add more error checking
# 05/26/21 Diana Yang   Add cohesity name to vip-list file name
#
#################################################################

function show_usage {
echo "usage: nfs-coh-mount-umount.bash -y <Cohesity Cluster> -v <view> -p <mount-prefix> -n <number of mounts> -m <yes/no>"
echo " -y : Cohesity Cluster DNS name"
echo " -v : Cohesity view"
echo " -p : mount-prefix (like /coh/ora)"
echo " -n : number of mounts"
echo " -m : yes means mount Cohesity view, no means umount Cohesity view"
}

while getopts ":y:v:p:n:m:" opt; do
  case $opt in
    y ) cohesityname=$OPTARG;;
    v ) view=$OPTARG;;
    p ) mount=$OPTARG;;
    n ) num=$OPTARG;;
    m ) action=$OPTARG;;
  esac
done

#echo  $cohesityname, $view, $mount

# Check required parameters
if test $view && test $mount && test $action
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

if [[ -z $cohesityname ]]; then
  echo "Cohesity name is not provided. Check vip-list file" 
  if [[ ! -f $DIR/config/vip-list ]]; then
     echo "can't find $DIR/config/vip-list file. Please provide cohesity name or populate $DIR/config/vip-list with Cohesity VIPs"
     echo " "
     show_usage
     exit 1
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

if [[ -z $cohesityname ]]; then
  echo "Cohesity Cluster name is not provided, we will use vipfile"
  vipfile=${DIR}/config/vip-list
else
  vipfiletemp=${DIR}/config/$cohesityname-vip-list-temp
  vipfile=${DIR}/config/$cohesityname-vip-list
  echo "Cohesity Cluster name is $cohesityname. VIPS will be collected and stored in $vipfile"
  nslookup $cohesityname | grep -i address | tail -n +2 | awk '{print $2}' > $vipfiletemp 
  
  if [[ ! -s $vipfiletemp ]]; then
     echo "Cohesity Cluster name $cohesityname provided here is not in DNS"
     exit 1
  fi

  shuf $vipfiletemp > $vipfile
fi

if [[ -z $num ]]; then
  num=`grep -v -e '^$' $vipfile | wc -l | awk '{print $1}'`
else
  numnode=`grep -v -e '^$' $vipfile | wc -l | awk '{print $1}'`
fi

}

function mount_coh {

echo "mount Cohesity view if they are not mounted yet"
j=1

while [ $j -le $num ]; do
   while IFS= read -r ip; do
    
      ip=`echo $ip | xargs`

      if [[ -n $ip ]]; then   
	  
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
               echo "mount point ${mount}$j is not mounted. Mount it at" `/bin/date '+%Y%m%d%H%M%S'`
               if sudo mount -o intr,hard,rsize=1048576,wsize=1048576,proto=tcp,vers=3,nolock $ip:/${view} ${mount}$j; then
                  echo "mount ${mount}${j} is sucessfull at " `/bin/date '+%Y%m%d%H%M%S'`
               else
                  echo "mount ${mount}${j} failed at " `/bin/date '+%Y%m%d%H%M%S'`
                  exit 1
               fi  
            else      
               echo "== "
               echo "mount point ${mount}$j is already mounted"	   
            fi        			
         fi
	 j=$[$j+1]
      fi
   done < $vipfile   
done

}

function umount_coh {

echo "== "
echo " will umount Cohesity NFS mountpoint"
j=1
while [ $j -le $num ]; do
   while IFS= read -r ip; do
    
      ip=`echo $ip | xargs`
  
      if [[ -n $ip ]]; then  
	  
         if [[ $j -le $num ]]; then
            mount_cnt=`df -h ${mount}$j | grep -wc "${mount}$j$"`
            if [ "$mount_cnt" -ge 1 ]; then
               echo "== "
               echo "mount point ${mount}$j is mounted. umount it at" `/bin/date '+%Y%m%d%H%M%S'`
               if sudo umount ${mount}$j; then
                  echo "umount ${mount}${j} is sucessfull at " `/bin/date '+%Y%m%d%H%M%S'`
               else
                  echo "umount ${mount}${j} failed at " `/bin/date '+%Y%m%d%H%M%S'`	 
               fi
            else
               echo "mount point ${mount}$j is not mounted"
            fi
         fi
         j=$[$j+1]	  
      fi
   done < $vipfile
done

}

create_vipfile
case $action in
  [Yy]* ) mount_coh;;
  [Nn]* ) umount_coh;;
  *     ) echo "The switch after -m $action needs to be yes or no";;
esac

