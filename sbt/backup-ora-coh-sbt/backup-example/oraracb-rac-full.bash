#!/bin/bash

scanname=orascan1
oracle_database=oraracb
incremental_level=0
view=orasbt1/$scanname/$oracle_database
retention=7
cohesity_name="cohesity"

# backup-ora-coh-oim.bash script does Oracle backup
/home/oracle/scripts/sbt/rman/backup-ora-coh-sbt.bash -h $scanname -o $oracle_database -y "${cohesity_name}" -i $incremental_level -v $view/$scanname/$oracle_database -e $retention
