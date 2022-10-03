## Download the script

- /opt/freeware/bin/curl -O https://raw.githubusercontent.com/diana-hui-yang/cohesity-scripts/master/db2/backup-db2-coh-nfs-mount/aix/aix-backup-db2-coh-nfs-mount.bash
- chmod 750 aix-backup-db2-coh-nfs-mount.bash

## Backup scripts Description
When run the script without any options, it displays the script usage


 Required Parameters
- -d : database name
- -t : backup type. full means database backup full, incre means database backup full, log means transactional backup
- -y : Cohesity Cluster DNS name
- -v : Cohesity View that is configured to be the target for Oracle backup
- -m : mount-prefix (like /coh/db2)
- -n : number of mounts (only 1 is supported currently)
- -e : Retention time (days to retain the backups)

 Optional Parameters
- -l : offline backup or online backup. off means offline backup. default is online backup
- -p : number of stripes (Optional, only 1 is supported currently)
- -w : yes means preview db2 backup scripts



## aix-backup-db2-coh-nfs-mount.bash Backup Example
### Full database backup example
./aix-backup-db2-coh-nfs-mount.bash -d test -t full -y cohesity -v db2_nfs -m /coh/db2nfs -n 3 -p 6
### Incremental database backup example
./aix-backup-db2-coh-nfs-mount.bash -d test -t incre -y cohesity -v db2_nfs -m /coh/db2nfs -n 3 -p 6
