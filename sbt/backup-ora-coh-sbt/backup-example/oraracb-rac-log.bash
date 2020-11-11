#!/bin/bash

scanname=orascan1
oracle_database=oraracb
archive_backup_only=yes
view=orasbt1/$scanname/$oracle_database
retention=7
cohesity_name="cohesity"


/home/oracle/scripts/sbt/rman/backup-ora-coh-sbt.bash -h $scanname -o $oracle_database -a $archive_backup_only -y "${cohesity_name}" -v $view/$scanname/$oracle_database -e $retention
