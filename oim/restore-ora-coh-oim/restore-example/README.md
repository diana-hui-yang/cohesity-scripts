## cohcdbb-restore-validate.bash
This script will only restore Oracle database datafiles to /dev/null. It can test the restore performance from the backup appliance without overwrite the existing database

- curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/sbt/restore-ora-coh-sbt/restore-example/cohcdbb-restore-validate.bash
- chmod 750 cohcdbb-restore-validate.bash

## cohcdbb-recover-database.bash
This script will restore database datafiles and recover database. It assumes controlfiles are intact. It wil overwrite the original database datafiles.

- curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/sbt/restore-ora-coh-sbt/restore-example/cohcdbb-recover-database.bash
- chmod 750 cohcdbb-recover-database.bash

## cohcdbb-recover-controlfile-database.bash
This script will restore controlfile, database datafiles and recover database. It wil overwrite the original database datafiles. 

- curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/sbt/restore-ora-coh-sbt/restore-example/cohcdbb-recover-controlfile-database.bash
- chmod 750 cohcdbb-recover-controlfile-database.bash
