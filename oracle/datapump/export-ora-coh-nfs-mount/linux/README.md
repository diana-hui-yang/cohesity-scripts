## Download the script

- curl -O https://raw.githubusercontent.com/diana-hui-yang/cohesity-scripts/master/oracle/datapump/export-ora-coh-nfs-mount/linux/export-ora-coh-nfs-mount.bash
- chmod 750 export-ora-coh-nfs-mount.bash

## Export scripts Description
When run the script without any options, it displays the script usage

 Required Parameters
- -h : host (scanname is required if it is RAC. optional if it is standalone.)
- -o : ORACLE_DB_NAME (Need to have an entry of this database in /etc/oratab. If it is RAC, it is db_unique_name)
- -y : Cohesity Cluster DNS name
- -v : Cohesity View that is configured to be the target for Oracle export
- -m : mount-prefix (like /mnt/ora)
- -e : Retention time (days to retain the exports)


 Optional Parameters
- -s : Sqlplus connection (example: "dbuser/dbpass@'database connection string'", optional if it is local)
- -d : ORACLE PDB database
- -n : number of mounts
- -p : number of parallel (Optional, default is 4)
- -a : yes means leave Cohesity NFS mount on server, default is umount all NFS mount after export is successful
- -x : ORACLE_HOME (default is /etc/oratab, optional.)
- -z : file size in GB (Optional, default is 58G)
- -c : Export option chosen by DBA. It can be table level or schema level. example "schemas=soe1" The default is full
- -w : yes means preview Oracle export scripts


## export-ora-coh-nfs-mount.bash Backup Example
### Full database export example
./export-ora-coh-nfs-mount.bash -o orcl -y cohesity-o1 -v ora -m /coh/ora -p 6 -e 30
### Create Full database export script only example
./export-ora-coh-nfs-mount.bash -o orcl -y cohesity-o1 -v ora -m /coh/ora -p 6 -e 30 -w yes


