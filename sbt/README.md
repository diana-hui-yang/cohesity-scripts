# Cohesity Oracle Backup Sample Script using souce-side dedupe library (sbt_tape)
***Warning: this code is provided on a best effort basis and is not in any way officially supported or sanctioned by Cohesity. The code in this repository is provided as-is and the author accepts no liability for damages resulting from its use.***


The bash script can be used to generate RMAN commands only or generate/execute RMAN commands to work with Cohesity platform. When "\-w yes" is given as part of the input, it generates RMAN commands and stores it in a csv suffix file in \<bash script directory\>/log/\<oracle server name\> directory according to the inputs. Without "\-w yes" input, the bash script will execute the RMAN commands after generating the RMAN commands. 

## Download individual script
Check individual script link

## AIX Prerequisite 
GNU package: bash, gawk, python, mpfr, findutils. Here is link to AIX open source https://www.ibm.com/support/pages/aix-toolbox-open-source-software-downloads-alpha

## Download all SBT related scripts
### Linux
linux-sbt-download script will download all RMAN shell scripts to run on Linux servers and Cohesity Python scripts that are necessary to do Oracle backup and restore using Cohesity sbt library. 
### AIX
aix-sbt-download script will download all RMAN shell scripts to run on AIX servers and Cohesity Python scripts that are necessary to do Oracle backup and restore using Cohesity sbt library.

## Download SBT library
SBT library needs to be downloaded from Cohesity support site. 
### Linux
The linux sbt library download link is (http://downloads.cohesity.com/oracle_sbt/RPC-Library/6.5.1/linux/). When you click it first, it may ask you to login. Once you login, click this link again. Download the library libsbt_linux_x86_64.so and copy this sbt library file to the lib directory in the script directory on the Oracle server (\<top directory\>/rman/lib). There are two useful toos (sbt_list and sbt_perf_test) in tools directory. Download them amd copy them to toos directory in the script directory on the Oracle server (\<top directory\>/rman/tools)
### AIX
The AIX sbt installer script link is http://downloads.cohesity.com/oracle_sbt/RPC-Library/6.4.1-and-above/AIX. The installation command is

- cohesity_plugin_sbt_0.0.0-master_aix_powerpc_installer -- -d \<top directory\>/rman/lib

