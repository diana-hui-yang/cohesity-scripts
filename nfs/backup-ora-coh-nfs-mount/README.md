## Download the script

- curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/nfs/backup-ora-coh-nfs-mount/backup-ora-coh-nfs-mount.bash
- chmod 750 backup-ora-coh-nfs-mount.bash

- curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/nfs/backup-ora-coh-nfs-mount/aix-backup-ora-coh-nfs-mount.bash
- chmod 750 aix-backup-ora-coh-nfs-mount.bash

## Backup scripts Description

The backup scripts mount multiple Cohesity NFS shares before backing up Oracle databases. They umount the NFS shares after the backup is done and there is no more RMAN backup
using these scripts are running. It requires Oracle user to have mount and umount root privilege. 

The backup files are in Oracle backupset format. It supports full, incremental, and archive logs backup options. It also supports recvoery catalog.

When run the script without any options, it displays the script usage

 Required Parameters
- -h : host (scanname is required if it is RAC. optional if it is standalone.)
- -o : ORACLE_DB_NAME (Need to have an entry of this database in /etc/oratab. If it is RAC, it is db_unique_name)
- -a : yes (yes means archivelog backup only, no means database backup plus archivelog backup, no is optional)
- -i : If not archive only, it is full or incremental backup. 0 is full backup, and 1 is cumulative incremental backup
- -y : Cohesity Cluster DNS name
- -v : Cohesity View that is configured to be the target for Oracle backup
- -m : mount-prefix (like /mnt/ora)
- -e : Retention time (days to retain the backups, apply only after uncomment "Delete obsolete" in this script)

 Optional Parameters
- -r : Target connection (example: "<dbuser>/<dbpass>@<target connection string> as sysbackup", optional if it is local backup)
- -c : Catalog connection (example: "<dbuser>/<dbpass>@<catalog connection string>", optional)
- -d : Rac nodes connectons strings that will be used to do backup (example: "<rac1-node connection string,ora2-node connection string>")
- -p : number of channels (Optional, default is 4)
- -n : number of mounts
- -l : Archive logs retain days (days to retain the local archivelogs before deleting them. default is 1 day)
- -b : ORACLE_HOME (default is /etc/oratab, optional.)
- -z : section size in GB (Optional, default is no section size)
- -w : yes means preview rman backup scripts

## backup-ora-coh-nfs-mount.bash Backup Example
### Full backup example
./backup-ora-coh-nfs-mount.bash -o orcl -a no -i 0 -y cohesity-o1 -v ora -m /coh/ora -p 6 -e 30
### Cumulative backup example
./backup-ora-coh-nfs-mount.bash -o orcl -a no -i 1 -y cohesity-o1 -v ora -m /coh/ora -p 3 -e 30
### Archive log backup example
./backup-ora-coh-nfs-mount.bash -o orcl -a yes -y cohesity-o1 -v ora -m /coh/ora -p 2 -e 30

## Backup-ora-coh-nfs-mount.bash RAC database backup Example
### Full backup example for RAC database
./backup-ora-coh-nfs-mount.bash -h orascan -o orarac -a no -i 0 -y cohesity-o1 -v ora -m /coh/ora -p 6 -e 30
### Cumulative backup example for RAC database
./backup-ora-coh-nfs-mount.bash  -h orascan -o orarac -a no -i 1 -y cohesity-o1 -v ora -m /coh/ora -p 3 -e 30
### Archive log backup example for RAC database
./backup-ora-coh-nfs-mount.bash  -h orascan -o orarac -a yes -y cohesity-o1 -v ora -m /coh/ora -p 2 -e 30


