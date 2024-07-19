
## w2sigb-restore-validate.bash
This script will only restore Oracle database datafiles to /dev/null. It can test the restore performance from the backup appliance without overwrite the existing database

- curl -O https://raw.githubusercontent.com/diana-hui-yang/cohesity-scripts/master/oracle/sbt/restore-ora-coh-sbt/restore-example/w2sigb-restore-validate.bash
- chmod 750 w2sigb-restore-validate.bash

## w2sigb-recover-database.bash
This script will restore database datafiles and recover database. It assumes controlfiles are intact. It wil overwrite the original database datafiles.

- curl -O https://raw.githubusercontent.com/diana-hui-yang/cohesity-scripts/master/oracle/sbt/restore-ora-coh-sbt/restore-example/w2sigb-recover-database.bash
- chmod 750 w2sigb-recover-database.bash

## w2sigb-recover-controlfile-database.bash
THis script will restore controlfile, database datafiles and recover database. It wil overwrite the original database datafiles. This restore script was only tested
against none CDB/PDB database.

- curl -O https://raw.githubusercontent.com/diana-hui-yang/cohesity-scripts/master/oracle/sbt/restore-ora-coh-sbt/restore-example/w2sigb-recover-controlfile-database.bash
- chmod 750 w2sigb-recover-controlfile-database.bash
