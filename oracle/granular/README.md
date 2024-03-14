# Cohesity Oracle Restore Sample Script using adapter

### ***Warning: this code is provided on a best effort basis and is not in any way officially supported or sanctioned by Cohesity. The code in this repository is provided as-is and the author accepts no liability for damages resulting from its use.***

The import-tablespace bash script is capable of importing a tablespace from one Oracle database to another. It is useful for performing point-in-time tablespace restores from backups created using the Oracle adapter. Initially, a Cohesity point-in-time Oracle clone should be created either through the Cohesity GUI or by utilizing Brian's Python script available at (https://github.com/bseltz-cohesity/scripts/tree/master/oracle/python/cloneOracle). Subsequently, this script can be used to import the tablespace from the Cohesity Oracle clone into the database requiring restoration of this particular tablespace.

The restore-datafile bash script generates RMAN scripts capable of restoring an Oracle datafile from the backup. It is designed for situations where only a datafile needs restoration, particularly in large databases where the restoration process can be time-consuming.

The restore-tablespace bash script generates RMAN scripts capable of restoring the tablespace to the last commit time from the backup. It is designed for situations where a tablespace is corrupted and needs restoration. It requires that the latest Oracle logs are available on the server. Please utilize the import-tablespace bash script when a point-in-time tablespace restore needs to be performed.
