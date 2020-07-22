# Cohesity Oracle Backup Sample Script using NFS

Warning: this code is provided on a best effort basis and is not in any way officially supported or sanctioned by Cohesity. The code in this repository is provided as-is and the author accepts no liability for damages resulting from its use.

## Download the script

- curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/nfs/backup-ora-coh-nfs/backup-ora-coh-nfs.bash
- curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/nfs/backup-ora-coh-oim/backup-ora-coh-oim.bash
- curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/nfs/duplicate-ora-coh-oim/duplicate-ora-coh-oim.bash
- curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/nfs/nfs-mount/nfs-mount.bash
- curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/nfs/prepare-restore/prepare-restore.bash
- chmod 750 backup-ora-coh-nfs.bash
- chmod 750 backup-ora-coh-oim.bash
- chmod 750 deduplicate-ora-coh-oim.bash
- chmod 750 nfs-mount.bash
- chmod 750 prepare-restore.bash

## Download OIM installation script
This script will download all RMAN shell scripts and Cohesity Python scripts that are necessary to do Oracle Incremental Merge backup and restore. 
- cd <script directory>
- curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/nfs/oim-download.bash
- chmod 750 oim-download.bash
