#!/bin/bash

#catalogconnect="<user>/<passwd>@orawest:/catalog"
targetconnect="<user>/<passwd>@oracle-01/cohcdbr1"
prod_host=oracle-01
source_db=cohcdbr1
source_pdb=cohpdbr2
target_oraclesid=cohcdbc
view=ora_sbt/orawest2/cohcdbr1
cohesity_name="sac01-ftdcoh"


echo start Oracle duplication
/home/oracle1/scripts/sbt/rman/duplicate-ora-coh-sbt.bash -r "${targetconnect}" -y "${cohesity_name}" -b ${prod_host} -d ${source_db} -t ${target_oraclesid} -v $view -c $source_pdb
