## Download the script
- curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/oim/restore-ora-coh-oim/restore-ora-coh-oim.bash
- chmod 750 restore-ora-coh-oim.bash

## Description
The scripts restores database from the backup files created by script backup-ora-coh-oim.bash

When run the script without any options, it displays the script usage

Basic parameter

- -h : backup host
- -i : Oracle instance name. If it is not RAC, it is the same as DB name. If it is RAC, it is the instance name like cohcdba2
- -m : mount-prefix (like /coh/ora)
- -n : number of mounts
- -f : yes means force. It will restore Oracle database. Without it, it will just run RMAN validate (Optional)

Optional Parameter

- -r : RMAN login (example: "rman target / "), optional
- -d : Oracle database name. only required for RAC. If it is RAC, it is the database name like cohcdba
- -c : File contains restore location setting, example: set newname for database to '/oradata/restore/orcl/%b';
- -t : Point in Time (format example: "2019-01-27 13:00:00"), optional
- -l : yes means complete restore including control file, no means not restoring controlfile
- -p : number of channels (default is 4), optional
- -o : ORACLE_HOME (default is current environment), optional
- -w : yes means preview rman backup scripts

## Restore exmaple

### Restore database validate example
- ./restore-ora-coh-oim.bash -h oracle1 -i orcl -m /coh/ora -n 4 -p 3
### Restore database assuming controlfile are still intact
- ./restore-ora-coh-oim.bash -h oracle1 -i orcl -m /coh/ora -n 4 -f yes
### Restore controlfile, then database
Note: before running this commaand, several prepare steps should be done first. init file should be created, adump directory should be created. Check the scripts example in restore-example directory for for details
- ./restore-ora-coh-oim.bash -h oracle1 -i orcl -t "2020-08-02 12:00:00" -l yes -m /coh/ora -n 4 -f yes
