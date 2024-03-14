#!/bin/bash

targetconnect="<user>/<passwd>@oracle-01/cohcdbr1"
source_host=oracle-01
source_db=cohcdbr1
source_pdb=cohpdbr1
target_oraclesid=cohcdbc

echo start Oracle duplication
/home/oracle1/scripts/nfs/rman/duplicate-ora-coh-nfs.bash -i ${target_oraclesid} -h ${source_host} -d ${source_db} -u ${source_pdb} -t "2022-04-01 12:30:00"  -m /coh/oraoim -n 4
