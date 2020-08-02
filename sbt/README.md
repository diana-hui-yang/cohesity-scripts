# Cohesity Oracle Backup Sample Script using souce-side dedupe library (sbt_tape)
Warning: this code is provided on a best effort basis and is not in any way officially supported or sanctioned by Cohesity. The code in this repository is provided as-is and the author accepts no liability for damages resulting from its use.

## Download the script
- curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/sbt/backup-ora-coh-dedup/backup-ora-coh-dedup.bash
- curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/sbt/restore-ora-coh-dedup/restore-ora-coh-dedup.bash
- chmod 750 backup-ora-coh-dedup.bash
- chmod 750 restore-ora-coh-dedup.bash

## Download OIM installation script
This script will download all RMAN shell scripts and Cohesity Python scripts that are necessary to do Oracle Incremental Merge backup and restore. 
- cd <script directory>
- curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/sbt/sbt-download.bash
- chmod 750 sbt-download.bash
