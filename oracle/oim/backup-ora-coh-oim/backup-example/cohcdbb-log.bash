#!/bin/bash

oracle_host=orawest2
oracle_database=cohcdbb
archive_backup_only=yes
oracle_mount_prefix=/coh/oraoim
number_of_mount=4
retention=14

/home/oracle1/scripts/oim/rman/backup-ora-coh-oim.bash -h $oracle_host -o $oracle_database -a $archive_backup_only -m $oracle_mount_prefix -n $number_o
f_mount -e $retention

