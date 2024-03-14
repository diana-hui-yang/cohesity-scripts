### ***Warning: this code is provided on a best effort basis and is not in any way officially supported or sanctioned by Cohesity. The code in this repository is provided as-is and the author accepts no liability for damages resulting from its use.***


## Duplicate scripts Description
This bash script utilize RMAN duplicate command to duplicate, or clone, a database from the backup taken by using backup-ora-coh-sbt.bash script if it is Oracle database on Linix or aix-backup-ora-coh-sbt.bash script if it is Oracle database on AIX. This duplicate bash script supports RMAN duplicate "SET" option before duplicate command. It does not support RMAN duplicate "SPFILE" option. Any "SPFILE" option can be set in init<database>.ora file first. 
    
 "SET" should be set a file that the duplicate bash script calls on by using "-l" option. When using time setting like "set until time \"to_date("'2020-08-23 11:30:00','YYYY/MM/DD HH24:MI:SS'")\";", the time use the timezone on the source server, not the target server if there is a timezone difference. 



