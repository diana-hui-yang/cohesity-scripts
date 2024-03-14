#!/bin/bash
#
# Name:         nfs-coh-mount-perm.bash
#
# Function:     This script needs root privilege  
#		It mounts the same Cohesity view on Linux server using Cohesity VIPs.
#		It also adds the information to /etc/fstab.
#		The number of mounts is the number of nodes in Cohesity cluster
#
# Show Usage: run the command to show the usage
#
# Changes:
# 06/15/20 Diana Yang   New script
# 10/25/20 Diana Yang   Support Linux and Solaris
# 01/20/21 Diana Yang   Remove the need to manually create vip-list file
# 02/06/21 Diana Yang   Add more error checking
#
#################################################################

function show_usage {
echo "usage: nfs-coh-mount-perm.bash -y <Cohesity> -v <view> -p <mount-prefix> -n <number of mounts>"
echo " -y : Cohesity Cluster DNS name"
echo " -v : Cohesity view"
echo " -p : mount-prefix (like /coh/ora)"
echo " -n : number of mounts"
}

while getopts ":y:v:p:n:" opt; do
  case $opt in
    y ) cohesityname=$OPTARG;;
    v ) view=$OPTARG;;
    p ) mount=$OPTARG;;
    n ) num=$OPTARG;;
  esac
done

#echo  $cohesityname, $view, $mount

# Check required parameters
if test $view && test $mount
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

if [[ ! -d $DIR/config ]]; then
  echo " $DIR/config does not exist, create it"
  mkdir -p $DIR/config
  
  if [ $? -ne 0 ]; then
    echo "create log directory $DIR/config failed. There is a permission issue"
    exit 1
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

if [[ -z $cohesityname ]]; then
  echo "Cohesity Cluster name is not provided, we will use vipfile"
  vipfile=${DIR}/config/vip-list
else
  vipfiletemp=${DIR}/config/vip-list-temp
  vipfile=${DIR}/config/vip-list
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
  if [[ $num -ge $numnode ]]; then
     num=$numnode
  fi
fi

i=1  
while IFS= read -r ip; do
  
  ip=`echo $ip | xargs echo -n`    	
  echo "Check whether IP $ip can be connected"

  if [[ -n $ip ]]; then
     return=`/bin/ping $ip -c 2`

#    echo "return is $return"
     if echo $return | grep -q error; then
        echo "error: IP $ip can't be connected. It may not be a valid IP. Skip this IP"	 
     else
        echo "IP $ip can be connected"
		
	if [[ $i -le $num ]]; then
          echo "create the mount if it does not exist"
          if [[ ! -d "${mount}$i" ]]; then
             echo "Directory ${mount}$i does not exist, create it"
             if mkdir -p ${mount}$i; then
               echo "${mount}$i is created"
             else
               echo "creating ${mount}$i failed. There is a permission issue"
               exit 1
             fi
          fi

          echo "check whether the mount point is in /etc/fstab"
          mpreturn=`grep -i $ip /etc/fstab | grep -i $view`
		  
          if [[ -z $mpreturn ]]; then
             echo "${mount}$i is not in /etc/fstab, add it to /etc/fstab" 
             echo "${ip}:/${view} ${mount}$i nfs intr,hard,rsize=1048576,wsize=1048576,proto=tcp,vers=3 0 0" >>/etc/fstab
          else
             echo "${mount}$i is already in /etc/fstab" 
          fi

# check whether this mount point is being used

          mount_cnt=`df -h ${mount}$i | grep -wc "${mount}$i$"`
          if [ "$mount_cnt" -lt 1 ]; then
             echo "== "
             echo "mount point ${mount}$i is not mounted. Mount it"
	     if mount ${mount}$i; then
                echo "mount ${mount}${i} is sucessfull at " `/bin/date '+%Y%m%d%H%M%S'`
             else
                echo "mount ${mount}${i} failed at " `/bin/date '+%Y%m%d%H%M%S'`
                exit 1
             fi
           else
             echo "${mount}$i is a mount point"
	  fi
        fi
     fi
              
     i=$[$i+1]
  fi
            
done < $vipfile

ls -ld ${mount}1

echo "Need to change the permission to Oracle if it is not set up yet"
