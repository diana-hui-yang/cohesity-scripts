#!/bin/bash

oracle_instance=oraracb1
oracle_db=oraracb
scanname=orascan1
vip_file=/home/oracle/scripts/sbt/vip-list
view=orasbt1
sbt_code=/u01/app/cohesity

/home/oracle/scripts/sbt/rman/restore-ora-coh-sbt.bash -h $scanname -i $oracle_instance -d $oracle_db -j $vip_file -v $view/$scanname/$oracle_instance -s $sbt_code
