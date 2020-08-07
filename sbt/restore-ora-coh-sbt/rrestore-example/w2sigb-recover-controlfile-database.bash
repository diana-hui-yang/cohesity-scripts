#!/bin/bash

#this script will not use the orignal Cohesity view of Oracle backups. It will use a cloned view.

cohesity_user=oraadmin
cohesity_domain=sa.corp.cohesity.com
cohesity_cluster=10.19.2.70
cohesity_job="snap sbt"
original_view=ora_sbt
clone_view=ora_sbt_restore
oracle_instance=w2sigb
restore_controlfile=yes
vip_file=/home/oracle1/scripts/dedup/vip-list
view=ora_sbt_restore
sbt_code=/u01/app/cohesity
force=yes
point_in_time="2020-08-02 12:00:00"

# delete the cloned view
/home/oracle1/scripts/dedup/coh/deleteView.py -s $cohesity_cluster -u $cohesity_user -d $cohesity_domain -v ${clone_view}

sleep 5

# clone the view again
/home/oracle1/scripts/dedup/coh/cloneView.py -s $cohesity_cluster -u $cohesity_user -d $cohesity_domain -j "${cohesity_job}" -v ${original_view} -n
${clone_view} -w

sleep 5

# Oracle restore
/home/oracle1/scripts/dedup/rman/restore-ora-coh-dedup.bash -i $oracle_instance -t "${point_in_time}" -l $restore_controlfile -j $vip_file -v $view
-s $sbt_code -f $force

