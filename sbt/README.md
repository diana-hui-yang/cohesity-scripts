# Cohesity Oracle Backup Sample Script using souce-side dedupe library (sbt_tape)
Warning: this code is provided on a best effort basis and is not in any way officially supported or sanctioned by Cohesity. The code in this repository is provided as-is and the author accepts no liability for damages resulting from its use.

## Download the script
- curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/sbt/backup-ora-coh-sbt.bash
- chmod 750 backup-ora-coh-nfs.bash

## Description
The scripts uses Cohesity Source-side dedup library to backup Oracle databases. The backup format is backupset. backup-ora-coh-sbt.bash has full, incremental, and archive logs backup options. It also supports recvoery catalog.

When run the script without any options, it displays the script usage

Basic parameter

- -o: Oracle instance
- -f: The file lists Cohesity Cluster VIPs
- -v: Cohesity View that is configured to be the target for Oracle backup
- -p: Number of Oracle channels
- -a: Archive only or not
- -i: If not archive only, it is full or incremental backup. 0 is full backup, and 1 is cumulative incremental backup
- -e: Backup Retention

## VIP file content example
- 10.19.2.6
- 10.19.2.7
- 10.19.2.8
- 10.19.2.9

## Backup exmaple

### Full backup example
./backup-ora-coh-sbt.bash -o orcl -a no -i 0 -f vip-list -v orasbt1 -p 4 -e 30
### Cumulative backup example
./backup-ora-coh-sbt.bash -o orcl -a no -i 1 -f vip-list -v orasbt1 -p 3 -e 30
### Archive log backup example
./backup-ora-coh-sbt.bash -o orcl -a yes -f vip-list -v orasbt1 -p 2 -e 30
