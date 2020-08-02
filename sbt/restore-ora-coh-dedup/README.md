## Download the script
- curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/sbt/restore-ora-coh-dedup/restore-ora-coh-dedup.bash
- chmod 750 restore-ora-coh-dedup.bash

## Description
The scripts restores database uses Cohesity Source-side dedup library, and from the backup files created by script backup-ora-coh-dedup.

When run the script without any options, it displays the script usage

Basic parameter

- -r : RMAN login (example: \"rman target / \", optional)"
- -h : backup host (optional)"
- -i : Oracle instance name. If it is not RAC, it is the same as DB name. If it is RAC, it is the instance name like cohcdba2"
- -d : Oracle database name. only required for RAC. If it is RAC, it is the database name like cohcdba"
- -t : Point in Time (format example: "2019-01-27 13:00:00"), optional"
- -l : yes means complete restore including control file, no means not restoring controlfile, optional"
- -j : file that has vip list"
- -v : Cohesity view"
- -s : Cohesity SBT library home"
- -p : number of channels (Optional, default is same as the number of mounts4)"
- -o : ORACLE_HOME (Optional, default is current environment)"
- -f : yes means force. It will testore Oracle database without prompt"
- -c : yes means this script will catalog archivelogs before recovery"
- -w : yes means preview rman backup scripts (Optional)"
- -x : yes means run RMAN restore validate (Optional)"

## VIP file content example
- 10.19.2.6
- 10.19.2.7
- 10.19.2.8
- 10.19.2.9

## Restore exmaple

### Restore database validate example
./restore-ora-coh-dedup.bash -i orcl -j vip-list -v orasbt1 -s /u01/app/coheisty
### Restore database assuming controlfile are stil intact
./restore-ora-coh-dedup.bash -i orcl -j vip-list -v orasbt1 -s /u01/app/coheisty -f yes
### Restore controlfile, then database
Note: before running this commaand, several prepare steps should be done first.
init file should be created, adump directory should be created, a restore Cohesity view should be used, a read-only mount of production view on this server. 
Check the example for for details
./restore-ora-coh-dedup.bash  -i orcl -t "2020-08-02 12:00:00" -l yes -j vip-list -v orasbt1 -s /u01/app/coheisty -f yes


