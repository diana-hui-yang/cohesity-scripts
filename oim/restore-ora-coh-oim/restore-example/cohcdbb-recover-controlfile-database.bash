#!/bin/bash

oracle_instance=cohcdbb
backup_host=oracle1
restore_controlfile=yes
oracle_mount_prefix=/coh/oraoim
number_of_mount=4
force=yes
point_in_time="2020-09-07 17:40:00"

/home/oracle/scripts/oim/rman/restore-ora-coh-oim.bash -h $backup_host -i $oracle_instance -t "${point_in_time}" -l $restore_controlfile -m $oracle_mount_pr
efix -n $number_of_mount  -f $force
#/home/oracle/scripts/oim/rman/restore-ora-coh-oim.bash -h $backup_host -i $oracle_instance -l $restore_controlfile -m $oracle_mount_prefix -n $number_of_mo
unt -f $force
