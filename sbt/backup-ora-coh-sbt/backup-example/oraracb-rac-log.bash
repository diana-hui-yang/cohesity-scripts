#!/bin/bash

cohesity_user=oraadmin
cohesity_domain=sa.corp.cohesity.com
cohesity_cluster=10.19.2.70
cohesity_job="snap sbt"
scanname=orascan1
oracle_database=oraracb
archive_backup_only=yes
vip_file=/home/oracle/scripts/sbt/vip-list
view=orasbt1/$scanname/$oracle_database
sbt_code=/u01/app/cohesity
retention=7

/home/oracle/scripts/sbt/rman/backup-ora-coh-sbt.bash -h $scanname -o $oracle_database -a $archive_backup_only -f $vip_file -v $view/$scanname/$oracle_database -s $sbt_code -e $retention
