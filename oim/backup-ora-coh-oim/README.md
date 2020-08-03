## Download the script
- curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/oim/backup-ora-coh-oim/backup-ora-coh-oim.bash
- chmod 750 backup-ora-coh-oim.bash

## Backup scripts Description

backuo-ora-coh-oim.bash can utilize mutiple mount points to backup Oracle databases. It uses Oracle incremental merge. The backup is incremental and the result is full backup after the merge. It should be used with Cohesity snapshot feature as a complete backup solution. Cohesity Remote adapter will run Cohesity snapshow after the backup is done. When using cron job to schedule the job, Cohesity python snapshot script should be used. It can be downloaded from this link https://github.com/bseltz-cohesity/scripts/tree/master/python/backupNow
This script supports full, incremental, and archive logs backup options. It also supports recvoery catalog.

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

### Incremental merge backup example (incremental backup and the result is full backup)
./backup-ora-coh-oim.bash -o orcl -a no -t incre -m /coh/ora -n 4 -p 3 -e 3

### Archive log backup example
./backup-ora-coh-oim.bash -o orcl -a yes -m /coh/ora -n 4 -p 2 -e 3

### Full backup example (only needed when forcing a new full)
./backup-ora-coh-oim.bash -o orcl -a no -t full -m /coh/ora -n 4 -p 6 -e 3

