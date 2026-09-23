## Download the script from PowerShell

Run the following in a **PowerShell** window (not cmd):

```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/diana-hui-yang/cohesity-scripts/master/oracle/sbt/backup-ora-coh-sbt/Windows/backup-ora-coh-sbt.ps1' -OutFile 'backup-ora-coh-sbt.ps1'
Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/diana-hui-yang/cohesity-scripts/master/oracle/sbt/backup-ora-coh-sbt/Windows/backup-ora-coh-sbt.bat' -OutFile 'backup-ora-coh-sbt.bat'
```

After downloading, unblock the files so Windows will run them:

```powershell
Unblock-File .\backup-ora-coh-sbt.ps1
Unblock-File .\backup-ora-coh-sbt.bat
```

## Description

When run the script without any options, it displays the script usage.

### Required Parameters
- `-HostName`          (-h) : host (scanname is required if it is RAC, optional if it is standalone)
- `-DbName`            (-o) : ORACLE_DB_NAME (needs an entry of this database in oratab. If it is RAC, it is db_name)
- `-CohesityName`      (-y) : Cohesity Cluster DNS name
- `-ArchiveOnly`       (-a) : archivelog only backup (yes = archivelog backup only, no = database backup plus archivelog backup; default is no)
- `-Level`             (-i) : If not archivelog only backup, it is full or incremental backup. 0 is full backup, 1 is cumulative incremental backup, offline is offline full backup
- `-View`              (-v) : Cohesity View that is configured to be the target for Oracle backup
- `-OracleRetention`   (-e) : Retention time in days; expired files are deleted by Oracle
- `-OracleHome`        (-m) : ORACLE_HOME (the folder that contains the bin directory)

### Optional Parameters
- `-TargetConnect`     (-r) : Target connection (example: "<dbuser>/<dbpass>@<target connection string> as sysbackup"; optional if it is local backup)
- `-CatalogConnect`    (-c) : Catalog connection (example: "<dbuser>/<dbpass>@<catalog connection string>"; optional)
- `-LongRetention`          : Long Term Retention time (days to retain this particular backup; needs an RMAN catalog database and works only with -OracleRetention. No single-letter alias.)
- `-Parallel`          (-p) : number of channels (optional, default is 4)
- `-VipFile`           (-f) : The file lists Cohesity Cluster VIPs (default name is vip-list and default directory is config)
- `-SbtLibrary`        (-s) : Cohesity SBT library name including directory, or just directory (default directory is lib)
- `-ArchiveLogKeepDays`(-l) : Archive logs retain days (days to retain local archivelogs before deleting them. default is 1 day, "no" means not deleting local archivelogs on disk)
- `-ArchiveCopies`     (-b) : Number of times backing up Archive logs (default is 1)
- `-SectionSize`       (-z) : section size in GB (optional, default is no section size)
- `-Tag`               (-t) : RMAN TAG
- `-Compression`       (-k) : RMAN compression (yes = RMAN compression, no = no RMAN compression; default is no)
- `-Encryption`        (-g) : yes means encryption-in-flight is used. Default is no
- `-EncryptionCertFile`(-j) : encryption certificate file; default directory is lib if full path is not provided
- `-Grpc`              (-x) : yes means gRPC is used, no means SunRPC is used. Default is yes
- `-SourceDedup`       (-d) : yes means source side dedup is used. Default is yes
- `-SbtIoLog`          (-q) : yes means SBT activity is recorded in sbtio.log, no means only errors are recorded. Default is yes
- `-Preview`           (-w) : switch (no value). Include -Preview to print the generated RMAN scripts without running the backup.

## Backup to Cohesity view "orasbt1" example

### Full backup example when sbt library is in lib directory under the script directory
```bat
backup-ora-coh-sbt.bat -o orcl -i 0 -y cohesity_name -v orasbt1 -p 4 -e 30
```

### Cumulative backup example when sbt library is in directory d:\oracle\cohesity\lib
```bat
backup-ora-coh-sbt.bat -o orcl -i 1 -y cohesity_name -v orasbt1 -p 3 -e 30 -s d:\oracle\cohesity\lib
```

### Archive log backup example when sbt library is in lib directory under the script directory
```bat
backup-ora-coh-sbt.bat -o orcl -a yes -y cohesity_name -v orasbt1 -p 2 -e 30
```
