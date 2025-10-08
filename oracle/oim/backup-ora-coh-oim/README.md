### ***Warning: this code is provided on a best effort basis and is not in any way officially supported or sanctioned by Cohesity. The code in this repository is provided as-is and the author accepts no liability for damages resulting from its use.***

## prerequisite
- Download Brian Seltz's python scripts. These scripts are in https://github.com/diana-hui-yang/rman-cohesity/blob/master/oim/linux-oim-download.bash or https://github.com/diana-hui-yang/rman-cohesity/blob/master/oim/sun-oim-download.bash
- Run the storePassword.py script before running the Oracle backup script listed on this page, or after the Cohesity user’s password has been changed. This script saves an encrypted key file in the user’s home directory. The syntax is available at https://github.com/bseltz-cohesity/scripts/tree/master/python/storePassword
- Run storePasswordInFile.py script if Oracle is running on a failover cluster. This script will save the encrypted key file in the same directory as the storePasswordInFile.py script. The syntax is on https://github.com/bseltz-cohesity/scripts/tree/master/python/storePasswordInFile

Note: you may need to run the following command before you run python commands on AIX
export LIBPATH=/opt/freeware/lib:$LIBPATH
