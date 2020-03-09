# Cohesity Oracle Backup Sample Script using NFS

Warning: this code is provided on a best effort basis and is not in any way officially supported or sanctioned by Cohesity. The code in this repository is provided as-is and the author accepts no liability for damages resulting from its use.

## Download the script

- curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/backup-ora-coh-nfs.bash
- chmod 750 backup-ora-coh-nfs.bash

## Description

The scripts can utilize mutiple mount points to backup Oracle databases. The backup format is backupset.
backup-ora-coh-nfs.bash have full, incremental, and archive logs backup options. It also supports recvoery catalog.

When run the script without any options, it displays the script usage

Basic parameter
- -o: Oracle instance
- -m: Mount prefix (for example: if the mount is /coh/ora1, the prefix is /coh/ora)
- -n: number of mounts (If this number is 3, mount point /coh/ora1, /coh/ora2, /coh/ora3 wil be used as Oracle backup target)
- -p: Number of Oracle channels
- -a: Archive only or not
- -i: If not archive only, it is full or incremental backup. 0 is full backup, and 1 is cumulative incremental backup
