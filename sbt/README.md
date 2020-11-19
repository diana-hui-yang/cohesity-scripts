# Cohesity Oracle Backup Sample Script using souce-side dedupe library (sbt_tape)
Warning: this code is provided on a best effort basis and is not in any way officially supported or sanctioned by Cohesity. The code in this repository is provided as-is and the author accepts no liability for damages resulting from its use.

## Download individual script
### Linux
- curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/sbt/backup-ora-coh-sbt/backup-ora-coh-sbt.bash
- curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/sbt/duplicate-ora-coh-sbt/duplicate-ora-coh-sbt.bash
- curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/sbt/restore-ora-coh-sbt/restore-ora-coh-sbt.bash
- chmod 750 backup-ora-coh-sbt.bash
- chmod 750 duplicate-ora-coh-sbt.bash
- chmod 750 restore-ora-coh-sbt.bash


## Download all SBT related scripts
### Linux
This linux-sbt-download.bash script will download all RMAN shell scripts to run on Linux servers and Cohesity Python scripts that are necessary to do Oracle backup and restore using Cohesity sbt library. You can copy the content of linux-sbt-download.bash script directly on your unix server. You can also download it first.
- cd <script directory>
- curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/sbt/linux-sbt-download.bash
- chmod 750 linux-sbt-download.bash

## Download SBT library
SBT library needs to be downloaded from Cohesity support site. 
### Linux
Here is the linux sbt library link http://downloads.cohesity.com/oracle_sbt/RPC-Library/6.4.1-and-above/libsbt_6_and_7_linux-x86_64.so. When you click it first, it may ask you to login. Once you login, click this link again. It will download the library to your computer. Copy this sbt library file to the lib directory in the script directory. 
