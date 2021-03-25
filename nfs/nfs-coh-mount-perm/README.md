## Download the script

- curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/nfs/nfs-coh-mount-perm/nfs-coh-mount-perm.bash
- chmod 750 nfs-coh-mount-perm.bash

## NFS mount script Description
### nfs-mount script parameter

- -y: Cohesity Cluster DNS name
- -v: Cohesity View that is configured to be the target for Oracle backup
- -p: Mount prefix (for example: if the mount is /coh/ora1, the prefix is /coh/ora)
- -n: number of mounts

## nfs-coh-mount-perm.bash exmaple (requires root privilege)
./nfs-coh-mount-perm.bash -y cohesity1  -v ora -p /coh/ora -n 4
