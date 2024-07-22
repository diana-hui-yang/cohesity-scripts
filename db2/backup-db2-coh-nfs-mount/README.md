### ***Warning: this code is provided on a best effort basis and is not in any way officially supported or sanctioned by Cohesity. The code in this repository is provided as-is and the author accepts no liability for damages resulting from its use.***

# Cohesity DB2 backup Sample Script using NFS

Warning: this code is provided on a best effort basis and is not in any way officially supported or sanctioned by Cohesity. The code in this repository is provided as-is and the author accepts no liability for damages resulting from its use.

## Download the script

- curl -O https://raw.githubusercontent.com/diana-hui-yang/cohesity-scripts/master/db2/backup-db2-coh-nfs-mount/linux/backup-db2-coh-nfs-mount.bash
- /opt/freeware/bin/curl -O https://github.com/diana-hui-yang/cohesity-scripts/blob/master/db2/backup-db2-coh-nfs-mount/aix/backup-db2-coh-nfs-mount.bash
- chmod 750 backup-db2-coh-nfs-mount.bash
- chmod 750 aix-backup-db2-coh-nfs-mount.ksh

## Backup  script Description

The scripts in this folder can utilize mutiple mount points to backup DB2 databases to NFS mounts. It has the following assumption
- The last charactor of the mount should be a numerical digit. 
- The last charactor of the first mount should be 1
- The last charactor of the rest of mounts should be increased 1 by 1

The backup scripts mount multiple Cohesity NFS shares before backing up DB2 databases. They umount the NFS shares after the backup is done and when there is no DB2 backup scripts are running. It requires DB2 user to have mount and umount root privilege by adding the following line in /etc/sudoers file

### Linux option
- db2inst1 ALL=(ALL) NOPASSWD:/bin/mount,/bin/umount,/bin/mkdir,/bin/chown

### AIX option
- db2inst1 ALL=(ALL) NOPASSWD:/usr/sbin/mount,/usr/sbin/umount,/usr/bin/mkdir,/usr/bin/chown
