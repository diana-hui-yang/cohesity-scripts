## Download the script
- curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/nfs/restore-ora-coh-nfs/linux/restore-ora-coh-nfs.bash
- chmod 750 restore-ora-coh-nfs.bash

## Description
The scripts restores database from the backup files created by script backup-ora-coh-nfs.bash

When run the script without any options, it displays the script usage

Basic parameter

- -i : Oracle instance name. If it is not RAC, it is the same as DB name. If it is RAC, it is the instance name like cohcdba2
- -d : Oracle database name. only required for RAC. If it is RAC, it is the database name like cohcdba
- -m : mount-prefix (like /coh/ora)
- -n : number of mounts
- -f : yes means force. It will restore Oracle database. Without it, it will just run RMAN validate (Optional)


Optional Parameter

- -h : Oracle database host that the backup was run.
- -c : Catalog connection (example: "<dbuser>/<dbpass>@<catalog connection string>", optional)
- -b : File contains restore location setting, example: set newname for database to '/oradata/restore/orcl/%b';
- -t : Point in Time (format example: 2019-01-27 13:00:00), the time should be based on source server timezone, optional
- -l : yes means complete restore including control file, no means not restoring controlfile
- -p : number of channels (Optional, default is same as the number of mounts4)
- -o : ORACLE_HOME (Optional, default is current environment)
- -w : yes means preview rman backup scripts

## Restore exmaple

### Restore database validate example
- ./restore-ora-coh-nfs.bash -h oracle1 -i orcl -m /coh/ora -n 4 -p 3
### Restore database assuming controlfile are still intact
- ./restore-ora-coh-nfsbash -h oracle1 -i orcl -m /coh/ora -n 4 -f yes
### Restore controlfile, then database
Note: before running this commaand, several prepare steps should be done first. init file should be created, adump directory should be created. Check the scripts example in restore-example directory for for details
- ./restore-ora-coh-nfs.bash -h oracle1 -i orcl -t "2020-08-02 12:00:00" -l yes -m /coh/ora -n 4 -f yes
