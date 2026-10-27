<#
.SYNOPSIS
    Restore an Oracle database from a Cohesity SBT backup taken by backup-ora-coh-sbt.ps1
    (Windows / PowerShell port).

.DESCRIPTION
    PowerShell port of restore-ora-coh-sbt.bash (Diana Yang).
    This is the STREAMLINED Windows standalone version:
      * RAC multi-node restore logic has been dropped (-r / -n).
      * ORACLE_HOME must be supplied (-OracleHome); it is not read from the environment.

    The script can:
      * Run an RMAN "restore database validate" (default, when -Force is NOT given).
      * Restore spfile + controlfile + datafiles and recover (with -Force, and -RestoreControlfile
        for the complete flow including controlfile).
      * Do point-in-time recovery (-PointInTime).
      * Use an RMAN recovery catalog (-CatalogConnect).
      * Preview the generated RMAN scripts without doing anything (-Preview).

.NOTES
    Windows specifics vs. the Linux original:
      * The instance is hosted by the Windows service OracleService<SID>; the script starts that
        service before "startup nomount". The service and a parameter/password file must already
        exist (create with oradim if needed).
      * The instance state is read from V$INSTANCE.STATUS (DOWN / NOMOUNT / MOUNT / OPEN), which is
        more reliable than the old service-only check (on Windows the service can be Running while
        the instance is idle).
      * Parameter/spfiles are looked for under ORACLE_HOME\database (not dbs).


.EXAMPLE
    # Validate a restore (no changes to the database)
    .\restore-ora-coh-sbt.ps1 -OracleSid orcl -OracleHome "C:\app\oracle\product\19.0.0\dbhome_1" `
        -View oraback -CohesityName cohesity.example.com

.EXAMPLE
    # Full restore incl. controlfile (no catalog: supply the controlfile backup name), recover and open
    .\restore-ora-coh-sbt.ps1 -OracleSid orcl -OracleHome "C:\app\oracle\product\19.0.0\dbhome_1" `
        -View oraback -CohesityName cohesity.example.com -RestoreControlfile -Force `
        -ControlfileBackup "ORCL_c-1234567890-20260127-00"

.EXAMPLE
    # Point-in-time restore
    .\restore-ora-coh-sbt.ps1 -OracleSid orcl -OracleHome "C:\app\oracle\product\19.0.0\dbhome_1" `
        -View oraback -CohesityName cohesity.example.com -RestoreControlfile -Force `
        -PointInTime "2026-01-27 13:00:00"
#>

[CmdletBinding()]
param(
    [Alias('i')]
    [string]$OracleSid,

    [Alias('v')]
    [string]$View,

    [Alias('o')]
    [string]$OracleHome,

    [Alias('d')]
    [string]$DbName,

    [Alias('h')]
    [string]$BackupHost,

    [Alias('c')]
    [string]$CatalogConnect,

    [Alias('t')]
    [string]$PointInTime,

    # Name of the controlfile autobackup piece (example: ORCL_c-1234567890-20260127-00).
    # Required with -RestoreControlfile when no RMAN catalog is used (no sbt_list on Windows).
    [Alias('b')]
    [string]$ControlfileBackup,

    # DBID of the source database. Optional when -ControlfileBackup is given (derived from its name);
    # required with -RestoreControlfile + -CatalogConnect when -ControlfileBackup is not given.
    [Alias('e')]
    [string]$Dbid,

    [Alias('y')]
    [string]$CohesityName,

    [Alias('j')]
    [string]$VipFile,

    [Alias('s')]
    [string]$SbtLibrary,

    [Alias('p')]
    [int]$Parallel = 4,

    # -l in bash: complete restore including controlfile (and spfile).
    [Alias('l')]
    [switch]$RestoreControlfile,

    # -f in bash: actually restore. Without it the script only runs "restore database validate".
    [Alias('f')]
    [switch]$Force,

    [Alias('g')]
    [ValidateSet('yes', 'Yes', 'YES', 'no', 'No', 'NO')]
    [string]$Encryption = 'no',

    [Alias('k')]
    [string]$EncryptionCertFile,

    # gRPC (yes) vs SunRPC (no)
    [Alias('x')]
    [ValidateSet('yes', 'Yes', 'YES', 'no', 'No', 'NO')]
    [string]$Grpc = 'yes',

    [Alias('w')]
    [switch]$Preview
)

function Show-Usage {
    $scriptName = Split-Path -Leaf $PSCommandPath
    if (-not $scriptName) { $scriptName = "restore-ora-coh-sbt.ps1" }

    Write-Host @"
Usage: .\$scriptName -OracleSid <Oracle instance name> -View <view> -OracleHome <ORACLE_HOME> -DbName <Oracle_DB_Name> -BackupHost <backup host> -CatalogConnect <Catalog connection> -PointInTime <point-in-time> -ControlfileBackup <controlfile backup name> -Dbid <dbid> -CohesityName <Cohesity-cluster> -VipFile <vip file> -SbtLibrary <sbt home> -Parallel <number of channels> -Encryption <yes/no> -EncryptionCertFile <cert path or name> -Grpc <yes/no> [-RestoreControlfile] [-Force] [-Preview]

 (Each long name has a single-letter alias shown in parentheses, matching the original bash flags.)

 Required Parameters
 -OracleSid         (-i) : Oracle instance name. If not RAC, it is the same as the DB name.
 -View              (-v) : Cohesity View that holds the backup
 -OracleHome        (-o) : ORACLE_HOME (the folder that contains the bin directory)

 Optional Parameters
 -DbName            (-d) : Source Oracle_DB_Name (DB name, not instance name). Defaults to -OracleSid.
 -BackupHost        (-h) : Oracle database host that the backup was run on (default is current host)
 -CatalogConnect    (-c) : Catalog connection (example: "<dbuser>/<dbpass>@<catalog connection string>")
 -PointInTime       (-t) : Point in Time (format example: "2026-01-27 13:00:00")
 -ControlfileBackup (-b) : Controlfile backup piece name (example: ORCL_c-1234567890-20260127-00).
                           Required with -RestoreControlfile when no catalog is used. The DBID is taken from it.
 -Dbid              (-e) : Source DBID. Required with -RestoreControlfile and -CatalogConnect if -ControlfileBackup is not given.
 -CohesityName      (-y) : Cohesity Cluster DNS name (VIPs are resolved automatically)
 -VipFile           (-j) : The file lists Cohesity Cluster VIPs (default name is vip-list, default directory is config)
 -SbtLibrary        (-s) : Cohesity SBT library name including directory or just directory (default directory is lib)
 -Parallel          (-p) : number of channels (Optional, default is 4)
 -Encryption        (-g) : yes means encryption-in-flight is used. Default is no
 -EncryptionCertFile(-k) : encryption certificate file, default directory is lib if full path is not provided
 -Grpc              (-x) : yes means gRPC is used, no means SunRPC is used. Default is yes
 -RestoreControlfile(-l) : switch (no value). Include it for a complete restore including spfile and controlfile.
 -Force             (-f) : switch (no value). Include it to actually restore. Without it, only "restore database validate" runs.
 -Preview           (-w) : switch (no value). Include -Preview to print the generated RMAN scripts without restoring.

"@
}

if (-not $OracleSid) {
    Write-Host "

    Missing OracleSid parameter. It is required.

    "
    Show-Usage
    exit 1
}

if (-not $View) {
    Write-Host "

    Missing View parameter. It is required.

    "
    Show-Usage
    exit 1
}

if (-not $OracleHome) {
    Write-Host "

    Missing OracleHome parameter. It is required.

    "
    Show-Usage
    exit 1
}

$ErrorActionPreference = 'Continue'

# ------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------

function Get-TimeStamp { return (Get-Date -Format 'yyyyMMddHHmmss') }

function Test-Yes { param([string]$Value) return ($Value -match '^[Yy]') }

function Fail { param([string]$Message, [int]$Code = 1) Write-Host $Message; exit $Code }

if ($RestoreControlfile -and ($Force -or $Preview)) {
    if (-not $CatalogConnect -and -not $ControlfileBackup) {
        Fail 'Without an RMAN catalog, -ControlfileBackup (the controlfile backup piece name, e.g. ORCL_c-1234567890-20260127-00) is required with -RestoreControlfile.' 2
    }
    if ($CatalogConnect -and -not $ControlfileBackup -and -not $Dbid) {
        Fail 'With -CatalogConnect and -RestoreControlfile, provide -Dbid (or -ControlfileBackup so the DBID can be derived from its name).' 2
    }
}

function Write-Both {
    param([string]$Message, [string]$LogFile)
    Write-Host $Message
    if ($LogFile) { Add-Content -Path $LogFile -Value $Message }
}

# Return the first non-empty data row that follows the "----" header separator in a spool file.
function Get-OracleSpoolValue {
    param([string]$SpoolFile)
    if (-not (Test-Path $SpoolFile)) { return '' }
    $seen = $false
    foreach ($line in (Get-Content -Path $SpoolFile)) {
        if ($seen) {
            $t = ($line -replace '\s+', ' ').Trim()
            if ($t) { return $t }
        }
        if ($line -match '-{2,}') { $seen = $true }
    }
    return ''
}

# Run a SQL query, spooling output to $SpoolFile.
function Invoke-Sqlplus {
    param([string]$Sql, [string]$SpoolFile)
    if (Test-Path $SpoolFile) { Remove-Item -Path $SpoolFile -Force -ErrorAction SilentlyContinue }
    $body = @"
set echo off
set feedback off
spool "$SpoolFile"
$Sql
spool off
exit
"@
    $body | & $Global:SqlplusExe -S -L '/ as sysdba' | Out-Null
}

# Run arbitrary SQL*Plus commands (no spool), optionally echoing output.
function Invoke-SqlplusScript {
    param([string]$Sql)
    $body = "$Sql`nexit`n"
    $body | & $Global:SqlplusExe -S -L '/ as sysdba'
}

# Run an RMAN command file with connect target '/' (+ optional catalog). Returns exit code.
function Invoke-Rman {
    param([string]$CommandFile, [string]$LogFile)
    $body = "connect target '/'`n"
    if ($CatalogConnect) { $body += "connect catalog '$CatalogConnect'`n" }
    $body += "@$CommandFile`n"
    if ($LogFile) { $body | & $Global:RmanExe "log=$LogFile" | Out-Null }
    else          { $body | & $Global:RmanExe | Out-Null }
    return $LASTEXITCODE
}

# Run arbitrary RMAN commands with connect target '/'. Returns exit code.
function Invoke-RmanRaw {
    param([string]$Commands, [string]$LogFile)
    $body = "connect target '/'`n$Commands`nexit;`n"
    if ($LogFile) { $body | & $Global:RmanExe "log=$LogFile" | Out-Null }
    else          { $body | & $Global:RmanExe | Out-Null }
    return $LASTEXITCODE
}

# SBT_PARMS(...) inner content. Note: restore uses the gflag-name/gflag-value form for SunRPC.
function Build-SbtParms {
    param([string]$DataView, [string]$Ip)
    $p = "data_view=$DataView,vips=$Ip"
    if (-not (Test-Yes $Grpc))  { $p += ',gflag-name=sbt_use_grpc,gflag-value=false' }
    if (Test-Yes $Encryption)   { $p += ",sbt_certificate_file=$Global:EncryptCert" }
    return $p
}

function Build-ChannelParms {
    param([string]$DataView, [string]$Ip)
    return "'SBT_LIBRARY=$Global:Sbt,SBT_PARMS=($(Build-SbtParms -DataView $DataView -Ip $Ip))'"
}

function Get-FirstVip {
    foreach ($v in (Get-Content -Path $Global:VipFilePath)) {
        $t = $v.Trim()
        if ($t) { return $t }
    }
    return $null
}

# ------------------------------------------------------------------
# Validation
# ------------------------------------------------------------------

if ($PointInTime -and $PointInTime -match '"') {
    Fail 'There should not be quote characters inside -PointInTime. Use e.g. "2026-01-27 13:00:00".' 2
}

# ------------------------------------------------------------------
# Setup
# ------------------------------------------------------------------

$machine = $env:COMPUTERNAME
if (-not $BackupHost) { $BackupHost = $machine }

if (-not $DbName) {
    Write-Host "Oracle instance name $OracleSid is provided. If it is RAC or Standby, please provide the DB name via -DbName."
    $DbName = $OracleSid
}
$DbName = $DbName.ToUpper()

if ($Parallel -le 0) { Write-Host 'no input for parallel, set parallel to be 4'; $Parallel = 4 }

# ORACLE_HOME / executables
if (-not (Test-Path $OracleHome)) { Fail "ORACLE_HOME '$OracleHome' does not exist." }
$env:ORACLE_HOME = $OracleHome
$env:PATH = "$OracleHome\bin;$env:PATH"
$env:NLS_DATE_FORMAT = 'DD:MM:YYYY-HH24:MI:SS'
$env:ORACLE_SID = $OracleSid

$Global:RmanExe    = Join-Path $OracleHome 'bin\rman.exe'
$Global:SqlplusExe = Join-Path $OracleHome 'bin\sqlplus.exe'
if (-not (Test-Path $Global:RmanExe))    { Fail "rman.exe not found under '$OracleHome\bin'. Check -OracleHome." }
if (-not (Test-Path $Global:SqlplusExe)) { Fail "sqlplus.exe not found under '$OracleHome\bin'. Check -OracleHome." }

$Global:OracleServiceName = "OracleService$OracleSid"

$DATE_SUFFIX = Get-TimeStamp

# Script directory
$DIR = $PSScriptRoot
if (-not $DIR) { $DIR = (Get-Location).Path }

# Log and config directories
$logDir    = Join-Path $DIR "log\$machine"
$configDir = Join-Path $DIR 'config'
foreach ($d in @($logDir, $configDir)) {
    if (-not (Test-Path $d)) {
        Write-Host "$d does not exist, create it"
        try { New-Item -ItemType Directory -Path $d -Force | Out-Null }
        catch { Fail "create directory $d failed. There is a permission issue" }
    }
}

# Encryption certificate discovery
$Global:EncryptCert = $null
if (Test-Yes $Encryption) {
    Write-Host 'This restore will use encryption-in-flight'

    if (-not $EncryptionCertFile) {
        Fail "Encryption is enabled but no -EncryptionCertFile was provided. Exit"
    }

    # If the value has no directory component (just a file name), look in <current dir>\lib.
    # If it includes any path (relative or full), use it as given.
    if ([string]::IsNullOrEmpty((Split-Path -Parent $EncryptionCertFile))) {
        $certPath = Join-Path (Join-Path $DIR 'lib') $EncryptionCertFile
    }
    else {
        $certPath = $EncryptionCertFile
    }

    if (Test-Path $certPath -PathType Leaf) {
        $Global:EncryptCert = (Resolve-Path $certPath).Path
        Write-Host "encryption certificate is $Global:EncryptCert"
        Write-Host 'encryption certificate exists, script continue'
    }
    else {
        Fail "Encryption certificate file not found: $certPath. Exit"
    }
}

# VIP list
if (-not $CohesityName) {
    if (-not $VipFile) { $VipFile = Join-Path $configDir 'vip-list' }
    Write-Host "Cohesity Cluster name is not provided, we will use vipfile $VipFile"
    if (-not (Test-Path $VipFile)) { Fail "file $VipFile provided does not exist" }
    Write-Host "file $VipFile provided exists, script continue"
}
else {
    $VipFile = Join-Path $configDir "$OracleSid-res-vip-list"
    Write-Host "Cohesity Cluster name is $CohesityName. VIPS will be collected and stored in $VipFile"
    try {
        $resolved = Resolve-DnsName -Name $CohesityName -Type A -ErrorAction Stop |
            Where-Object { $_.IPAddress } | Select-Object -ExpandProperty IPAddress
    }
    catch { $resolved = @() }
    if (-not $resolved -or $resolved.Count -eq 0) { Fail "Cohesity Cluster name $CohesityName provided here is not in DNS" }
    Set-Content -Path $VipFile -Value $resolved
}
$Global:VipFilePath = $VipFile
if (-not (Get-FirstVip)) { Fail "No VIPs found in $VipFile" }
$Global:Vips = @(Get-Content -Path $VipFile | ForEach-Object { $_.Trim() } | Where-Object { $_ })

# SBT library
if ($SbtLibrary) {
    if ($SbtLibrary -like '*.dll') { Write-Host "we will use the sbt library provided $SbtLibrary"; $Global:Sbt = $SbtLibrary }
    else { Write-Host 'This may be a directory'; $Global:Sbt = Join-Path $SbtLibrary 'cohesity_sbt.dll' }
}
else {
    Write-Host "we assume the sbt library is in $DIR\lib"
    $Global:Sbt = Join-Path $DIR 'lib\cohesity_sbt.dll'
}
if (Test-Path $Global:Sbt -PathType Leaf) { Write-Host "SBT plugin file $Global:Sbt exists, script continue" }
else { Fail "file $Global:Sbt does not exist. exit" }

# Log / RMAN file names
$restore_rmanlog      = Join-Path $logDir "$DbName.rman-restore.$DATE_SUFFIX.log"
$restore_rmanfile     = Join-Path $logDir "$DbName.rman-restore.$DATE_SUFFIX.rcv"
$recover_rmanlog      = Join-Path $logDir "$DbName.rman-recover.$DATE_SUFFIX.log"
$recover_rmanfile     = Join-Path $logDir "$DbName.rman-recover.$DATE_SUFFIX.rcv"
$spfile_rmanlog       = Join-Path $logDir "$DbName.rman-spfile.$DATE_SUFFIX.log"
$spfile_rmanfile      = Join-Path $logDir "$DbName.rman-spfile.$DATE_SUFFIX.rcv"
$controlfile_rmanlog  = Join-Path $logDir "$DbName.rman-controlfile.$DATE_SUFFIX.log"
$controlfile_rmanfile = Join-Path $logDir "$DbName.rman-controlfile.$DATE_SUFFIX.rcv"
$incarnation          = Join-Path $logDir "$DbName.incar_list"
$stdout               = Join-Path $logDir "$DbName.$DATE_SUFFIX.std"

$dbsDir = Join-Path $OracleHome 'database'   # Windows pfile/spfile location (Linux: $ORACLE_HOME/dbs)

# Point-in-time conversion
if (-not $PointInTime) {
    $ptime = Get-TimeStamp
    Write-Host "current time is $(Get-Date), point-in-time restore time $ptime"
}
else {
    try { $pit = [datetime]::Parse($PointInTime) }
    catch { Fail "Could not parse -PointInTime '$PointInTime'. Use e.g. `"2026-01-27 13:00:00`"." }
    $ptime = $pit.ToString('yyyyMMddHHmmss')
    Write-Host "PointInTime is $PointInTime, point-in-time restore time $ptime"
}

# Test catalog connection
if ($CatalogConnect) {
    Write-Host "catalog connection is $CatalogConnect"
    $catOut = "connect catalog '$CatalogConnect'`nexit;`n" | & $Global:RmanExe 2>&1
    if (-not ($catOut | Select-String -Pattern 'connected' -Quiet)) {
        Write-Host 'rman connection using the provided catalog is incorrect'
        $catOut | ForEach-Object { Write-Host $_ }
        Fail 'catalog syntax can be like "<catalog user>/<password>@<catalog connect string>"'
    }
    Write-Host 'rman catalog connect is successful. Continue'
}

# ------------------------------------------------------------------
# Oracle edition / license
# ------------------------------------------------------------------

function Get-OracleLicense {
    Write-Host "`nCheck the Oracle Edition`n"
    $sql = @"
SELECT CASE
  WHEN banner LIKE '%Enterprise Edition%' THEN 'ENTERPRISE'
  WHEN banner LIKE '%Standard Edition%'   THEN 'STANDARD'
  ELSE 'UNKNOWN' END AS edition
FROM v`$version WHERE banner LIKE 'Oracle Database%';
"@
    Invoke-Sqlplus -Sql $sql -SpoolFile $stdout
    $lic = (Get-OracleSpoolValue -SpoolFile $stdout).Trim()
    Write-Host "Oracle Edition is $lic"
    return $lic
}

# ------------------------------------------------------------------
# Locate controlfile backup + build spfile/controlfile restore scripts
# ------------------------------------------------------------------

$script:backupdir = $null
$script:db_name   = $null
$script:controlfile = $null
$script:srcDbid = $null

# Use the controlfile backup name / DBID supplied by the user (no sbt_list on Windows).
# The SBT directory is <BackupHost>/<DbName>; its case must match the backup directory in the view.
function Find-ControlfileBackup {
    param([string]$Ip)

    $script:backupdir = "$BackupHost/$DbName"
    $script:db_name   = $DbName

    if ($ControlfileBackup) {
        $script:controlfile = $ControlfileBackup
        Write-Host "The controlfile is $script:controlfile"
    }

    if ($Dbid) {
        $script:srcDbid = $Dbid
    }
    elseif ($ControlfileBackup -match '(?i)c-(\d+)-') {
        $script:srcDbid = $Matches[1]
    }
    else {
        Fail "Could not derive the DBID from controlfile backup name '$ControlfileBackup' (expected like ORCL_c-1234567890-20260127-00). Provide -Dbid." 2
    }
    Write-Host "dbid of this database is $script:srcDbid"
}

# Emit a set-dbid / restore block for spfile or controlfile.
function Get-CtlRestoreBlock {
    param([string]$DataView, [string]$Ip, [string]$AutobackupFormat, [string]$RestoreStmt)
    return @"
set dbid $script:srcDbid;
set CONTROLFILE AUTOBACKUP FORMAT FOR DEVICE TYPE sbt_tape TO '$AutobackupFormat';
run {
allocate CHANNEL c1 TYPE 'SBT_TAPE' PARMS $(Build-ChannelParms -DataView $DataView -Ip $Ip);
$RestoreStmt
release CHANNEL c1;
}
"@
}

function New-ControlfileRestoreScripts {
    param([bool]$UseCatalog)
    $ip = Get-FirstVip
    Find-ControlfileBackup -Ip $ip

    if ($UseCatalog) {
        $dv = $View
        $fmt = "$BackupHost/$script:db_name/%d_%F.ctl"
        $spfileStmt = 'restore spfile FROM AUTOBACKUP;'
        $ctlStmt    = 'restore CONTROLFILE FROM AUTOBACKUP;'
    }
    else {
        $dv = "$View/$script:backupdir"
        $fmt = '%d_%F.ctl'
        $spfileStmt = "restore spfile from '$script:controlfile';"
        $ctlStmt    = "restore CONTROLFILE from '$script:controlfile';"
    }

    Write-Host 'will create spfile rman restore script'
    Set-Content -Path $spfile_rmanfile -Value (Get-CtlRestoreBlock -DataView $dv -Ip $ip -AutobackupFormat $fmt -RestoreStmt $spfileStmt)

    Write-Host 'will create controlfile rman restore script'
    Set-Content -Path $controlfile_rmanfile -Value (Get-CtlRestoreBlock -DataView $dv -Ip $ip -AutobackupFormat $fmt -RestoreStmt $ctlStmt)
}

# ------------------------------------------------------------------
# Build restore / recover database scripts
# ------------------------------------------------------------------

function Get-UntilTimeLine {
    if ($PointInTime) {
        return "set until time `"to_date('$PointInTime','YYYY/MM/DD HH24:MI:SS')`";"
    }
    return $null
}

function New-RestoreDatabaseScript {
    $ip = Get-FirstVip
    Write-Host 'Create rman restore database file'
    $lines = New-Object System.Collections.Generic.List[string]

    $parms = Build-ChannelParms -DataView $View -Ip $ip
    $lines.Add("ALLOCATE CHANNEL FOR MAINTENANCE DEVICE TYPE 'SBT_TAPE' PARMS $parms;")
    $lines.Add("CONFIGURE CHANNEL DEVICE TYPE 'SBT_TAPE' PARMS $parms;")

    if ($Parallel -eq 1) {
        $lines.Add('CONFIGURE DEVICE TYPE SBT_TAPE PARALLELISM 1 BACKUP TYPE TO BACKUPSET;')
    }
    else {
        $lines.Add('RUN {')
        # Spread the channels across all VIPs (round-robin)
        for ($j = 0; $j -lt $Parallel; $j++) {
            $chIp = $Global:Vips[$j % $Global:Vips.Count]
            $lines.Add("allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS $(Build-ChannelParms -DataView $View -Ip $chIp);")
        }
    }

    $until = Get-UntilTimeLine
    if ($until) { Write-Host "Set recover time until $PointInTime"; $lines.Add($until) }

    if ($Force) { $lines.Add('restore database;') } else { $lines.Add('restore database validate;') }

    if ($Parallel -gt 1) { $lines.Add('}') }

    Set-Content -Path $restore_rmanfile -Value $lines
    Write-Host 'finished creating rman restore database file'
}

function New-RecoverDatabaseScript {
    Write-Host 'Create rman recover database file'
    $lines = New-Object System.Collections.Generic.List[string]

    if ($Parallel -gt 1) {
        $lines.Add('RUN {')
        for ($j = 0; $j -lt $Parallel; $j++) {
            $chIp = $Global:Vips[$j % $Global:Vips.Count]
            $lines.Add("allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS $(Build-ChannelParms -DataView $View -Ip $chIp);")
        }
    }

    $until = Get-UntilTimeLine
    if ($until) { $lines.Add($until) }

    $lines.Add('recover database;')

    if ($Parallel -gt 1) { $lines.Add('}') }

    if (-not $Force) {
        $lines.Add('exit;')
    }
    else {
        if ($RestoreControlfile) { $lines.Add('alter database open resetlogs;'); $lines.Add('exit;') }
        elseif ($PointInTime)    { $lines.Add('alter database open resetlogs;'); $lines.Add('exit;') }
        else                     { $lines.Add('alter database open;'); $lines.Add('exit;') }
    }

    Set-Content -Path $recover_rmanfile -Value $lines
    Write-Host 'finished creating rman recover database file'
}

# ------------------------------------------------------------------
# Instance / service helpers
# ------------------------------------------------------------------

# Make sure the Windows service that hosts the instance is Running (required before any STARTUP
# on Windows).
function Start-OracleInstanceService {
    param([string]$Sid)
    foreach ($name in @("OracleService$Sid", "OracleService$($Sid.ToUpper())")) {
        $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
        if ($svc) {
            if ($svc.Status -ne 'Running') {
                Write-Host "Starting Windows service $name"
                try { Start-Service -Name $name -ErrorAction Stop; Start-Sleep -Seconds 3 }
                catch { Write-Host "Could not start $name : $_" }
            }
            return $true
        }
    }
    Write-Host "WARNING: Windows service OracleService$Sid not found. The instance service must exist (create it with oradim) before the instance can start."
    return $false
}

# Read V$INSTANCE.STATUS and map it to the instance mode - DOWN / NOMOUNT / MOUNT / OPEN / UNKNOWN.
# More reliable than the old service-only check, because on Windows OracleService<SID> can be
# Running while the instance is idle (DOWN).
function Get-OracleDbMode {
    param([string]$Sid)
    $env:ORACLE_SID = $Sid
    $spool = Join-Path $logDir "$Sid.status.$DATE_SUFFIX.log"
    Invoke-Sqlplus -Sql "select status from v`$instance;" -SpoolFile $spool

    # Idle instance / instance not started -> ORA-01034 (or SQL*Plus "idle instance")
    if ((Test-Path $spool) -and (Select-String -Path $spool -Pattern 'ORA-01034|idle instance' -Quiet)) {
        return 'DOWN'
    }

    $st = (Get-OracleSpoolValue -SpoolFile $spool).Trim().ToUpper()
    if (-not $st) { return 'DOWN' }
    switch -Regex ($st) {
        '^STARTED' { return 'NOMOUNT' }   # instance started, DB not mounted
        '^MOUNTED' { return 'MOUNT' }     # control file mounted, DB not open
        '^OPEN'    { return 'OPEN' }      # covers OPEN and OPEN MIGRATE
        default    { return 'UNKNOWN' }
    }
}

function Confirm-Yes {
    param([string]$Prompt)
    $ans = Read-Host $Prompt
    return ($ans -match '^[Yy]')
}

# ------------------------------------------------------------------
# check init file
# ------------------------------------------------------------------

function Confirm-OracleInitFile {
    $pfile = Join-Path $dbsDir "init$OracleSid.ora"
    if (-not (Test-Path $pfile)) {
        Write-Host "The oracle pfile $pfile doesn't exist. Please make sure the instance name is correct."
        if (-not (Confirm-Yes 'If the instance name is correct and you want to continue without the pfile, type YES to continue, anything else to cancel')) {
            exit 2
        }
    }
}

# ------------------------------------------------------------------
# restore controlfile (start nomount, restore spfile + controlfile, mount)
# ------------------------------------------------------------------

$script:incar_num1 = $null

function Restore-Controlfile {
    Write-Host 'will restore controlfile'
    Write-Host 'check the instance state'

    Start-OracleInstanceService -Sid $OracleSid | Out-Null

    $mode = Get-OracleDbMode -Sid $OracleSid
    Write-Host "Oracle database $OracleSid current mode is $mode"

    switch ($mode) {
        'DOWN' {
            Write-Host "Oracle database $OracleSid is not up"
            Write-Host 'start the database in nomount, restore spfile, and restart the database in nomount'
            Invoke-RmanRaw -Commands 'startup nomount;' | Out-Null
            Write-Host "spfile restore started at $(Get-TimeStamp)"
            Invoke-Rman -CommandFile $spfile_rmanfile -LogFile $spfile_rmanlog | Out-Null
            Invoke-RmanRaw -Commands "shutdown immediate;`nstartup nomount;" | Out-Null
        }
        { $_ -in 'NOMOUNT', 'MOUNT', 'OPEN' } {
            Write-Host "Oracle database $OracleSid is up ($mode)"
            Write-Host 'shutdown the database first, start it in nomount, restore spfile, restart in nomount'
            Invoke-RmanRaw -Commands 'shutdown immediate;' | Out-Null
            Invoke-RmanRaw -Commands 'startup nomount;' | Out-Null
            Invoke-Rman -CommandFile $spfile_rmanfile -LogFile $spfile_rmanlog | Out-Null
            Invoke-RmanRaw -Commands "shutdown immediate;`nstartup nomount;" | Out-Null
        }
        default {
            Fail "Could not determine the mode of instance $OracleSid (status UNKNOWN). Check the Windows service, ORACLE_SID, and SYSDBA privileges."
        }
    }

    Write-Host 'The instance should be in nomount mode. If not, exit'
    $mode = Get-OracleDbMode -Sid $OracleSid
    if ($mode -ne 'NOMOUNT') {
        Fail "Oracle database $OracleSid is not in nomount mode (current mode is $mode)"
    }

    Write-Host "restore controlfile $script:controlfile"
    Invoke-Rman -CommandFile $controlfile_rmanfile -LogFile $controlfile_rmanlog | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "restore controlfile $script:controlfile failed at $(Get-TimeStamp)"
        Get-ChildItem -Path (Join-Path $dbsDir 'SPFILE*') -ErrorAction SilentlyContinue | Format-Table | Out-String | Write-Host
        Write-Host "rmanlog file is $controlfile_rmanlog"
        if (Test-Path $controlfile_rmanlog) { Get-Content -Path $controlfile_rmanlog -Tail 10 | ForEach-Object { Write-Host $_ } }
        exit 1
    }
    Write-Host "restore controlfile finished at $(Get-TimeStamp)"

    Write-Host 'Change database to mount mode'
    Invoke-SqlplusScript -Sql 'alter database mount;' | Out-Null

    $mode = Get-OracleDbMode -Sid $OracleSid
    Write-Host "database instance is in $mode mode"
    if ($mode -ne 'MOUNT') { Fail 'database is not in mount mode' }

    Write-Host 'incarnation after new controlfile'
    Invoke-RmanRaw -Commands 'list incarnation of database;' -LogFile $incarnation | Out-Null
    $script:incar_num1 = Get-CurrentIncarnation
    Write-Host "Oracle database incarnation is $script:incar_num1"

    if ((Test-Path $controlfile_rmanlog) -and (Select-String -Path $controlfile_rmanlog -Pattern 'error' -Quiet)) {
        Fail 'Controlfile restore failed'
    }
}

function Get-CurrentIncarnation {
    if (-not (Test-Path $incarnation)) { return $null }
    foreach ($line in (Get-Content -Path $incarnation)) {
        if ($line -match "(?i)$([regex]::Escape($DbName))" -and $line -match '(?i)CURRENT') {
            $tokens = ($line.Trim() -split '\s+')
            if ($tokens.Count -ge 2) { return $tokens[1] }
        }
    }
    return $null
}

function Reset-IncarnationAfterRestore {
    Write-Host 'incarnation after restore'
    Invoke-RmanRaw -Commands 'list incarnation of database;' -LogFile $incarnation | Out-Null
    $incar_num2 = Get-CurrentIncarnation
    Write-Host "Oracle database incarnation is $incar_num2"

    if ($script:incar_num1 -ne $incar_num2) {
        Write-Host 'reset database incarnation'
        Invoke-RmanRaw -Commands "reset database to incarnation $script:incar_num1;" | Out-Null
    }
    else {
        Write-Host 'no need to reset database incarnation'
    }
}

# ------------------------------------------------------------------
# restore / recover
# ------------------------------------------------------------------

function Invoke-RestoreValidate {
    Write-Host "Database restore validate started at $(Get-TimeStamp)"
    Write-Host "ORACLE SID is $OracleSid"
    Invoke-Rman -CommandFile $restore_rmanfile -LogFile $restore_rmanlog | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Database restore validate failed at $(Get-TimeStamp)"
        Write-Host "rmanlog file is $restore_rmanlog"
        if (Test-Path $restore_rmanlog) { Get-Content -Path $restore_rmanlog -Tail 10 | ForEach-Object { Write-Host $_ } }
        exit 1
    }
    Write-Host "Database restore validate finished at $(Get-TimeStamp)"
}

function Invoke-RestoreDatabase {
    Write-Host "Database restore started at $(Get-TimeStamp)"
    Write-Host "ORACLE SID is $OracleSid"

    Start-OracleInstanceService -Sid $OracleSid | Out-Null

    $mode = Get-OracleDbMode -Sid $OracleSid
    Write-Host "database instance is in $mode mode"

    switch ($mode) {
        'MOUNT' {
            Write-Host "Oracle database $OracleSid is in mount mode"
            if ($Force -and -not $RestoreControlfile) {
                if (-not (Confirm-Yes "The restore will overwrite the database $DbName. Type YES to confirm, anything else to cancel")) {
                    Fail 'restore will not start at this point'
                }
            }
        }
        'DOWN' {
            Write-Host "Oracle database $OracleSid is not up; starting it in mount mode"
            Invoke-SqlplusScript -Sql 'startup mount;' | Out-Null
        }
        { $_ -in 'NOMOUNT', 'OPEN' } {
            Write-Host "Oracle database $OracleSid is in $mode mode; restarting it in mount mode"
            Invoke-SqlplusScript -Sql "shutdown immediate;`nstartup mount;" | Out-Null
        }
        default {
            Fail "Could not determine the mode of instance $OracleSid (status UNKNOWN). Check the Windows service, ORACLE_SID, and SYSDBA privileges."
        }
    }

    Invoke-Rman -CommandFile $restore_rmanfile -LogFile $restore_rmanlog | Out-Null
    $restoreRc = $LASTEXITCODE
    Invoke-Rman -CommandFile $recover_rmanfile -LogFile $recover_rmanlog | Out-Null
    $recoverRc = $LASTEXITCODE

    if ($restoreRc -ne 0 -or $recoverRc -ne 0) {
        Write-Host "Database restore failed at $(Get-TimeStamp)"
        Write-Host "rmanlog files: $restore_rmanlog , $recover_rmanlog"
        if (Test-Path $restore_rmanlog) { Get-Content -Path $restore_rmanlog -Tail 10 | ForEach-Object { Write-Host $_ } }
        if (Test-Path $recover_rmanlog) { Get-Content -Path $recover_rmanlog -Tail 10 | ForEach-Object { Write-Host $_ } }
        exit 1
    }
    Write-Host "Database restore finished at $(Get-TimeStamp)"
}

function Open-CdbPdb {
    Invoke-Sqlplus -Sql "select name from v`$pdbs;" -SpoolFile $stdout
    $pdbname = Get-OracleSpoolValue -SpoolFile $stdout

    if ($pdbname -match 'PDB') {
        Write-Host 'This database is a multi-tenant database. Will open all pluggable databases'
        Invoke-SqlplusScript -Sql 'ALTER PLUGGABLE DATABASE ALL OPEN;' | Out-Null
    }
    else {
        Write-Host 'This database is not a multi-tenant database.'
    }

    Write-Host 'Check the database status'
    Invoke-SqlplusScript -Sql "select INSTANCE_NAME, STATUS from gv`$instance;`nCOL name FORMAT a20`nselect INST_ID, name, open_mode from gv`$pdbs;"
}

# ------------------------------------------------------------------
# Main
# ------------------------------------------------------------------

$ora_license = Get-OracleLicense
if ($ora_license -eq 'STANDARD') {
    Write-Host "`nSince the Oracle edition is Standard, only one RMAN channel will be used for the restore`n"
    $Parallel = 1
}

if ($Preview) {
    if ($RestoreControlfile) {
        New-ControlfileRestoreScripts -UseCatalog:([bool]$CatalogConnect)
        Write-Host "`nORACLE spfile restore RMAN SCRIPT`n---------------"
        Get-Content -Path $spfile_rmanfile | ForEach-Object { Write-Host $_ }
        Write-Host "`nORACLE controlfile restore RMAN SCRIPT`n---------------"
        Get-Content -Path $controlfile_rmanfile | ForEach-Object { Write-Host $_ }
        Write-Host '---------------'
    }
    New-RestoreDatabaseScript
    Write-Host "`nORACLE restore RMAN SCRIPT`n---------------"
    Get-Content -Path $restore_rmanfile | ForEach-Object { Write-Host $_ }
    Write-Host '---------------'
    New-RecoverDatabaseScript
    Write-Host "`nORACLE recovery RMAN SCRIPT`n---------------"
    Get-Content -Path $recover_rmanfile | ForEach-Object { Write-Host $_ }
    Write-Host '---------------'
    exit 0
}

if (-not $Force) {
    New-RestoreDatabaseScript
    Write-Host 'run rman restore validate. It will NOT overwrite the current database'
    Invoke-RestoreValidate
    Write-Host "restore validate time is in rman log $restore_rmanlog"
    Write-Host 'check the start time and Finished restore time'
    exit 0
}

if ($RestoreControlfile) {
    Write-Host 'The following procedure will restore spfile, controlfiles, and datafiles'
    Confirm-OracleInitFile
    if (-not (Confirm-Yes 'Any data in the FRA area for this database should be deleted. Type YES to continue, anything else to cancel')) {
        Fail 'stop the restore' 0
    }
    if ($machine -eq $BackupHost) {
        if (-not (Confirm-Yes "The database $DbName will be overwritten. Type YES to confirm, anything else to cancel")) {
            Fail "Restore database $DbName isn't executed." 0
        }
    }
    else {
        Write-Host "The database $DbName will be overwritten."
    }
    New-ControlfileRestoreScripts -UseCatalog:([bool]$CatalogConnect)
    Restore-Controlfile
}

New-RestoreDatabaseScript
New-RecoverDatabaseScript
Invoke-RestoreDatabase
Open-CdbPdb
Write-Host "restore time is in rman log $restore_rmanlog and $recover_rmanlog"
Write-Host 'check the start and finish time in the logs'
