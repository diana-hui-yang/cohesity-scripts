## w2sigb-full.bash
This script will do full backup and run Cohesity snapshot after the backup. Remove Cohesity snapshot job in this script when using Cohesity remote adapter

- curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/sbt/backup-ora-coh-sbt/backup-example/w2sigb-full.bash
- chmod 750 w2sigb-full.bash

## w2sigb-log.bash
This script will do archive log backup run Cohesity snapshot after the backup. Remove Cohesity snapshot job in this script when using Cohesity remote adapter

- curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/sbt/backup-ora-coh-sbt/backup-example/w2sigb-log.bash
- chmod 750 w2sigb-log.bash

## oraracb-rac-full.bash
This script will do full backup to directory "orascan1/oraracb" directory under view "orasbt1" and run Cohesity snapshot after the backup. Remove Cohesity snapshot job in this script when using Cohesity remote adapter

- curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/sbt/backup-ora-coh-sbt/backup-example/oraracb-rac-full.bash
- chmod 750 oraracb-rac-full.bash

## oraracb-rac-log.bash
This script will do archive log backup to directory "orascan1/oraracb" directory under view "orasbt1" run Cohesity snapshot after the backup. Remove Cohesity snapshot job in this script when using Cohesity remote adapter

- curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/sbt/backup-ora-coh-sbt/backup-example/oraracb-rac-log.bash
- chmod 750 oraracb-rac-log.bash
