### ***Warning: this code is provided on a best effort basis and is not in any way officially supported or sanctioned by Cohesity. The code in this repository is provided as-is and the author accepts no liability for damages resulting from its use.***


## Description
This script is a wrapper that calls a Python Oracle restore script to create a new database from the backup of another database using the Cohesity Oracle adapter 'Alternate restore' option. This operation is commonly used by Oracle DBAs to refresh their Test/Dev environments using backups of production databases. The script cleans /etc/oratab and drops the Test/Dev databases before running the Python script restoreOracle-v2.py.
