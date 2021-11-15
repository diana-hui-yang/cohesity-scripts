## Download the script

- curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/nfs/duplicate-ora-coh-nfs/linux/duplicate-ora-coh-nfs.bash
- curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/nfs/duplicate-ora-coh-nfs/sun/sun-duplicate-ora-coh-nfs.bash
- chmod 750 duplicate-ora-coh-nfs.bash
- chmod 750 sun-duplicate-ora-coh-nfs.bash

## Duplicate scripts Description
This bash script utilize RMAN duplicate command to duplicate, or clone, a database from the backup taken by using backup-ora-coh-nfs.bash script if it is Oracle database on Linix or sbackup-ora-coh-nfs.bash script if it is Oracle database on Solaris. This duplicate bash script supports RMAN duplicate "SET" option before duplicate command. It does not support RMAN duplicate "SPFILE" option. Any "SPFILE" option can be set in init<database>.ora file first. 
