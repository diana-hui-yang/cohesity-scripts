## Download the script

- curl -O https://raw.githubusercontent.com/diana-hui-yang/cohesity-scripts/master/db2/backup-db2-coh-nfs/linux/backup-db2-coh-nfs.bash
- chmod 750 backup-db2-coh-nfs.bash

## Backup scripts Description
When run the script without any options, it displays the script usage


 Required Parameters
- -d : database name
- -t : backup type. full means database backup full, incre means database backup incre
- -m : mount-prefix (like /coh/db2)
- -n : number of mounts 
- -e : Retention time (days to retain the backups)

 Optional Parameters
- -f : DB2 profile path. The default is /home/db2inst1/sqllib/db2profile
- -l : offline backup or online backup. off means offline backup. default is online backup
- -p : number of stripes
- -w : yes means preview db2 backup scripts



## backup-db2-coh-nfs.bash Backup Example
### Full database backup example
./backup-db2-coh-nfs.bash -d test -t full -m /coh/db2nfs -n 3 -p 6
### Incremental database backup example
./backup-db2-coh-nfs.bash -d test -t incre -m /coh/db2nfs -n 3 -p 6
