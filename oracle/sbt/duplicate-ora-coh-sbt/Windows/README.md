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
- `-TargetConnect`      (-r) : Target connection (example: `"<dbuser>/<dbpass>@<target connection string> as sysduplicate"`; optional if it is local duplicate)
- `-CatalogConnect`     (-c) : RMAN Catalog connection (example: `"<dbuser>/<dbpass>@<catalog connection string>"`)
- `-SourceHost`         (-h) : Source host - the Oracle database host the backup was run on
- `-SourceDbName`       (-d) : Deprecated - the source DB name is derived from `-SourceConnect`
- `-PointInTime`        (-t) : Point in Time (format example: `"2026-01-27 13:00:00"`)
- `-Sequence`           (-e) : Log sequence number of thread 1 (use either `-PointInTime` or `-Sequence`, not both)
- `-RestoreSettingFile` (-b) : File with RMAN restore-location settings (e.g. `set newname for database to 'D:\dup\%b';`)
- `-CohesityName`       (-y) : Cohesity Cluster DNS name (VIPs resolved automatically)
- `-VipFile`            (-j) : File listing Cohesity Cluster VIPs (default name `vip-list`, default dir `config`)
- `-SbtLibrary`         (-s) : Cohesity SBT library name including directory or just directory (default dir `lib`)
- `-Parallel`           (-p) : Number of channels (default is 4)
- `-SourcePdb`          (-u) : Source pluggable database (omit for standalone/CDB duplication)
- `-NewPdb`             (-n) : Destination pluggable database name (needs `-AuxiliaryDb`)
- `-PdbCopy`            (-l) : `yes` = plug PDB with COPY; default `nocopy`
- `-AuxiliaryDb`        (-a) : Temporary auxiliary CDB for restoring a PDB into an existing target CDB
- `-Encryption`         (-g) : `yes` means encryption-in-flight is used. Default is `no`
- `-EncryptionCertFile` (-k) : Encryption certificate file, default directory is `lib` if full path not provided
- `-Grpc`               (-x) : `yes` means gRPC is used, `no` means SunRPC is used. Default is `yes`
- `-Force`              (-f) : Switch (no value). Refresh/overwrite the target database without prompting
- `-NoResume`           (-m) : Switch (no value). Use Oracle duplicate `NORESUME`
- `-Preview`            (-w) : Switch (no value). Print the generated RMAN duplicate script without running it

## duplicate exmaple

### duplidate CDB database (or standalone) `orawin1` to a target CDB database (or standalone) `orawin2` example
- ./duplicate-ora-coh-sbt.ps1 -r "user/password@oraserver:/orawin1" -i orawin2 -y cohesity -v orasbt_win
### duplidate a PDB database `orapdb1` in CDB database `orawin1` to a target CDB database `orawin2` which doesn't exist yet.
- ./duplicate-ora-coh-sbt.ps1 -r "user/password@oraserver:/orawin1" -i orawin2 -u orapdb1  -y cohesity -v orasbt_win
### duplidate a PDB database `orapdb1` in CDB database `orawin1` to an exisinng target CDB database `orawin2` with a new PDB name orares1 using a auxiliary database `oraaux`
- ./duplicate-ora-coh-sbt.ps1 -r "user/password@oraserver:/orawin1 -i orawin2 -u orapdb1 -n orares1 -y cohesity -v ora_sbt -a oraaux

