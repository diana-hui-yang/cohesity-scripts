### ***Warning: this code is provided on a best effort basis and is not in any way officially supported or sanctioned by Cohesity. The code in this repository is provided as-is and the author accepts no liability for damages resulting from its use.***

## Description
This bash script utilizes the RMAN restore/recover command to restore a database from the backup taken by using the backup-ora-coh-sbt.bash script if it is an Oracle database on Linux, or the aix-backup-ora-coh-sbt.bash script if it is an Oracle database on AIX. It can be used to restore the original Oracle database in the event of corruption or server/storage failures. 
