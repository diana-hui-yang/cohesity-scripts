#!/bin/bash

targetconnect="<user>/<passwd>@oracle-01/cohcdbr1"
source_host=oracle-01
source_db=cohcdbr1
target_oraclesid=cohcdbr2
ora_set1=/home/oracle1/scripts/nfs/dup-set1-cohcdbr2.ora

echo start Oracle duplication
/home/oracle1/scripts/nfs/rman/duplicate-ora-coh-nfs.bash -i ${target_oraclesid} -r ${targetconnect} -h ${source_host} -d ${source_db} -b ${ora_set1} -t "2022-04-01 12:30:00" -m /coh/oraoim -n 4
