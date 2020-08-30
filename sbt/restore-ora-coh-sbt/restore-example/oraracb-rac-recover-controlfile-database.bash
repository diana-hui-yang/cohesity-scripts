#!/bin/bash

#this script will not use the orignal Cohesity view of Oracle backups. It will use a cloned view.

oracle_instance=oraracb1
oracle_db=oraracb
scanname=orascan1
restore_controlfile=yes
vip_file=/home/oracle/scripts/sbt/vip-list
view=orasbt1
sbt_code=/u01/app/cohesity
force=yes
point_in_time="2020-08-02 12:00:00"

# Oracle restore
/home/oracle/scripts/sbt/rman/restore-ora-coh-sbt.bash -h $scanname -i $oracle_instance -d $oracle_db -t "${point_in_time}" -l $restore_controlfile -j $vip_file -v $view/$host/$oracle_instance -s $sbt_code -f $force

