# Cohesity DB2 backup Sample Script using NFS

Warning: this code is provided on a best effort basis and is not in any way officially supported or sanctioned by Cohesity. The code in this repository is provided as-is and the author accepts no liability for damages resulting from its use.

## Download the script

- curl -O https://raw.githubusercontent.com/diana-hui-yang/cohesity-scripts/master/db2/backup-db2-coh-nfs/linux/backup-db2-coh-nfs.bash
- /opt/freeware/bin/curl -O https://raw.githubusercontent.com/diana-hui-yang/cohesity-scripts/master/db2/backup-db2-coh-nfs/aix/aix-backup-db2-coh-nfs.bash
- chmod 750 backup-db2-coh-nfs.bash
- chmod 750 aix-backup-db2-coh-nfs.bash

## Export script Description
The scripts in this folder can utilize mutiple mount points to backup DB2 databases to NFS mounts. It has the following assumption
- The last charactor of the mount should be a numerical digit. 
- The last charactor of the first mount should be 1
- The last charactor of the rest of mounts should be increased 1 by 1
