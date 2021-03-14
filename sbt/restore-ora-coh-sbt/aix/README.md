## Download the script
- curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/sbt/restore-ora-coh-sbt/aix/aix-restore-ora-coh-sbt.bash
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

- -h : backup host (default is current host), optional
- -c : File contains restore location setting, example: set newname for database to '/oradata/restore/orcl/%b';
- -t : Point in Time (format example: "2019-01-27 13:00:00"), optional
- -l : yes means complete restore including control file, no means not restoring controlfile
- -p : number of channels (default is 4), optional
- -j : The file lists Cohesity Cluster VIPs (default name is vip-list and default directory is config)
- -s : Cohesity SBT library name including directoy or just directory (default name is libsbt_aix_powerpc.so, default directory is lib)
- -o : ORACLE_HOME (default is current environment), optional
- -w : yes means preview rman backup scripts 

## Restore exmaple

### Restore database validate example when sbt library is in lib directory under the script directory
- ./aix-restore-ora-coh-sbt.bash -i orcl -y cohesity -v orasbt1
### Restore database assuming controlfile are still intact when sbt library is in directory /u01/app/cohesity
- ./aix-restore-ora-coh-sbt.bash -i orcl -y cohesity -v orasbt1 -s /u01/app/coheisty -f yes
### Restore controlfile, then database
Note: before running this commaand, several prepare steps should be done first.
init file should be created, adump directory should be created. 
Check the scripts example in restore-example directory for more details
- ./aix-restore-ora-coh-sbt.bash  -i orcl -t "2020-08-02 12:00:00" -l yes -y cohesity -v orasbt1 -f yes

## Restore exmaple from directory "orawest/orcl" under view "orasbt1" exmaple
The following example uses the directory "orawest/orcl" (host is orawest, the database is orcl) under view "orasbt1". You can mount the view to a Unix server to verify the backup files are in this directory.

### duplidate none CDB database example
### Restore database validate example when sbt library is in lib directory under the script directory
- ./aix-restore-ora-coh-sbt.bash -i orcl -y cohesity -v orasbt1/orawest/orcl
### Restore database assuming controlfile are still intact when sbt library is in directory /u01/app/cohesity
- ./aix-restore-ora-coh-sbt.bash -i orcl -y cohesity -v orasbt1/orawest/orcl -s /u01/app/coheisty -f yes
### Restore controlfile, then database
Note: before running this commaand, several prepare steps should be done first.
init file should be created, adump directory should be created. 
Check the scripts example in restore-example directory for for details
- ./aix-restore-ora-coh-sbt.bash  -i orcl -t "2020-08-02 12:00:00" -l yes -y cohesity -v orasbt1/orawest/orcl -f yes
