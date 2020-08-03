#!/bin/bash

oracle_instance=w2sigb
vip_file=/home/oracle1/scripts/dedup/vip-list
view=ora_sbt_restore
dedup_code_directory=/u01/app/cohesity
force=yes

/home/oracle1/scripts/dedup/rman/restore-ora-coh-dedup.bash -i $oracle_instance -j $vip_file -v $view -s $dedup_code_directory -f $force
