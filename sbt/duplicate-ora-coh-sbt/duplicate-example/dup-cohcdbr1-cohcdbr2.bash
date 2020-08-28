#!/bin/bash

rmanlogin="rman auxiliary / target <user>/<passwd>@<oracle connection string>"
prod_host=oracle-01
source_db=cohcdbr1
target_oraclesid=cohcdbr2
vip_file=/home/oracle1/scripts/sbt/vip-list
view=ora_sbt
sbt_code=/u01/app/cohesity
ora_set=/home/oracle/scripts/sbt/dup-set-cohcdbr2.ora


echo start Oracle duplication
/home/oracle/scripts/sbt/rman/duplicate-ora-coh-sbt.bash -r "${rmanlogin}" -b ${prod_host} -d ${source_db} -t ${target_oraclesid} -f ${ora_set} -j $vip_file -v $view -s $sbt_code
