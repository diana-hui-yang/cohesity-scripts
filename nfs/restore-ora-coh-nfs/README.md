## Download the script
- curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/nfs/restore-ora-coh-nfs/linux/restore-ora-coh-nfs.bash
- /opt/freeware/bin/curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/nfs/restore-ora-coh-nfs/aix/aix-restore-ora-coh-nfs.bash
- curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/nfs/restore-ora-coh-nfs/sun/sun-restore-ora-coh-nfs.bash
- chmod 750 restore-ora-coh-nfs.bash
- chmod 750 aix-restore-ora-coh-nfs.bash
- chmod 750 sun-restore-ora-coh-nfs.bash

## Description
This bash script utilize RMAN restore/recover command to restore a database from the backup taken by using backup-ora-coh-nfs.bash script/backup-ora-coh-oim.bash if it is Oracle database on Linix or sbackup-ora-coh-nfs.bash script/sbackup-ora-coh-oim.bash if it is Oracle database on Solaris. When using point-in-time like "2020-08-23 11:30:00', it is the timezone on the source server, not the target server if there is a timezone difference. 

