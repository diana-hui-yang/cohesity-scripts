
#!/bin/bash

cohesity_user=oraadmin
cohesity_domain=sa.corp.cohesity.com
cohesity_cluster=10.19.2.70
oracle_host=orascan
oracle_database=cohraca
backup_type=incre
archive_backup_only=no
oracle_mount_prefix=/coh/oim
number_of_mount=4
retention=14
view=oraoim-data

# backup-ora-coh-oim.bash script does Oracle backup, export three variables (host, backup_dir and backup_time), and create catalog bash
 script
/home/oracle/scripts/oim/rman/backup-ora-coh-oim.bash -h $oracle_host -o $oracle_database -t $backup_type -a $archive_backup_only -m $o
racle_mount_prefix -n $number_of_mount -e $retention

if [ $? -ne 0 ]; then
  echo "OIM incremental backup failed at " `/bin/date '+%Y%m%d%H%M%S'`
  exit 1
else
  echo "OIM incremental backup finished at " `/bin/date '+%Y%m%d%H%M%S'`
fi

sleep 30

# source the following file to get backup_dir and backup_time variable
. /tmp/${oracle_database}.cohesity.oim
echo host is $host
echo backup_dir is $backup_dir

# create snapshot of backup files in backup_dir/datafile directory
/home/oracle/scripts/oim/coh/cloneDirectory.py -s $cohesity_cluster -u $cohesity_user -d $cohesity_domain -sp /$view/${backup_dir}/data
file -dp /$view/${backup_dir} -nd datafile.${backup_time}

if [ $? -ne 0 ]; then
  echo "Cohesity snapshot backup files in ${oracle_mount_prefix}1/${backup_dir}/datafile failed at " `/bin/date '+%Y%m%d%H%M%S'`
  exit 1
else
  echo "Cohesity snapshot backup files in ${oracle_mount_prefix}1/${backup_dir}/datafile finished at " `/bin/date '+%Y%m%d%H%M%S'`
fi

# RMAN catalog the snapshot backup file
/home/oracle/scripts/oim/rman/log/${host}/${oracle_database}_catalog.${backup_time}.bash

if [ $? -ne 0 ]; then
  echo "RMAN catalog snapshot backup files failed at " `/bin/date '+%Y%m%d%H%M%S'`
  exit 1
else
  echo "RMAN catalog snapshot backup files finished at " `/bin/date '+%Y%m%d%H%M%S'`
fi
