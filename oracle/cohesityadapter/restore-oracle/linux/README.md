## Download the script
- curl -O https://raw.githubusercontent.com/diana-hui-yang/cohesity-scripts/master/oracle/cohesityadapter/restore-oracle/linux/restore-ora-cohesityadapter.bash
- curl -O https://raw.githubusercontent.com/cohesity/community-automation-samples/main/oracle/python/restoreOracle-v2/restoreOracle-v2.py
- curl -O https://raw.githubusercontent.com/cohesity/community-automation-samples/main/python/pyhesity.py
- chmod 750 restore-ora-cohesityadapter.bash
- chmod 750 restoreOracle-v2.py

## Description
This script is a wrapper that calls a Python Oracle restore script to create a new database from the backup of another database using the Cohesity Oracle adapter 'Alternate restore' option. This operation is commonly used by Oracle DBAs to refresh their Test/Dev environments using backups of production databases. The script cleans /etc/oratab and drops the Test/Dev databases before running the Python script restoreOracle-v2.py. Click [restoreOracle-v2.py ](https://github.com/bseltz-cohesity/scripts/tree/master/oracle/python/restoreOracle-v2) link to learn how to use it.

Required parameters

- -b : restoreOracle-v2.py script with input. ( example: "/home/oracle1/scripts/python/restoreOracle-v2.py -v cohesity -u ora -i -ss oracle1 -ts oracle2 -sd cohcdbt -td restore1 -oh /u01/app/oracle1/product/19.3.0/dbhome_1 -ob /u01/app/oracle1 -od '+DATA1'" )
 
 Optional Parameters
- -f : yes means the script will execute restoreOracle-v2.py script with input, the default is no
- -d : yes means the database which needs to be refreshed can be dropped first without prompting, the default is no

## Example
./restore-ora-cohesityadapter.bash -b "/home/oracle1/scripts/oracle-agent/github/restoreOracle-v2.py -v cohesity-cluster -u oraadmin -i -ss oraserver2 -ts oraserver1 -sd orcl1 -td restore1 -oh /u01/app/oracle1/product/19.3.0/dbhome_1 -ob /u01/app/oracle1 -od +DATA1 -ch 2 -l -pf "CONTROL_FILES='+DATA1','+FRA'" -pf "DB_RECOVERY_F
ILE_DEST='+FRA'" -pf "SGA_TARGET=14125M" -w" -f yes -d yes
