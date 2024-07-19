## Download the script
- curl -O https://raw.githubusercontent.com/diana-hui-yang/cohesity-scripts/master/oracle/cohesityadapter/create-standby/linux/create-standby-cohesityadapter.bash
- chmod 750 create-standby-cohesityadapter.bash

## Description
This script will instantiate an Oracle Data Guard Physical Standby from a Cohesity backup. A Cohesity Oracle recovery view needs to be created first. When running the script without any options, it displays the script usage. When using the "-w yes" parameter, the script builds a softlink of backup files in NFS mounts of the Cohesity view to a single directory under /tmp/orarestore and creates RMAN commands without executing them.

Required parameters

- -i : Standby instance name
- -d : Oracle_DB_Name (database backup was taken). It is DB name, not instance name
- -m : mount-prefix (like /coh/ora)
- -n : number of mounts
 
 Optional Parameters
- -p : number of channels (Optional, default is same as the number of mounts4)
- -o : ORACLE_HOME (Optional, default is current environment)
- -f : yes means force. It will refresh the target database without prompt
- -s : yes mean Oracle duplicate use noresume, default is no
- -w : yes means preview rman duplicate scripts
