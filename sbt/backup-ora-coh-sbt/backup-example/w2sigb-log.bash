#!/bin/bash

cohesity_user=oraadmin
cohesity_domain=sa.corp.cohesity.com
cohesity_cluster=10.19.2.70
cohesity_job="snap sbt"
oracle_database=w2sigb
archive_backup_only=yes
vip_file=/home/oracle/scripts/sbt/vip-list
view=ora_sbt
directory=$view/orawest/w2sigb
sbt_code=/u01/app/cohesity
retention=7

/home/oracle/scripts/sbt/rman/backup-ora-coh-sbt.bash -o $oracle_database -a $archive_backup_only -f $vip_file -v $directory -s $sbt_code -e $retention

if [ $? -ne 0 ]; then
  echo "SBT full backup failed at " `/bin/date '+%Y%m%d%H%M%S'`
  exit 1
else
  echo "SBT full backup finished at " `/bin/date '+%Y%m%d%H%M%S'`
fi

sleep 30

# Protect the view
/home/oracle/scripts/dedup/coh/backupNow.py -v $cohesity_cluster -u $cohesity_user -d $cohesity_domain -j "${cohesity_job}" -k 3 -w

if [ $? -ne 0 ]; then
  echo "Cohesity snapshot failed at " `/bin/date '+%Y%m%d%H%M%S'`
  exit 1
else
  echo "Cohesity snapshot finished at " `/bin/date '+%Y%m%d%H%M%S'`
fi
