## Download the script

- curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/nfs/nfs-mount/nfs-mount.bash
- chmod 750 nfs-mount.bash

## NFS mount script Description
### nfs-mount script parameter

- -f: The file lists Cohesity Cluster VIPs
- -v: Cohesity View that is configured to be the target for Oracle backup
- -m: Mount prefix (for example: if the mount is /coh/ora1, the prefix is /coh/ora)

## VIP file content example
- 10.19.2.6
- 10.19.2.7
- 10.19.2.8
- 10.19.2.9

## nfs-mount.bash exmaple (requires root privilege)
./nfs-mount.bash -f vip-list  -v ora -m /coh/ora
