## Download the script
- curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/oracle/nfs/list-del-ora-agedfile/linux/list-del-ora-agedfile.bash
- chmod 750 list-del-ora-agedfile.bash

## Description
When run the script without any options, it displays the script usage

Parameters

- -h : host (optional)
- -a : yes/no (yes means all databases, no means individual database)
- -s : Search pattern
- -d : Backup Files Directory, NFS mount from Cohesity
- -r : specified day
- -f : yes/no (yes means expired files will be deleted, no means list only)

The -r (The specified day) input should be RMAN retention policy plus days between two full backup. For example if RMAN retenton is 14 days, and DBA runs full
backup on weekend and incremental on week day, the -r input should be 21 days. 
