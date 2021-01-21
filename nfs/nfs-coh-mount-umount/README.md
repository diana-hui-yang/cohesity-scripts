## Download the script

- curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/nfs/nfs-coh-mount-umount/nfs-coh-mount-umount.bash
- chmod 750 nfs-coh-mount-umount.bash

## NFS mount script Description
### nfs-mount script parameter

- -y: Cohesity Cluster DNS name
- -v: Cohesity View that is configured to be the target for Oracle backup
- -p: Mount prefix (for example: if the mount is /coh/ora1, the prefix is /coh/ora)
- -m : yes means mount Cohesity view, no means umount Cohesity view

## nfs-coh-mount-umount.bash mount exmaple (requires user has sudo privilege to mount the filesystem)
./nfs-coh-mount-umount.bash -y cohesity1  -v ora -p /coh/ora -m yes

## nfs-coh-mount-umount.bash umount exmaple (requires user has sudo privilege to umount the filesystem)
./nfs-coh-mount-umount.bash -y cohesity1  -v ora -p /coh/ora -m no
