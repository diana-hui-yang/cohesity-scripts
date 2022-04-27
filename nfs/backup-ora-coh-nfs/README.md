
## Download the script

- curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/nfs/backup-ora-coh-nfs/linux/backup-ora-coh-nfs.bash
- curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/nfs/backup-ora-coh-nfs/solaris/sbackup-ora-coh-nfs.bash
- curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/nfs/backup-ora-coh-nfs/aix/aix-backup-ora-coh-nfs.bash
- chmod 750 backup-ora-coh-nfs.bash
- chmod 750 sbackup-ora-coh-nfs.bash
- chmod 750 aix-backup-ora-coh-nfs.bash

## Backup scripts Description

Both backup-ora-coh-nfs.bash and sbackup-ora-coh-nfs.bash can utilize mutiple mount points to backup Oracle databases. The backup files are in Oracle backupset format.
It supports full, incremental, and archive logs backup options. It also supports recvoery catalog. backup-ora-coh-nfs.bash supports Linux and sbackup-ora-coh-nfs.bash supports Solaris. 
