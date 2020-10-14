#!/bin/bash

oracle_host=orawest
oracle_database=cohcdbb
backup_incre=0
archive_backup_only=no
oracle_mount_prefix=/coh/oranfs
number_of_mount=4
retention=14

/home/oracle1/scripts/nfs/rman/backup-ora-coh-nfs.bash -h $oracle_host -o $oracle_database  -a $archive_backup_only -i 0 -m $oracle_mount_prefix -n $number_of_mount -e $retention
