
### ***Warning: this code is provided on a best effort basis and is not in any way officially supported or sanctioned by Cohesity. The code in this repository is provided as-is and the author accepts no liability for damages resulting from its use.***

## Duplicate scripts Description
This bash script utilize RMAN duplicate command to duplicate (clone) a database from the backup taken by using backup-ora-coh-nfs.bash/backup-ora-coh-oim.bash on Linux ,sbackup-ora-coh-nfs.bash/sbackup-ora-coh-oim.bash on Solaris, or aix-backup-ora-coh-nfs.bash/aix-backup-ora-oim.bash on AIX. This duplicate bash script supports RMAN duplicate "SET" option before duplicate command. It does not support RMAN duplicate "SPFILE" option. Any "SPFILE" option can be set in init<database>.ora file first. 
 
