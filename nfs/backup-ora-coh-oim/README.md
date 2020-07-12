Download the script
- curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/nfs/backup-ora-coh-oim/backup-ora-coh-oim.bash
- chmod 750 backup-ora-coh-oim.bash

## Backup scripts Description

The backup scripts can utilize mutiple mount points to backup Oracle databases. backuo-ora-coh-oim.bash uses Oracle incremental merge. backuo-ora-coh-oim.bash should be used with Cohesity snapshot feature as a complete backup solution. 
It supports full, incremental, and archive logs backup options. It also supports recvoery catalog.

When run the script without any options, it displays the script usage

backup-ora-coh-oim.bash Basic parameter

- -o: Oracle instance
- -m: Mount prefix (for example: if the mount is /coh/ora1, the prefix is /coh/ora)
- -n: number of mounts (If this number is 3, mount point /coh/ora1, /coh/ora2, /coh/ora3 wil be used as Oracle backup target)
- -p: Number of Oracle channels
- -a: Archive only or not
- -t: If not archive only, it is full or incremental backup.
- -e: Backup retention

## backup-ora-coh-oim.bash Backup Example
### Full backup example
./backup-ora-coh-oim.bash -o orcl -a no -t full -m /coh/ora -n 4 -p 6 -e 3

### Cumulative backup example
./backup-ora-coh-oim.bash -o orcl -a no -t incre -m /coh/ora -n 4 -p 3 -e 3

### Archive log backup example
./backup-ora-coh-oim.bash -o orcl -a yes -m /coh/ora -n 4 -p 2 -e 3
