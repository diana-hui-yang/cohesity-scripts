Warning: this code is provided on a best effort basis and is not in any way officially supported or sanctioned by Cohesity. The code in this repository is provided as-is and the author accepts no liability for damages resulting from its use.

# Download the script
curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/backup-ora-all.bash

curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/backup-ora-arch.bash

curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/backup-ora-full.bash

# rman-cohesity

The scripts can utilize mutiple mount points to backup Oracle databases. 

backup-ora-full.bash does full backup only. 
backup-ora-arch.bash does archive logs backup.
backup-ora-all.bash have full, incremental, and archive logs backup options. It also supports recvoery catalog.

When run the script without any options, it displays the script usage

# Basic parameter
-o: oracle instance

-m: Mount prefix

-n: number of mounts 
