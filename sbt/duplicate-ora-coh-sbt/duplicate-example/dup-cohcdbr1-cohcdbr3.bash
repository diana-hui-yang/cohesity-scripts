#!/bin/bash

targetconnect="<user>/<passwd>@oracle-01/cohcdbr1"
source_host=oracle-01
target_oraclesid=cohcdbr3
view=ora_sbt/orawest2/cohcdbr1
cohesity_name="sac01-ftdcoh"
#catalogconnect="rman/fr8shst8rt@orawest:/catalog"

echo start Oracle duplication
/home/oracle1/scripts/sbt/rman/duplicate-ora-coh-sbt.bash -r "${targetconnect}" -y "${cohesity_name}" -h ${source_host} -i ${target_oraclesid} -v $view -t "2023-04-21 13:00:00"
