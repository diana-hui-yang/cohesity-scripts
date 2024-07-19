## Download the script
- curl -O https://raw.githubusercontent.com/diana-hui-yang/cohesity-scripts/master/oracle/granular/import-tablespace/import-tablespace.bash
- chmod 750 import-tablespace.bash

## Description
When run the script without any options, it displays the script usage

Required parameters

- -o : Oracle instance name. If it is not RAC, it is the same as DB name. If it is RAC, it is the instance name like cohcdba2. It is a CDB not PDB
- -t : Oracle tablespace name.
- -c : Oracle instance that has the tablespace. If it is not RAC, it is the same as DB name. If it is RAC, it is the instance name like cohcdbb2. It is a CDB not PDB
- -d : A local directory or NFS mount point from Cohesity view (like /opt/cohesity/mount_paths/nfs_oracle_mounts/oratestview/oracle_35135289_8258227_path0)

 
Optional parameters
- -p : PDB database name. If this database is a root of a CDB database, enter root. Assume the PDB database name is the same on Oracle instance and clone database instance
- -b : ORACLE_HOME (Optional, default is current environment)
- -w : yes means preview rman backup scripts

