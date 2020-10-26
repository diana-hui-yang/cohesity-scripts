#!/bin/bash
#
# Name:         nfs-mount.bash
#
# Function:     This script needs root privilege  
#		It mounts the same Cohesity view on Linux server using Cohesity VIPs.
#		It also adds the information to /etc/fstab.
#		The number of mounts is the number of VIPs in vip-list file
#
# Show Usage: run the command to show the usage
#
# Changes:
# 06/15/20 Diana Yang   New script
# 10/25/20 Diana Yang   Support Linux and Solaris
#
#################################################################

function show_usage {
echo "usage: nfs-mount.bash -f <vip file> -v <view> -m <mount>"
echo " -f : file that has vip list"
echo " -v : Cohesity view"
echo " -m : mount-prefix (like /coh/ora)"
}

while getopts ":f:v:m:" opt; do
  case $opt in
    f ) vipfile=$OPTARG;;
    v ) view=$OPTARG;;
    m ) mount=$OPTARG;;
  esac
done

#echo  $vipfile, $view, $mount

# Check required parameters
if test $vipfile && test $view && test $mount
then
  :
else
  show_usage 
  exit 1
fi

if test -f $vipfile
then
   echo "file $vipfile provided exist, script continue"
else 
   echo "file $vipfile provided does not exist"
   exit 1
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

        mountstatus=`mount | grep -i  "${mount}${i}"`
        if [[ -n $mountstatus ]]; then
           echo "${mount}$i is a mount point"
        else
           mount ${mount}$i
        fi
     fi
              
     i=$[$i+1]
  fi
            
done < $vipfile

ls -ld ${mount}1

echo "Need to change the permission to Oracle if it is not set up yet"
