#!/bin/bash

scanname=orascan1
oracle_database=oraracb
archive_backup_only=no
incremental_level=0
vip_file=/home/oracle/scripts/sbt/vip-list
view=orasbt1/$scanname/$oracle_database
sbt_code=/u01/app/cohesity
retention=7

# backup-ora-coh-oim.bash script does Oracle backup
/home/oracle/scripts/sbt/rman/backup-ora-coh-sbt.bash -h $scanname -o $oracle_database -a $archive_backup_only -i $incremental_level -f $vip_file -v $view/$scanname/$oracle_database -s $sbt_code -e $retention
