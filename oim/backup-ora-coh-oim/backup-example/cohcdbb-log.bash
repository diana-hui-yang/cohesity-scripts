#!/bin/bash

cohesity_user=oraadmin
cohesity_domain=sa.corp.cohesity.com
cohesity_cluster=10.19.2.70
cohesity_job="snap im"
oracle_host=orawest2
oracle_database=cohcdbb
archive_backup_only=yes
oracle_mount_prefix=/coh/oraoim
number_of_mount=4
retention=14

/home/oracle1/scripts/oim/rman/backup-ora-coh-oim.bash -h $oracle_host -o $oracle_database -a $archive_backup_only -m $oracle_mount_prefix -n $number_o
f_mount -e $retention

if [ $? -ne 0 ]; then
  echo "Oracle backup failed at " `/bin/date '+%Y%m%d%H%M%S'`
  exit 1
else
  echo "Oracle backup finished at " `/bin/date '+%Y%m%d%H%M%S'`
fi

sleep 30

# Protect the view
/home/oracle1/scripts/oim/coh/backupNow.py -v $cohesity_cluster -u $cohesity_user -d $cohesity_domain -j "${cohesity_job}" -k 3 -w

if [ $? -ne 0 ]; then
  echo "Cohesity snapshot failed at " `/bin/date '+%Y%m%d%H%M%S'`
  exit 1
else
  echo "Cohesity snapshot finished at " `/bin/date '+%Y%m%d%H%M%S'`
fi
