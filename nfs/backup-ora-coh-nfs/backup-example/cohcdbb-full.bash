#!/bin/bash

oracle_host=orawest
oracle_database=cohcdbb
incremental_level=0
archive_backup_only=no
oracle_mount_prefix=/coh/oranfs
number_of_mount=4
retention=14

/home/oracle1/scripts/nfs/rman/backup-ora-coh-nfs.bash -h $oracle_host -o $oracle_database  -a $archive_backup_only -i $incremental_level -m $oracle_mount_prefix -n $number_of_mount -e $retention
