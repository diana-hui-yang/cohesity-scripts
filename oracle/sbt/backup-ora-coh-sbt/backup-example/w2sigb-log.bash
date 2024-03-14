#!/bin/bash

host=`uname -n`
oracle_database=w2sigb
archive_backup_only=yes
vip_file=/home/oracle1/scripts/sbt/vip-list
view=ora_sbt
sbt_code=/u01/app/cohesity
retention=7

/home/oracle1/scripts/sbt/rman/backup-ora-coh-sbt.bash -o $oracle_database -a $archive_backup_only -f $vip_file -v $view -s $sbt_code -e $retention
