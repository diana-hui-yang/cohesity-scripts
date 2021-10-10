#!/bin/bash

targetconnect="<user>/<passwd>@oracle-01/cohcdbr1"
prod_host=oracle-01
source_db=cohcdbr1
target_oraclesid=cohcdbr3
view=ora_sbt/orawest2/cohcdbr1
ora_set=/home/oracle1/scripts/sbt/dup-set1-cohcdbr3.ora
cohesity_name="sac01-ftdcoh"
#catalogconnect="rman/fr8shst8rt@orawest:/catalog"

echo start Oracle duplication
/home/oracle1/scripts/sbt/rman/duplicate-ora-coh-sbt.bash -r "${targetconnect}" -y "${cohesity_name}" -b ${prod_host} -d ${source_db} -t ${target_oraclesid} -l ${ora_set} -v $view
