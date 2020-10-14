#!/bin/bash

oracle_host=orawest2
oracle_database=cohcdbb
backup_type=full
archive_backup_only=no
oracle_mount_prefix=/coh/oranfs
number_of_mount=4
retention=14


# backup-ora-coh-oim.bash script does Oracle backup, export three variables (host, backup_dir and backup_time), and create catalog bash
