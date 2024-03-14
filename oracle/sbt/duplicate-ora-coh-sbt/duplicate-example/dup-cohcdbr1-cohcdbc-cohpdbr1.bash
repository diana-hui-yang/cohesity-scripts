#!/bin/bash

#catalogconnect="<user>/<passwd>@orawest:/catalog"
targetconnect="<user>/<passwd>@oracle-01/cohcdbr1"
source_host=oracle-01
source_pdb=cohpdbr2
target_oraclesid=cohcdbc
view=ora_sbt
cohesity_name="sac01-ftdcoh"


echo start Oracle duplication
/home/oracle1/scripts/sbt/rman/duplicate-ora-coh-sbt.bash -r "${targetconnect}" -y "${cohesity_name}" -h ${source_host} -i ${target_oraclesid} -v $view -t "2023-04-21 13:00:00" -c $source_pdb
