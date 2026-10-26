## Download the script from PowerShell

Run the following in a **PowerShell** window (not cmd):

```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/diana-hui-yang/cohesity-scripts/master/oracle/sbt/duplicate-ora-coh-sbt/Windows/duplicate-ora-coh-sbt.ps1' -OutFile 'duplicate-ora-coh-sbt.ps1'
```

After downloading, unblock the files so Windows will run them:

```powershell
Unblock-File .\duplicate-ora-coh-sbt.ps1
```

## Description

When run the script without any options, it displays the script usage.

### Required Parameters
- `-TargetSid`         (-i) : Target Oracle instance name (the duplicate database)
- `-SourceConnect`     (-r) : Source Oracle connection (example: "sys/<password>@<source connect string> as sysbackup")
- `-View`              (-v) : Cohesity View that holds the backup
- `-OracleHome`        (-o) : ORACLE_HOME (the folder that contains the bin directory)

### Optional Parameters
- `-TargetConnect`     (-r) : Target connection (example: "<dbuser>/<dbpass>@<target connection string> as sysduplicate"; optional if it is local duplicate)
- `-CatalogConnect`    (-c) : Catalog connection (example: "<dbuser>/<dbpass>@<catalog connection string>"; optional)
- `-LongRetention`          : Long Term Retention time (days to retain this particular duplicate; needs an RMAN catalog database and works only with -OracleRetention. No single-letter alias.)
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
- `-Preview`           (-w) : switch (no value). Include -Preview to print the generated RMAN scripts without running the duplicate.

## duplicate to Cohesity view "orasbt1" example

### Full duplicate example when sbt library is in lib directory under the script directory
```bat
duplicate-ora-coh-sbt.bat -o orcl -i 0 -y cohesity_name -v orasbt1 -p 4 -e 30
```

### Cumulative duplicate example when sbt library is in directory d:\oracle\cohesity\lib
```bat
duplicate-ora-coh-sbt.bat -o orcl -i 1 -y cohesity_name -v orasbt1 -p 3 -e 30 -s d:\oracle\cohesity\lib
```

### Archive log duplicate example when sbt library is in lib directory under the script directory
```bat
duplicate-ora-coh-sbt.bat -o orcl -a yes -y cohesity_name -v orasbt1 -p 2 -e 30
```
