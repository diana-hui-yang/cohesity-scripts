### ***Warning: this code is provided on a best effort basis and is not in any way officially supported or sanctioned by Cohesity. The code in this repository is provided as-is and the author accepts no liability for damages resulting from its use.***

## Backup scripts Description

The backup scripts mount multiple Cohesity NFS shares before backing up Oracle databases. They umount the NFS shares after the backup is done and when there is RMAN backup scripts are running. It requires Oracle user to have mount and umount root privilege by adding the following line in /etc/sudoers file

- oracle1 ALL=(ALL) NOPASSWD:/bin/mount,/bin/umount,/bin/mkdir,/bin/chown

The backup files are in Oracle backupset format. It supports full, incremental, and archive logs backup options. It also supports recvoery catalog.

