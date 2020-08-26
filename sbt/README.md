# Cohesity Oracle Backup Sample Script using souce-side dedupe library (sbt_tape)
Warning: this code is provided on a best effort basis and is not in any way officially supported or sanctioned by Cohesity. The code in this repository is provided as-is and the author accepts no liability for damages resulting from its use.

## Download the script
- curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/sbt/backup-ora-coh-sbt/backup-ora-coh-sbt.bash
- curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/sbt/restore-ora-coh-sbt/duplicate-ora-coh-sbt.bash
- curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/sbt/restore-ora-coh-sbt/restore-ora-coh-sbt.bash
- chmod 750 backup-ora-coh-sbt.bash
- chmod 750 duplicate-ora-coh-sbt.bash
- chmod 750 restore-ora-coh-sbt.bash

## Download sbt scripts installation script
This script will download all RMAN shell scripts and Cohesity Python scripts that are necessary to do Oracle backup and restore using Cohesity sbt library. Here is the content of installation script
- cd <script directory>
- curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/sbt/sbt-download.bash
- chmod 750 sbt-download.bash
