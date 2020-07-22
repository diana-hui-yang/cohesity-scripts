## cohcdbb-incre.bash
This script does incremental backup of Oracle database cohcdbb. It does full backup when running the first time. After that it is incremental backup and  a full 
backup is built since it uses Oracle incremental merge. It can be scheduled to run a day or few times a day. Oracle database cohcdbb is a CDB database running on 
a single server.

- curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/nfs/backup-ora-coh-oim/backup-example/cohcdbb-incre.bash
- chmod 750 cohcdbb-incre.bash

## cohcdbb-log.bash
This script backs up Oracle archive log of Oracle database cohcdbb. It can be scheduled based on RPO requirement.

- curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/nfs/backup-ora-coh-oim/backup-example/cohcdbb-log.bash
- chmod 750 cohcdbb-log.bash

## cohcdbb-full.bash
THis script does full backup. It can be used when there is a need to start a new full.

- curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/nfs/backup-ora-coh-oim/backup-example/cohcdbb-full.bash
- chmod 750 cohcdbb-full.bash

## cohraca-incre.bash
This script does incremental backup of Oracle database cohcdbb. It does full backup when running the first time. After that it is incremental backup and  a full 
backup is built since it uses Oracle incremental merge. It can be scheduled to run a day or few times a day. Oracle database cohraca is a RAC database running on 
a three-nodes RAC cluster

- curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/nfs/backup-ora-coh-oim/backup-example/cohraca-incre.bash
- chmod 750 cohraca-incre.bash
