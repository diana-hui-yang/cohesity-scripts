## Download the script
- /opt/freeware/bin/curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/oracle/sbt/restore-ora-coh-sbt/aix/aix-restore-ora-coh-sbt.bash
- chmod 750 aix-restore-ora-coh-sbt.bash

## Description
The scripts restores database uses Cohesity Source-side dedup library, and from the backup files created by script aix-backup-ora-coh-sbt.bash

When run the script without any options, it displays the script usage

Required parameters

- -i : Oracle instance name. If it is not RAC, it is the same as DB name. If it is RAC, it is the instance name like cohcdba2
- -d : Source Oracle_DB_Name, only required if it is RAC. It is DB name, not instance name
- -y : Cohesity Cluster DNS name
- -v : Cohesity view
- -f : yes means force. It will restore Oracle database. Without it, it will just run RMAN validate (Optional)

Optional Parameters

- -h : Oracle database host that the backup was run. (default is current host), optional
- -c : Catalog connection (example: "<dbuser>/<dbpass>@<catalog connection string>", optional)
- -b : File contains restore location setting, example: set newname for database to '/oradata/restore/orcl/%b';
- -t : Point in Time (format example: "2019-01-27 13:00:00"), optional
- -l : yes means complete restore including control file, no means not restoring controlfile
- -p : number of channels (default is 4), optional
- -j : The file lists Cohesity Cluster VIPs (default name is vip-list and default directory is config)
- -s : Cohesity SBT library name including directoy or just directory (default name is libsbt_6_and_7_linux-x86_64.so, default directory is lib)
- -o : ORACLE_HOME (default is current environment), optional
- -g : yes means encryption-in-flight is used. The default is no
- -k : encryption certificate file directory, default directory is lib
- -x : yes means gRPC is used. no means SunRPC is used. The default is yes
- -w : yes means preview rman backup scripts

## Restore exmaple

### Restore database validate example when sbt library is in lib directory under the script directory. The database name is "orcl". The database won't be over-written. 
- ./restore-ora-coh-sbt.bash -i orcl -y cohesity -v orasbt1
### Restore database"orcl" assuming controlfile are still intact when sbt library is in directory /u01/app/cohesity. The database will be over-written.
- ./restore-ora-coh-sbt.bash -i orcl -y cohesity -v orasbt1 -s /u01/app/coheisty -f yes
### Restore controlfile, then database "orcl" on the original Oracle server "orawest".  The database will be over-written.
- ./restore-ora-coh-sbt.bash  -i orcl -t "2020-08-02 12:00:00" -l yes -y cohesity -v orasbt1 -f yes
### Restore controlfile, then database "orcl" on a new server "orawestdr". (the original Oracle server is "orawest")
Note: before running this commaand, several prepare steps should be done first.
init file should be created, adump directory should be created. 
Check the scripts example in restore-example directory for more details
- ./restore-ora-coh-sbt.bash -h orawest -i orcl -t "2020-08-02 12:00:00" -l yes -y cohesity -v orasbt1 -f yes
