#!/bin/bash

oracle_instance=cohcdbb
backup_host=orawest2
oracle_mount_prefix=/coh/oraoim
number_of_mount=4


/home/oracle1/scripts/oim/rman/restore-ora-coh-nfs.bash -h $backup_host -i $oracle_instance -m $oracle_mount_prefix -n $number_of_mount
