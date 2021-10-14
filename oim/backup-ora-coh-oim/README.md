## Download the script
- curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/oim/backup-ora-coh-oim/linux/backup-ora-coh-oim.bash
- curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/oim/backup-ora-coh-oim/sun/sbackup-ora-coh-oim.bash
- chmod 750 backup-ora-coh-oim.bash
- chmod 750 sbackup-ora-coh-oim.bash

## prerequisite
- Download Brian Seltz's python scripts. These scripts are in https://github.com/diana-hui-yang/rman-cohesity/blob/master/oim/linux-oim-download.bash or https://github.com/diana-hui-yang/rman-cohesity/blob/master/oim/sun-oim-download.bash
- Run storePassword.py script before run Oracle backup script listed on this page. The syntax is on https://github.com/bseltz-cohesity/scripts/tree/master/python/storePassword
