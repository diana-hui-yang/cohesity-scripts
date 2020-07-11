## Download the script
- curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/sbt/backup-ora-coh-dedup.bash
- chmod 750 backup-ora-coh-dedup.bash

## Description
The scripts uses Cohesity Source-side dedup library to backup Oracle databases. The backup format is backupset. backup-ora-coh-sbt.bash has full, incremental, and archive logs backup options. It also supports recvoery catalog.

When run the script without any options, it displays the script usage

Basic parameter

- -o: Oracle instance or database
- -f: The file lists Cohesity Cluster VIPs
- -v: Cohesity View that is configured to be the target for Oracle backup
- -s: The directory where libsbt_6_linux-x86_64.so is in
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
./backup-ora-coh-dedup.bash -o orcl -a no -i 0 -f vip-list -s /u01/app/coheisty -v orasbt1 -p 4 -e 30
### Cumulative backup example
./backup-ora-coh-dedup.bash -o orcl -a no -i 1 -f vip-list -s /u01/app/coheisty -v orasbt1 -p 3 -e 30
### Archive log backup example
./backup-ora-coh-dedup.bash -o orcl -a yes -f vip-list -s /u01/app/coheisty -v orasbt1 -p 2 -e 30


## Note
RMAN "delete obsolete" command is used in this script to delete expired backups. Be default, it is commmented out. Please check Oracle Bug report and apply the necessary fixes before you uncomment that line. 

"Oracle Bug 29633753  delete obsolete removes backup created inside recovery window of read only datafiles in nocatalog mode"


The other option to control retention is by using NFS mount. 

