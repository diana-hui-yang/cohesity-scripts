## Download the script
- curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/sbt/restore-ora-coh-sbt/linux/restore-ora-coh-sbt.bash
- /opt/freeware/bin/curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/sbt/restore-ora-coh-sbt/aix/aix-restore-ora-coh-sbt.bash
- chmod 750 restore-ora-coh-sbt.bash
- chmod 750 aix-restore-ora-coh-sbt.bash

## Description
This bash script utilize RMAN restore/recover command to restore a database from the backup taken by using backup-ora-coh-sbt.bash script if it is Oracle database on Linix or aix-backup-ora-coh-sbt.bash scriptif it is Oracle database on AIX. When using point-in-time like "2020-08-23 11:30:00', it is the timezone on the source server, not the target server if there is a timezone difference. 

