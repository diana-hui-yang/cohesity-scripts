#!/bin/bash

targetconnect="<user>/<passwd>@oracle-01/cohcdbr1"
prod_host=oracle-01
source_db=cohcdbr1
source_pdb=cohpdbr1
target_oraclesid=cohcdbc
ora_set1=/home/oracle1/scripts/nfs/dup-set1-cohcdbr2.ora

echo start Oracle duplication
/home/oracle1/scripts/nfs/rman/duplicate-ora-coh-nfs.bash -b ${prod_host} -d ${source_db} -t ${target_oraclesid} -c ${source_pdb} -l ${ora_set1} -m /coh/oraoim -n 4
