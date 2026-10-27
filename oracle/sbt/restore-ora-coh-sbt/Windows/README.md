## Download the script from PowerShell

Run the following in a **PowerShell** window (not cmd):

```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/diana-hui-yang/cohesity-scripts/master/oracle/sbt/restore-ora-coh-sbt/Windows/restore-ora-coh-sbt.ps1' -OutFile 'restore-ora-coh-sbt.ps1'
```

After downloading, unblock the files so Windows will run them:

```powershell
Unblock-File .\restore-ora-coh-sbt.ps1
```

## Description

When run the script without any options, it displays the script usage.

### Required Parameters
- `-OracleSid`          (-i) : Oracle instance name. If not RAC, it is the same as the DB name.
- `-View`               (-v) : Cohesity View that holds the backup
- `-OracleHome`         (-o) : ORACLE_HOME (the folder that contains the bin directory)

### Optional Parameters
- `-DbName`             (-d) : Source Oracle_DB_Name (DB name, not instance name). Defaults to -OracleSid.
- `-BackupHost`         (-h) : Oracle database host that the backup was run on (default is current host)
- `-CatalogConnect`     (-c) : Catalog connection (example: "<dbuser>/<dbpass>@<catalog connection string>")
- `-PointInTime`        (-t) : Point in Time (format example: "2026-01-27 13:00:00")
- `-ControlfileBackup`  (-b) : Controlfile backup piece name (example: orawin1_c-1234567890-20260127-00). Required with -RestoreControlfile when no catalog is used. The DBID is taken from it.
- `-Dbid`               (-e) : Source DBID. Required with -RestoreControlfile and -CatalogConnect if -ControlfileBackup is not given.
- `-CohesityName`       (-y) : Cohesity Cluster DNS name (VIPs are resolved automatically)
- `-VipFile`            (-j) : The file lists Cohesity Cluster VIPs (default name is vip-list, default directory is config)
- `-SbtLibrary`         (-s) : Cohesity SBT library name including directory or just directory (default directory is lib)
- `-Parallel`           (-p) : Number of channels (default is 4)
- `-Encryption`         (-g) : yes means encryption-in-flight is used. Default is no
- `-EncryptionCertFile` (-k) : Encryption certificate file, default directory is lib if full path is not provided
- `-Grpc`               (-x) : yes means gRPC is used, no means SunRPC is used. Default is yes
- `-RestoreControlfile` (-l) : Switch (no value). Include it for a complete restore including spfile and controlfile.
- `-Force`              (-f) : Switch (no value). Include it to actually restore. Without it, only "restore database validate" runs.
- `-Preview`            (-w) : Switch (no value). Include it to print the generated RMAN scripts without restoring.
## restore exmaple

### Restore database validate example. The database name is "orawin1". The database won't be over-written. 
- ./restore-ora-coh-sbt.ps1 -i orawin1 -y cohesity -v orasbtwin -o e:\oracle\oraclehome
### Restore database"orawin1" assuming controlfile are still intact. The database will be over-written.
- ./restore-ora-coh-sbt.ps1 -i orawin1 -y cohesity -v orasbtwin -s /u01/app/coheisty -f -o e:\oracle\oraclehome
### Restore controlfile, then database "orawin1" on the original Oracle server "orawest".  The database will be over-written.
- ./restore-ora-coh-sbt.ps1  -i orawin1 -t "2020-08-02 12:00:00" -l -y cohesity -v orasbtwin -f -o e:\oracle\oraclehome -b \<controlfile backup\>
### Restore controlfile, then database "orawin1" on a new server "orawestdr". (the original Oracle server is "orawest")
Note: before running this commaand, several prepare steps should be done first.
init file should be created, adump directory should be created. 
Check the scripts example in restore-example directory for more details
- ./restore-ora-coh-sbt.ps1 -h orawest -i orawin1 -t "2020-08-02 12:00:00" -l -y cohesity -v orasbtwin -f -c "catalog login" -e \<dbid\>
