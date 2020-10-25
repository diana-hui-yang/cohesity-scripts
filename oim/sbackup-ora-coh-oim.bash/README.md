## Download the script
- curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/oim/sbackup-ora-coh-oim/sbackup-ora-coh-oim.bash
- chmod 750 backup-ora-coh-oim.bash

## Backup scripts Description

sbackuo-ora-coh-oim.bash can utilize mutiple mount points to backup Oracle databases in SOLARIS. It uses Oracle incremental merge. The backup is incremental and the result is full backup after the merge. It should be used with Cohesity snapshot feature as a complete backup solution. Cohesity Remote adapter will run Cohesity snapshow after the backup is done. When using cron job to schedule the job, Cohesity python snapshot script should be used. It can be downloaded from this link https://github.com/bseltz-cohesity/scripts/tree/master/python/backupNow
This script supports full, incremental, and archive logs backup options. It also supports recvoery catalog.

When run the script without any options, it displays the script usage

 Required Parameters
- -h : host (scanname is required if it is RAC. optional if it is standalone.)
- -o : ORACLE_DB_NAME (Need to have an entry of this database in /etc/oratab. If it is RAC, it is db_unique_name)
- -t : backup type: Full or Incre
- -a : yes (yes means archivelog backup only, no means database backup plus archivelog backup, no is optional)
- -m : mount-prefix (like /mnt/ora)
- -n : number of mounts
- -e : Retention time (days to retain the backups, apply only after uncomment "Delete obsolete" in this script)

 Optional Parameters
- -r : RMAN login (example: "rman target /", optional)
- -p : number of channels (Optional, default is 4)
- -l : Archive logs retain days (days to retain the local archivelogs before deleting them. default is 1 day)
- -b : ORACLE_HOME (default is /etc/oratab, optional.)
- -w : yes means preview rman backup scripts

## sbackup-ora-coh-oim.bash Backup Example

### Incremental merge backup example (incremental backup and the result is full backup)
./sbackup-ora-coh-oim.bash -o orcl -a no -t incre -m /coh/ora -n 4 -p 3 -e 3

### Archive log backup example
./sbackup-ora-coh-oim.bash -o orcl -a yes -m /coh/ora -n 4 -p 2 -e 3

### Full backup example (only needed when forcing a new full)
./sbackup-ora-coh-oim.bash -o orcl -a no -t full -m /coh/ora -n 4 -p 6 -e 3

