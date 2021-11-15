# Cohesity Oracle Backup Sample Script using OIM

Warning: this code is provided on a best effort basis and is not in any way officially supported or sanctioned by Cohesity. The code in this repository is provided as-is and the author accepts no liability for damages resulting from its use.

## Download the script

- curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/oim/backup-ora-coh-oim/linux/backup-ora-coh-oim.bash
- curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/oim/backup-ora-coh-oim/sun/sbackup-ora-coh-oim.bash
- chmod 750 backup-ora-coh-oim.bash
- chmod 750 sbackup-ora-coh-oim.bash

## Download OIM installation script
The following scripts will download all RMAN shell scripts and Cohesity Python scripts that are necessary to do Oracle Incremental Merge backup and restore. The python script requires requests python module (python-requests) to be installed on the Oracle server. python script prerequisites are listed on https://github.com/bseltz-cohesity/scripts/tree/master/python

- cd <script directory>
- curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/oim/linux-oim-download.bash
- chmod 750 linux-oim-download.bash
- curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/oim/sun-oim-download.bash
- chmod 750 sun-oim-download.bash
