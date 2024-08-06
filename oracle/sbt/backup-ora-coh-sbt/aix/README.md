## Download the script
- /opt/freeware/bin/curl -O https://raw.githubusercontent.com/diana-hui-yang/cohesity-scripts/master/oracle/sbt/backup-ora-coh-sbt/aix/aix-backup-ora-coh-sbt.ksh
- chmod 750 aix-backup-ora-coh-dedup.ksh

## Description
When run the script without any options, it displays the script usage

Required parameters
-  -h : host (scanname is required if it is RAC. optional if it is standalone.)
- -o : ORACLE_DB_NAME (Need to have an entry of this database in /etc/oratab. If it is RAC, it is db_name)
- -y : Cohesity Cluster DNS name
- -a : archivelog only backup (yes means archivelog backup only, no means database backup plus archivelog backup, default is no)
- -i : If not archivelog only backup, it is full or incremental backup. 0 is full backup, and 1 is cumulative incremental backup, offline is offline full backup
- -v : Cohesity View that is configured to be the target for Oracle backup
- -u : Retention time (days to retain the backups, expired file are deleted by SBT. It is only required if -e option is not used or Cohesity policy is not used)
- -e : Retention time (days to retain the backups, expired file are deleted by Oracle. It is only required if retention is managed by oracle only)

Optional parameters
-  -r : Target connection (example: "<dbuser>/<dbpass>@<target connection string> as sysbackup", optional if it is local backup)
- -c : Catalog connection (example: "<dbuser>/<dbpass>@<catalog connection string>", optional)
- -n : Rac nodes connectons strings that will be used to do backup (example: "<rac1-node connection string,ora2-node connection string>")
- -p : number of channels (Optional, default is 4)
- -f : The file lists Cohesity Cluster VIPs (default name is vip-list and default directory is config)
- -s : Cohesity SBT library name including directoy or just directory (default name is libsbt_aix_powerpc.so, default directory is lib)
- -l : Archive logs retain days (days to retain the local archivelogs before deleting them. default is 1 day, no means not deleting local archivelogs on disk)
- -b : Number of times backing Archive logs (default is 1.)
- -m : ORACLE_HOME (default is /etc/oratab, optional.)
- -z : section size in GB (Optional, default is no section size)
- -t : RMAN TAG
- -k : RMAN compression (Optional, yes means RMAN compression. no means no RMAN compression. default is no)
- -w : yes means preview rman backup scripts


## Backup to Cohesity view "orasbt1" exmaple

### Full backup example when sbt library is in lib directory under the script directory
./aix-backup-ora-coh-sbt.ksh -o orcl -i 0 -y cohesity_name -v orasbt1 -p 4 -e 30
### Cumulative backup example when sbt library is in directory /u01/app/cohesity
./aix-backup-ora-coh-sbt.ksh -o orcl -i 1 -y cohesity_name -v orasbt1 -p 3 -e 30 -s /u01/app/coheisty
### Archive log backup example when sbt library is in lib directory under the script directory
./aix-backup-ora-coh-sbt.ksh -o orcl -a yes -y cohesity_name -v orasbt1 -p 2 -e 30



