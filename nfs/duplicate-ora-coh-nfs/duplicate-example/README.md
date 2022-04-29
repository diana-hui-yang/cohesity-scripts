When duplicating a database to a new database especially on the same server, the database files locations need to be changed. Please reference Oracle document to set up the correct parameter in pfile (like DB_FILE_NAME_CONVERT and LOG_FILE_NAME_CONVERT for none OMF or db_recovery_file_dest for OMF)
https://docs.oracle.com/database/121/BRADV/rcmdupad.htm#BRADV99994

## dup-cohcdbr1-cohcdbr2.bash
This script will duplicate database cohcdbr1 to database cohcdbr3.

- curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/nfs/duplicate-ora-coh-nfs/duplicate-example/dup-cohcdbr1-cohcdbr3.bash
- chmod 750 dup-cohcdbr1-cohcdbr3.bash

## dup-cohcdbr1-cohcdbc-cohpdbr1.bash
THis script duplicate pluggable database cohpdbr1 from CDB database cohcdbr1 to a CDB database cohcdbr2

- curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/nfs/duplicate-ora-coh-nfs/duplicate-example/dup-cohcdbr1-cohcdbc-cohpdbr1.bash
- chmod 750 dup-cohcdbr1-cohcdbc-cohpdbr1.bash
