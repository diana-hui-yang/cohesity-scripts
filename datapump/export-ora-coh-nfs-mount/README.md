# Cohesity Oracle export Sample Script using NFS

Warning: this code is provided on a best effort basis and is not in any way officially supported or sanctioned by Cohesity. The code in this repository is provided as-is and the author accepts no liability for damages resulting from its use.

## Download the script

- curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/datapump/export-ora-coh-nfs-mount/linux/export-ora-coh-nfs-mount.bash
- curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/nfs/nfs-coh-mount-perm/nfs-coh-mount-perm.bash
- curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/nfs/nfs-coh-mount-umount/linux/nfs-coh-mount-umount.bash
- chmod 750 export-ora-coh-nfs-mount.bash

## Export script Description
The export script mounts multiple Cohesity NFS shares before exporting Oracle databases. It umounts the NFS shares after the backup is done and when there aren't any other export scripts are running. It requires Oracle user to have mount and umount root privilege by adding the following line in /etc/sudoers file

oracle1 ALL=(ALL) NOPASSWD:/bin/mount,/bin/umount,/bin/mkdir,/bin/chown
