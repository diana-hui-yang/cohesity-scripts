#!/bin/bash

oracle_host=orawest
oracle_database=cohcdbb
archive_backup_only=yes
oracle_mount_prefix=/coh/oranfs
number_of_mount=4
retention=14

/home/oracle1/scripts/nfs/rman/backup-ora-coh-nfs.bash -h $oracle_host -o $oracle_database  -a $archive_backup_only -m $oracle_mount_prefix -n $number_of_mount -e $retention
