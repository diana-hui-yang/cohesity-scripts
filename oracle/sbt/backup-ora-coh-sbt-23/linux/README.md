## Download the script
- curl -O https://raw.githubusercontent.com/diana-hui-yang/cohesity-scripts/master/oracle/sbt/backup-ora-coh-sbt-23/linux/backup-ora-coh-sbt-23.bash
- chmod 750 backup-ora-coh-sbt-23.bash

## Description
When run the script without any options, it displays the script usage

Required parameters

-  -h : host (scanname is required if it is RAC. optional if it is standalone.)
- -o : ORACLE_DB_NAME (Need to have an entry of this database in /etc/oratab. If it is RAC, it is db_name)
- -y : Cohesity Cluster DNS name
- -a : archivelog only backup (yes means archivelog backup only, no means database backup plus archivelog backup, default is no)
- -i : If not archivelog only backup, it is full or incremental backup. 0 is full backup, and 1 is cumulative incremental backup, offline is offline full backup
- -v : Cohesity View that is configured to be the target for Oracle backup
- -e : Cohesity View that is configured to be the Cohesity catalog for Oracle backup


Optional parameters
- -r : Target connection (example: "dbuser/dbpass@target connection string as sysbackup", optional if it is local backup)
- -c : Catalog connection (example: "dbuser/dbpass@catalog connection string", optional)
- -n : RAC nodes connectons strings that will be used to do backup (example: "rac1-node connection string,ora2-node connection string")
- -p : number of channels (Optional, default is 4)
- -f : The file lists Cohesity Cluster VIPs (default name is vip-list and default directory is config)
- -s : Cohesity SBT library name including directoy or just directory (default name is libsbt_6_and_7_linux-x86_64.so, default directory is lib)
- -l : Archive logs retain days (days to retain the local archivelogs before deleting them. default is 1 day, "no" means not deleting local archivelogs on disk)
- -m : ORACLE_HOME (provide ORACLE_HOME if the database is not in /etc/oratab. Otherwise, it is optional.)
- -z : section size in GB (Optional, default is no section size)
- -t : RMAN TAG
- -k : RMAN compression (Optional, yes means RMAN compression. no means no RMAN compression. default is no)
- -g : yes means encryption-in-flight is used. The default is no
- -j : encryption certificate file directory, default directory is lib
- -x : yes means gRPC is used. no means SunRPC is used. The default is yes
- -d : yes means source side dedup is used. The default is yes
- -q : yes means sbt activity record are recorded in sbtio.log. no means only errors are recorded in sbtio.log. The default is yes
- -w : yes means print rman backup scripts only. The RMAN script is not executed


## Backup to Cohesity view "orasbt1" exmaple

### Full backup example when sbt library is in lib directory under the script directory
./backup-ora-coh-sbt-23.bash -o orcl -i 0 -y cohesity_name -v orasbt -e orasbt_catalog -p 4
### Cumulative backup example when sbt library is in directory /u01/app/cohesity
./backup-ora-coh-sbt-23.bash -o orcl -i 1 -y cohesity_name -v orasbt1 -e orasbt_catalog -p 3 -s /u01/app/cohesity
### Archive log backup example when sbt library is in lib directory under the script directory
./backup-ora-coh-sbt-23.bash -o orcl -a yes -y cohesity_name -v orasbt1 -e orasbt_catalog -p 2
