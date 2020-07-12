## Download the script

- curl -O https://raw.githubusercontent.com/diana-hui-yang/rman-cohesity/master/nfs/prepare-restore/prepare-restore.bash
- chmod 750 prepare-restore.bash

## prepare-restore.bash script Description
This script mount Oracle Cohesity copy view on a server for restore purpose. The user needs to have mount/umount privilege. It uses a python script copyView.py which can be downloaded from https://github.com/bseltz-cohesity/scripts/tree/master/python/cloneView. 

### prepare-restore.bash script parameter

- -f : file that has vip list"
- -u : username: username to authenticate to Cohesity cluster"
- -d : domain: (optional) domain of username, defaults to local"
- -v : Cohesity view for Oracle backup"
- -n : Cohesity view for Oracle restore. The name should have restore in it"
- -j : jobname: name of protection job to run, exmaple "snap view""
- -m : mount-prefix (The name should have restore in it. like /coh/restore/oraoim)"
- -t : (optional) select backup version before specified date, defaults to latest backup, format \"2020-04-18 18:00:00\")"
- -r : yes means refresh restore view with new data. no means no refresh"

## VIP file content example
- 10.19.2.6
- 10.19.2.7
- 10.19.2.8
- 10.19.2.9

## nfs-mount.bash exmaple (requires root privilege)
./prepare-restore.bash -f vip-list -f $vip_list -u oraadmin -d local -v $oraoim -n $orarestore -j "snap oim" -m /coh/oraoin -r yes


