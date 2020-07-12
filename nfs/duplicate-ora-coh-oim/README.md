## Download the script

- curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/nfs/deduplicate-ora-coh-oim/deduplicate-ora-coh-oim.bash
- chmod 750 deduplicate-ora-coh-oim.bash

## Oracle duplicate scripts Description
This Oracle duplicate script can duplicate Oracle database using the backup files backed up by backup-ora-coh-oim.bash script. It can duplicate Oracle database on the same server of the original Oracle database or an alternate server. It can duplicate CDB database or a PDB database to another CDB. The script by itself can only duplicate the database using the backup files that were backed up in less than 2 day. When duplicating the Oracle database from the backup fileslonger than 2 days and/or the backup files from Cohesity snapshot, prepare-restore.bash should run first before this script. 

When run the script without any options, it displays the script usage

duplicate-ora-coh-oim.bash Basic parameter
- -r : RMAN login (example: \"rman auxiliary / \", optional)"
- -b : backup host" 
- -a : target host (Optional, default is localhost)"
- -s : Source Oracle database" 
- -t : Target Oracle database"
- -f : File contains duplicate settting, example: set newname for database to '/oradata/restore/orcl/%b'; "
- -i : File contains new setting to spfile. example: SET DB_CREATE_FILE_DEST +DGROUP3"
- -m : mount-prefix (like /coh/ora)"
- -n : number of mounts"
- -p : number of channels (Optional, default is same as the number of mounts4)"
- -o : ORACLE_HOME (Optional, default is current environment)"
- -c : pluggable database (if this input is empty, it is CDB database restore"

## duplicate-ora-coh-nfs.bash Backup Example
### Duplicate a traditional Oracle database or CDB database example
./duplicate-ora-coh-nfs.bash  -b $oracle_source_server -s $oracle_source_database -t $oracle_target_database -f $ora_pfile -i $ora_spfile -m  $oracle_mount_prefix -n $number_of_mount

### Duplicate a PDB database to a CDB example
./duplicate-ora-coh-nfs.bash -b $oracle_source_server -s $oracle_source_database -t $oracle_target_database -f ${ora_pfile} -m  $oracle_mount_prefix -n $number_of_mount -c $oracle_pluggable_database

