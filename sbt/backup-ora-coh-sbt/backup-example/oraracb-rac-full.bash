#!/bin/bash

scanname=orascan1
oracle_database=oraracb
incremental_level=0
view=orasbt1/$scanname/$oracle_database
retention=7
cohesity_name="cohesity"

# backup-ora-coh-oim.bash script does Oracle backup
/home/oracle/scripts/sbt/rman/backup-ora-coh-sbt.bash -h $scanname -o $oracle_database -y "${cohesity_name}" -i $incremental_level -v $view -u $retention

or 
scanname=orascan1
oracle_database=oraracb
incremental_level=0
view=orasbt1/$scanname/$oracle_database
retention=7
cohesity_name="cohesity"
racnode1=orarac1
racnode2=orarac2

/home/oracle/scripts/sbt/rman/backup-ora-coh-sbt.bash -h $scanname -r "sys/<password>@${scanname}/${oracle_database}" -y "${cohesity_name}" -i $incremental_level -v $view -u $retention -n "{racnode1}/${oracle_database},${racnode2|/${oracle_database}"
