#!/bin/bash

oracle_instance=cohcdbb
backup_host=orawest2
restore_controlfile=no
oracle_mount_prefix=/coh/oraoim
number_of_mount=4
force=yes

/home/oracle1/scripts/oim/rman/restore-ora-coh-nfs.bash -h $backup_host -i $oracle_instance -l $restore_controlfile -m $oracle_mount_prefix -n $number_of_mount -f $force
