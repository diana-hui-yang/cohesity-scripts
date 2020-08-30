#!/bin/bash

oracle_instance=w2sigb
host=orawest
vip_file=/home/oracle1/scripts/dedup/vip-list
view=orasbt1
sbt_code=/u01/app/cohesity
force=yes

/home/oracle1/scripts/dedup/rman/restore-ora-coh-sbt.bash -i $oracle_instance -j $vip_file -v $view/$host/$oracle_instance -s $sbt_code -f $force
