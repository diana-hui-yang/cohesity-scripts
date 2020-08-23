## Download the script
- curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/sbt/backup-ora-coh-sbt/backup-ora-coh-sbt.bash
- chmod 750 backup-ora-coh-dedup.bash

## Description
The scripts uses Cohesity Source-side dedup library to backup Oracle databases. The backup format is backupset. backup-ora-coh-dedup.bash has full, incremental, and archive logs backup options. It should be used with Cohesity snapshot feature as a complete backup solution. Cohesity Remote adapter will run Cohesity snapshow after the backup is done. When using cron job to schedule the job, Cohesity python snapshot script should be used. It can be downloaded from this link https://github.com/bseltz-cohesity/scripts/tree/master/python/backupNow, The script can be launched from a central server and also supports recvoery catalog. 

When run the script without any options, it displays the script usage

Basic parameter

- -o: ORACLE_DB_NAME (Need to have an entry of this database in /etc/oratab. If it is RAC, it is db_unique_name)
- -f: The file lists Cohesity Cluster VIPs
- -v: Cohesity View that is configured to be the target for Oracle backup
- -s: Cohesity SBT library name including directoy or just directory (default name is libsbt_6_and_7_linux-x86_64.so)
- -a: arch (archivelog backup only, optional. default is database backup)
- -i: If not archive only, it is full or incremental backup. 0 is full backup, and 1 is cumulative incremental backup
- -e: Retention time (days to retain the backups, apply only after uncomment "Delete obsolete" in this script)

Optional parameter
- -r : RMAN login (example: "rman target /", optional)
- -h : host (scanname is required if it is RAC. optional if it is standalone.)
- -p : number of channels (Optional, default is 4)
- -l : Archive logs retain days (days to retain the local archivelogs before deleting them. default is 1 day)
- -m : ORACLE_HOME (default is in /etc/oratab, optional.)
- -z : section size in GB (Optional, default is no section size)
- -w : yes means preview rman backup scripts


## VIP file content example
- 10.19.2.6
- 10.19.2.7
- 10.19.2.8
- 10.19.2.9

## Backup exmaple

### Full backup example
./backup-ora-coh-sbt.bash -o orcl -a no -i 0 -f vip-list -s /u01/app/coheisty -v orasbt1 -p 4 -e 30
### Cumulative backup example
./backup-ora-coh-sbt.bash -o orcl -a no -i 1 -f vip-list -s /u01/app/coheisty -v orasbt1 -p 3 -e 30
### Archive log backup example
./backup-ora-coh-sbt.bash -o orcl -a yes -f vip-list -s /u01/app/coheisty -v orasbt1 -p 2 -e 30


## Note
RMAN "delete obsolete" command is used in this script to delete expired backups. Be default, it is commmented out. Please check Oracle Bug report and apply the necessary fixes before you uncomment that line. 

"Oracle Bug 29633753  delete obsolete removes backup created inside recovery window of read only datafiles in nocatalog mode"


The other option to control retention is by using NFS mount. 

