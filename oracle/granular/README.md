# Cohesity Oracle Restore Sample Script using adapter

### ***Warning: this code is provided on a best effort basis and is not in any way officially supported or sanctioned by Cohesity. The code in this repository is provided as-is and the author accepts no liability for damages resulting from its use.***

The import-tablespace bash script is capable of importing a tablespace from one Oracle database to another. It is useful for performing point-in-time tablespace restores from backups created using the Oracle adapter. Initially, a Cohesity point-in-time Oracle clone should be created either through the Cohesity GUI or by utilizing Brian's Python script available at (https://github.com/bseltz-cohesity/scripts/tree/master/oracle/python/cloneOracle). Subsequently, this script can be used to import the tablespace from the Cohesity Oracle clone into the database requiring restoration of this particular tablespace.
