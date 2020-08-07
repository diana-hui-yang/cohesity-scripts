## Download the script
- curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/sbt/restore-ora-coh-sbt/restore-ora-coh-sbt.bash
- chmod 750 restore-ora-coh-sbt.bash

## Description
The scripts restores database uses Cohesity Source-side dedup library, and from the backup files created by script backup-ora-coh-dedup.

When run the script without any options, it displays the script usage

Basic parameter

- -i : Oracle instance name. If it is not RAC, it is the same as DB name. If it is RAC, it is the instance name like cohcdba2
- -j : file that has vip list
- -v : Cohesity view
- -s : Cohesity SBT library home
- -f : yes means force. It will restore Oracle database. Without it, it will just run RMAN validate (Optional)

Optional Parameter

- -r : RMAN login (example: \"rman target / \"), optional
- -h : backup host (default is current host), optional
- -d : Oracle database name. only required for RAC. If it is RAC, it is the database name like cohcdba
- -t : Point in Time (format example: "2019-01-27 13:00:00"), optional
- -l : yes means complete restore including control file, no means not restoring controlfile
- -p : number of channels (default is 4), optional
- -o : ORACLE_HOME (default is current environment), optional
- -w : yes means preview rman backup scripts 

## VIP file content example
- 10.19.2.6
- 10.19.2.7
- 10.19.2.8
- 10.19.2.9

## Restore exmaple

### Restore database validate example
- ./restore-ora-coh-sbt.bash -i orcl -j vip-list -v orasbt1 -s /u01/app/coheisty
### Restore database assuming controlfile are stil intact
- ./restore-ora-coh-sbt.bash -i orcl -j vip-list -v orasbt1 -s /u01/app/coheisty -f yes
### Restore controlfile, then database
Note: before running this commaand, several prepare steps should be done first.
init file should be created, adump directory should be created, a restore Cohesity view should be used, a read-only mount of production view on this server. 
Check the scripts example in restore-example directory for for details
- ./restore-ora-coh-sbt.bash  -i orcl -t "2020-08-02 12:00:00" -l yes -j vip-list -v orasbt1 -s /u01/app/coheisty -f yes


