## Download the script
- curl -O https://raw.githubusercontent.com/diana-hui-yang/cohesity-scripts/master/oracle/granular/restore-datafile/restore-datafile.bash
- chmod 750 restore-datafile.bash

## Description
When run the script without any options, it displays the script usage

Required parameters

- -o : Oracle instance name. If it is not RAC, it is the same as DB name. If it is RAC, it is the instance name like cohcdba2. It is a CDB not PDB
- -f : Oracle datafile name or id.

 
Optional parameters
- -m : NFS mount point created by Cohesity (like /opt/cohesity/mount_paths/nfs_oracle_mounts/oratestview/oracle_35135289_8258227_path0)
- -b : ORACLE_HOME (Optional, default is current environment)
- -w : yes means preview rman backup scripts
