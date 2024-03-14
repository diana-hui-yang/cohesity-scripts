#!/bin/bash

host=`uname -n`
oracle_database=w2sigb
incremental_level=0
view=ora_sbt
retention=7
cohesity_name="cohesity"

# backup-ora-coh-oim.bash script does Oracle backup
/home/oracle1/scripts/sbt/rman/backup-ora-coh-sbt.bash -o $oracle_database -a $archive_backup_only -i $incremental_level-y "${cohesity_name}" -v $view -e $retention
