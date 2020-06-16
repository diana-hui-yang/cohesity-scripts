# Cohesity Oracle Backup Sample Script using NFS

Warning: this code is provided on a best effort basis and is not in any way officially supported or sanctioned by Cohesity. The code in this repository is provided as-is and the author accepts no liability for damages resulting from its use.

## Download the script

- curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/nfs/backup-ora-coh-nfs.bash
- curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/nfs/backup-ora-coh-oim.bash
- curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/nfs/nfs-mount.bash
- chmod 750 backup-ora-coh-nfs.bash
- chmod 750 backup-ora-coh-oim.bash
- chmod 750 nfs-mount.bash

## Description

The backup scripts can utilize mutiple mount points to backup Oracle databases. backup-ora-coh-nfs.bash script uses Oracle backupset and  backuo-ora-coh-oim.bash uses Oracle incremental merge. backuo-ora-coh-oim.bash should be used with Cohesity snapshot feature as a complete backup solution. 
Both support full, incremental, and archive logs backup options. They also supports recvoery catalog.

When run the script without any options, it displays the script usage

backup-ora-coh-nfs.bash Basic parameter
- -o: Oracle instance
- -m: Mount prefix (for example: if the mount is /coh/ora1, the prefix is /coh/ora)
- -n: number of mounts (If this number is 3, mount point /coh/ora1, /coh/ora2, /coh/ora3 wil be used as Oracle backup target)
- -p: Number of Oracle channels
- -a: Archive only or not
- -i: If not archive only, it is full or incremental backup. 0 is full backup, and 1 is cumulative incremental backup
- -e: Backup retention

backup-ora-coh-oim.bash Basic parameter
- -o: Oracle instance
- -m: Mount prefix (for example: if the mount is /coh/ora1, the prefix is /coh/ora)
- -n: number of mounts (If this number is 3, mount point /coh/ora1, /coh/ora2, /coh/ora3 wil be used as Oracle backup target)
- -p: Number of Oracle channels
- -a: Archive only or not
- -t: If not archive only, it is full or incremental backup. 
- -e: Backup retention

## backup-ora-coh-nfs.bash Backup Example
### Full backup example
./backup-ora-coh-nfs.bash -o orcl -a no -i 0 -m /coh/ora -n 4 -p 6 -e 30
### Cumulative backup example
./backup-ora-coh-nfs.bash -o orcl -a no -i 1 -m /coh/ora -n 4 -p 3 -e 30
### Archive log backup example
./backup-ora-coh-nfs.bash -o orcl -a yes -m /coh/ora -n 4 -p 2 -e 30


## backup-ora-coh-oim.bash Backup Example
### Full backup example
./backup-ora-coh-oim.bash -o orcl -a no -t full -m /coh/ora -n 4 -p 6 -e 3
### Cumulative backup example
./backup-ora-coh-oim.bash -o orcl -a no -t incre -m /coh/ora -n 4 -p 3 -e 3
### Archive log backup example
./backup-ora-coh-oim.bash -o orcl -a yes -m /coh/ora -n 4 -p 2 -e 3


