### ***Warning: this code is provided on a best effort basis and is not in any way officially supported or sanctioned by Cohesity. The code in this repository is provided as-is and the author accepts no liability for damages resulting from its use.***

## Description
This bash script utilize RMAN restore/recover command to restore a database from the backup taken by using backup-ora-coh-sbt.bash script if it is Oracle database on Linix or aix-backup-ora-coh-sbt.bash scriptif it is Oracle database on AIX. When using point-in-time like "2020-08-23 11:30:00', it is the timezone on the source server, not the target server if there is a timezone difference. 

