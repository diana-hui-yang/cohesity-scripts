# Cohesity Sybase dump Sample Script using NFS

Warning: this code is provided on a best effort basis and is not in any way officially supported or sanctioned by Cohesity. The code in this repository is provided as-is and the author accepts no liability for damages resulting from its use.

## Download the script

- curl -O https://raw.githubusercontent.com/diana-hui-yang/cohesity-scripts/master/sybase/dump-sybase-coh-nfs/linux/dump-sybase-coh-nfs.bash
- curl -O https://raw.githubusercontent.com/diana-hui-yang/cohesity-scripts/master/sybase/dump-sybase-coh-nfs/aix/aix-dump-sybase-coh-nfs.bash
- chmod 750 dump-sybase-coh-nfs.bash
- chmod 750 aix-dump-sybase-coh-nfs.bash

## Export script Description
The scripts in this folder can utilize mutiple mount points to dump Sybase databases to NFS mounts. It has the following assumption
- The last charactor of the mount should be a numerical digit. 
- The last charactor of the first mount should be 1
- The last charactor of the rest of mounts should be increased 1 by 1
