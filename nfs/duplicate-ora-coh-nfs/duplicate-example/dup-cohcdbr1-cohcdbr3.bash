#!/bin/bash

source_host=oracle-01
source_db=cohcdbr1
target_oraclesid=cohcdbr3

echo start Oracle duplication
/home/oracle1/scripts/nfs/rman/duplicate-ora-coh-nfs.bash -i ${target_oraclesid} -h ${source_host} -d ${source_db} -t "2022-04-01 12:30:00" -m /coh/oraoim -n 4
