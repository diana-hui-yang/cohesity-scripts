# Cohesity Oracle Backup Sample Script using souce-side dedupe library (sbt_tape)
***Warning: this code is provided on a best effort basis and is not in any way officially supported or sanctioned by Cohesity. The code in this repository is provided as-is and the author accepts no liability for damages resulting from its use.***

## Download individual script
Check individual script link

## AIX Prerequisite 
GNU package: bash, gawk, python, mpfr, findutils. Here is link to AIX open source https://www.ibm.com/support/pages/aix-toolbox-open-source-software-downloads-alpha

## Download all SBT related scripts
### Linux
linux-sbt-download script will download all RMAN shell scripts to run on Linux servers to do Oracle backup and restore using Cohesity sbt library and Cohesity standard view. 
linux-sbt-23-download script will download all RMAN shell scripts to run on Linux servers to do Oracle backup and restore using Cohesity sbt library and Cohesity ZDLRA view. 
### AIX
aix-sbt-download script will download all RMAN shell scripts to run on AIX servers and Cohesity Python scripts that are necessary to do Oracle backup and restore using Cohesity sbt library.

## Download SBT library
SBT library needs to be downloaded from Cohesity support site. 
### Linux
The linux sbt library download link is (http://downloads.cohesity.com/oracle_sbt/RPC-Library/6.5.1/linux/). Copy this link to another browser window. You may have to log in first. Once you log in, paste the copied link again. Download the library ***'libsbt_linux_x86_64.so'*** and copy this sbt library file to the 'lib' directory in the script directory on the Oracle server (\<top directory\>/rman/lib). There are two useful toos 'sbt_list' and 'sbt_perf_test' in tools directory. Download them amd copy them to 'toos' directory in the script directory on the Oracle server (\<top directory\>/rman/tools)

When using the Cohesity ZDLRA view to perform Oracle backups and restores, it is important to download the Cohesity ZDLRA package. The link is (https://downloads.cohesity.com/oracle_sbt/RPC-Library/6.5.1/zdlra/). Copy this link to another browser window. You may have to log in first. Once you log in, paste the copied link again. Follow Cohesity document to install this package. Copy the sbt library file 'libsbt_linux_x86_64.so' from the ZDLRA package to the 'lib' directory in the script directory on the Oracle server.

### AIX
The AIX sbt library download link is (http://downloads.cohesity.com/oracle_sbt/RPC-Library/6.5.1/aix/). Copy this link to another browser window. You may have to log in first. Once you log in, paste the copied link again. Download the library 'libsbt_aix_powerpc.so' and copy this sbt library file to the 'lib' directory in the script directory on the Oracle server (\<top directory\>/rman/lib). There are two useful toos 'sbt_list' and 'sbt_perf_test' in tools directory. Download them amd copy them to 'toos' directory in the script directory on the Oracle server (\<top directory\>/rman/tools)


