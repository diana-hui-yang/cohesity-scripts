## Download the script
- curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/sbt/backup-ora-coh-sbt/linux/backup-ora-coh-sbt.bash
- chmod 750 backup-ora-coh-dedup.bash
- curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/sbt/backup-ora-coh-sbt/aix/aix-backup-ora-coh-sbt.bash
- chmod 750 backup-ora-coh-dedup.bash

## Description
The scripts uses Cohesity Source-side dedup library to backup Oracle databases. The backup format is backupset. backup-ora-coh-dedup.bash has full, incremental, and archive logs backup options. Cohesity Remote adapter will run Cohesity snapshot after the backup is done. The script can be launched from a central server and also supports recvoery catalog. 

