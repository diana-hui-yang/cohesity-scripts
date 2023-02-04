### ***Warning: this code is provided on a best effort basis and is not in any way officially supported or sanctioned by Cohesity. The code in this repository is provided as-is and the author accepts no liability for damages resulting from its use.***

## Download the script
- curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/nfs/restore-ora-coh-nfs/linux/restore-ora-coh-nfs.bash
- /opt/freeware/bin/curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/nfs/restore-ora-coh-nfs/aix/aix-restore-ora-coh-nfs.bash
- curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/nfs/restore-ora-coh-nfs/sun/sun-restore-ora-coh-nfs.bash
- chmod 750 restore-ora-coh-nfs.bash
- chmod 750 aix-restore-ora-coh-nfs.bash
- chmod 750 sun-restore-ora-coh-nfs.bash

## Description
This bash script utilize RMAN restore/recover command to restore a database from the backup taken by using backup-ora-coh-nfs.bash/backup-ora-coh-oim.bash on Linux ,sbackup-ora-coh-nfs.bash/sbackup-ora-coh-oim.bash on Solaris, or aix-backup-ora-coh-nfs.bash/aix-backup-ora-oim.bash on AIX.. When using point-in-time like "2020-08-23 11:30:00', it is the timezone on the source server, not the target server if there is a timezone difference. 

