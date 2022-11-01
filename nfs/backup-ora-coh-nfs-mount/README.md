## Download the script

- curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/nfs/backup-ora-coh-nfs-mount/linux/backup-ora-coh-nfs-mount.bash
- chmod 750 backup-ora-coh-nfs-mount.bash

## Backup scripts Description

The backup scripts mount multiple Cohesity NFS shares before backing up Oracle databases. They umount the NFS shares after the backup is done and when there is RMAN backup scripts are running. It requires Oracle user to have mount and umount root privilege by adding the following line in /etc/sudoers file

- oracle1 ALL=(ALL) NOPASSWD:/bin/mount,/bin/umount,/bin/mkdir,/bin/chown

The backup files are in Oracle backupset format. It supports full, incremental, and archive logs backup options. It also supports recvoery catalog.

