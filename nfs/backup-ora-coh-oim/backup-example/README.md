## cohcdbb-incre.bash
This script does incremental backup of Oracle database cohcdbb. It does full backup when running the first time. After that it is incremental backup and  a full 
backup is built since it uses Oracle incremental merge. It can be scheduled to run a day or few times a day. Oracle database cohcdbb is a CDB database running on 
a single server.

## cohcdbb-log.bash
This script backs up Oracle archive log of Oracle database cohcdbb. It can be scheduled based on RPO requirement.

## cohcdbb-full.bash
THis script does full backup. It can be used when there is a need to start a new full.

## cohraca-incre.bash
This script does incremental backup of Oracle database cohcdbb. It does full backup when running the first time. After that it is incremental backup and  a full 
backup is built since it uses Oracle incremental merge. It can be scheduled to run a day or few times a day. Oracle database cohraca is a RAC database running on 
a three-nodes RAC cluster
