#!/bin/bash

oracle_instance=cohcdbb
backup_host=oracle1
oracle_mount_prefix=/coh/oraoim
number_of_mount=4


/home/oracle/scripts/oim/rman/restore-ora-coh-oim.bash -h $backup_host -i $oracle_instance -m $oracle_mount_prefix -n $number_of_mount
