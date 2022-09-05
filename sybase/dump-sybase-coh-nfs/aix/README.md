## Download the script

- curl -O https://raw.githubusercontent.com/diana-hui-yang/cohesity-scripts/master/sybase/dump-sybase-coh-nfs/aix/aix-dump-sybase-coh-nfs.bash
- chmod 750 aix-dump-sybase-coh-nfs.bash

## Prerequisite
GNU package: bash, gawk, mpfr, find, rm
Here is link to AIX open source https://www.ibm.com/support/pages/aix-toolbox-open-source-software-downloads-alpha

## Export scripts Description
When run the script without any options, it displays the script usage


 Required Parameters
- -k : sybase login key
- -d : database name
- -t : dump type. db means database dump, log means transactional dump
- -m : mount-prefix (like /coh/sybase)
- -n : number of mounts (only 1 is supported currently)
- -e : Retention time (days to retain the dumps)

 Optional Parameters
- -U : sybase user. It is not needed when using key
- -P : sybase password. It is not needed when using key
- -S : Service name. It is not needed when using key
- -X : yes means Sybase -X is used. The default is no
- -p : number of stripes (Optional, only 1 is supported currently)
- -w : yes means preview sybase dump scripts



## aix-dump-sybase-coh-nfs.bash Backup Example
### Full database dump example
./dump-sybase-nfs.bash -d db1 -m /coh/sybkp -n 3 -p 6 -e 30 -k key -t db -X
### Create database log dump script only example
./dump-sybase-coh-nfs.bash -d db1 -m /coh/sybkp -n 3 -p 6 -e 30 -X -w yes -U sybase -P *** -S SYBASEASELX -t log
