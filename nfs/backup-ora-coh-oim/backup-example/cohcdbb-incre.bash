#!/bin/bash

cohesity_user=oraadmin
cohesity_domain=sa.corp.cohesity.com
cohesity_cluster=10.19.2.70
cohesity_job="snap im"
oracle_database=cohcdbb
backup_type=incre
archive_backup_only=no
oracle_mount_prefix=/coh/oraoim
number_of_mount=4
retention=14
view=oraim


# backup-ora-coh-oim.bash script does Oracle backup, export three variables (host, backup_dir and backup_time), and create catalog bash
 script
/home/oracle1/scripts/oim/rman/backup-ora-coh-oim.bash -o $oracle_database -t $backup_type -a $archive_backup_only -m $oracle_mount_pre
fix -n $number_of_mount -e $retention

if [ $? -ne 0 ]; then
  echo "OIM incremental backup failed at " `/bin/date '+%Y%m%d%H%M%S'`
  exit 1
else
  echo "OIM incremental backup finished at " `/bin/date '+%Y%m%d%H%M%S'`
fi

sleep 30

# source the following file to get backup_dir and backup_time variable
. /tmp/${oracle_database}.cohesity.oim

# create snapshot of backup files in backup_dir/datafile directory
/home/oracle1/scripts/oim/coh/cloneDirectory.py -s $cohesity_cluster -u $cohesity_user -d $cohesity_domain -sp /$view/${backup_dir}/dat
afile -dp /$view/${backup_dir} -nd datafile.${backup_time}

if [ $? -ne 0 ]; then
  echo "Cohesity snapshot backup files in ${oracle_mount_prefix}1/${backup_dir}/datafile failed at " `/bin/date '+%Y%m%d%H%M%S'`
  exit 1
else
  echo "Cohesity snapshot backup files in ${oracle_mount_prefix}1/${backup_dir}/datafile finished at " `/bin/date '+%Y%m%d%H%M%S'`
fi

# RMAN catalog the snapshot backup file
/home/oracle1/scripts/oim/rman/log/${host}/${oracle_database}_catalog.${backup_time}.bash

if [ $? -ne 0 ]; then
  echo "RMAN catalog snapshot backup files failed at " `/bin/date '+%Y%m%d%H%M%S'`
  exit 1
else
  echo "RMAN catalog snapshot backup files finished at " `/bin/date '+%Y%m%d%H%M%S'`
fi

# Protect the view
/home/oracle1/scripts/oim/coh/backupNow.py -v $cohesity_cluster -u $cohesity_user -d $cohesity_domain -j "${cohesity_job}" -k 3 -w

if [ $? -ne 0 ]; then
  echo "Cohesity snapshot failed at " `/bin/date '+%Y%m%d%H%M%S'`
  exit 1
else
  echo "Cohesity snapshot finished at " `/bin/date '+%Y%m%d%H%M%S'`
fi
