### ***Warning: this code is provided on a best effort basis and is not in any way officially supported or sanctioned by Cohesity. The code in this repository is provided as-is and the author accepts no liability for damages resulting from its use.***


## Description
The scripts uses Cohesity Source-side dedup library (please contact Cohesity support to get the library download link) to backup Oracle databases. The backup format is in Oracle backupset format. The backup-ora-coh-dedup.bash script supports full, incremental, and archive logs backup options.  Cohesity Remote adapter can schedule this script. The script can be launched from a central server and also supports a recovery catalog. 

