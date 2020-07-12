## Download the script

- curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/nfs/duplicate-ora-coh-oim/duplicate-ora-coh-oim.bash
- chmod 750 deduplicate-ora-coh-oim.bash

## Oracle duplicate scripts Description
This Oracle duplicate script can duplicate Oracle database using the backup files backed up by **backup-ora-coh-oim.bash** script. It can duplicate Oracle database on the same server of the original Oracle database or an alternate server. It can duplicate CDB database or a PDB database to another CDB. **prepare-restore** script needs to run first before this script on an alternate server. **prepare-restore** mounts the view that has the backup data on Cohesity to the alternate server. 

When run the script without any options, it displays the script usage

duplicate-ora-coh-oim.bash basic parameter
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

### ora_file example (File contains duplicate settting)
set newname for database to "'/oradata/restore/cdb1res';"
set until time \"to_date("'2020-07-03 21:40:00','YYYY/MM/DD HH24:MI:SS'")\";

### ora_spfile example (File contains new setting to spfile)
Set db_unique_name='cdb1res'
set db_create_file_dest='/oradata/restore/cdb1res'

## duplicate-ora-coh-nfs.bash Backup Example
### Duplicate a traditional Oracle database or CDB database example
./duplicate-ora-coh-nfs.bash  -b oracle-01 -s cdb1 -t cdb1res -f ora_file -i ora_spfile -m  /coh/oraoim -n 4

### Duplicate a PDB database to a CDB example
./duplicate-ora-coh-nfs.bash -b oracle-01 -s cdb1 -t cdb2 -f ora_file -m  /coh/oraoim -n 4 -c cohpdb1

