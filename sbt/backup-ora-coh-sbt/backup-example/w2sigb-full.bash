#!/bin/bash

host=`uname -n`
oracle_database=w2sigb
archive_backup_only=no
incremental_level=0
vip_file=/home/oracle1/scripts/sbt/vip-list
view=ora_sbt/$host/$oracle_database
sbt_code=/u01/app/cohesity/libsbt_6_and_7_linux-x86_64.so
retention=7

# backup-ora-coh-oim.bash script does Oracle backup
/home/oracle1/scripts/sbt/rman/backup-ora-coh-sbt.bash -o $oracle_database -a $archive_backup_only -i $incremental_level -f $vip_file -v $view -s $sbt_code -e $retention
