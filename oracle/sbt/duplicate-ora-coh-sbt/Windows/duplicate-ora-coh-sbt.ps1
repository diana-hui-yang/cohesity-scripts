<#
.SYNOPSIS
    Duplicate an Oracle database from a Cohesity SBT backup taken by backup-ora-coh-sbt.ps1
    (Windows / PowerShell port).

.DESCRIPTION
    PowerShell port of duplicate-ora-coh-sbt.bash (Diana Yang).
    Windows standalone version:
      * RAC source enumeration is dropped (single-instance source assumed).
      * ORACLE_HOME must be supplied (-OracleHome); it is not read from the environment.
      * The instance is hosted by the Windows service OracleService<SID>. The instance state is
        read from V$INSTANCE.STATUS (DOWN / NOMOUNT / MOUNT / OPEN), which is more reliable than
        the old service-only check (on Windows the service can be Running while the instance is idle).
      * pfile/spfile are looked for under ORACLE_HOME\database (Linux: dbs).

    It duplicates a whole database (or a pluggable database) from an SBT backup, using the source
    (target) database connection and/or an RMAN catalog. It supports point-in-time (-PointInTime) or
    log-sequence (-Sequence) recovery, and the auxiliary-CDB flow for restoring a PDB into an
    existing target CDB (-AuxiliaryDb / -NewPdb / -PdbCopy), for which it generates PowerShell helper
    scripts (unplug / plug / destroy-auxiliary) and runs them.

.EXAMPLE
    # Duplicate a whole database to target SID dupdb
    .\duplicate-ora-coh-sbt.ps1 -TargetSid dupdb -OracleHome "C:\app\oracle\product\19.0.0\dbhome_1" `
        -View oraback -CohesityName cohesity.example.com `
        -SourceConnect "sys/pw@srchost:1521/orcl as sysbackup" -SourceHost srchost -Force

.EXAMPLE
    # Point-in-time duplicate
    .\duplicate-ora-coh-sbt.ps1 -TargetSid dupdb -OracleHome "C:\app\oracle\product\19.0.0\dbhome_1" `
        -View oraback -CohesityName cohesity.example.com -SourceConnect "sys/pw@srchost/orcl as sysbackup" `
        -PointInTime "2026-01-27 13:00:00" -RestoreSettingFile .\config\newname.txt -Force
#>

[CmdletBinding()]
param(
    [Alias('i')]
    [string]$TargetSid,

    [Alias('v')]
    [string]$View,

    [Alias('o')]
    [string]$OracleHome,

    [Alias('r')]
    [string]$SourceConnect,

    [Alias('c')]
    [string]$CatalogConnect,

    [Alias('h')]
    [string]$SourceHost,

    [Alias('d')]
    [string]$SourceDbName,

    # File with RMAN restore-location settings, e.g. set newname for database to 'D:\oradata\dup\%b';
    [Alias('b')]
    [string]$RestoreSettingFile,

    [Alias('t')]
    [string]$PointInTime,

    [Alias('e')]
    [int]$Sequence,

    [Alias('y')]
    [string]$CohesityName,

    [Alias('j')]
    [string]$VipFile,

    [Alias('s')]
    [string]$SbtLibrary,

    [Alias('p')]
    [int]$Parallel = 4,

    # Source pluggable database to duplicate (omit for whole-DB / CDB duplication)
    [Alias('u')]
    [string]$SourcePdb,

    # Destination pluggable database name (needs -AuxiliaryDb)
    [Alias('n')]
    [string]$NewPdb,

    # yes = plug the PDB with COPY; default nocopy (file structure not moved from auxiliary to target)
    [Alias('l')]
    [ValidateSet('yes', 'Yes', 'YES', 'no', 'No', 'NO')]
    [string]$PdbCopy,

    # Temporary auxiliary CDB used to restore a PDB into an existing target CDB
    [Alias('a')]
    [string]$AuxiliaryDb,

    # -f: force / refresh the target database without prompting
    [Alias('f')]
    [switch]$Force,

    # -m: Oracle duplicate NORESUME
    [Alias('m')]
    [switch]$NoResume,

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
    if (-not $scriptName) { $scriptName = "duplicate-ora-coh-sbt.ps1" }

    Write-Host @"
Usage: .\$scriptName -TargetSid <Target Oracle_DB_Name> -View <view> -OracleHome <ORACLE_HOME> -SourceConnect <Source ORACLE connection> -SourceHost <backup host> -CatalogConnect <Catalog connection> -PointInTime <point-in-time> -Sequence <sequence> -RestoreSettingFile <file> -CohesityName <Cohesity-cluster> -VipFile <vip file> -SbtLibrary <sbt home> -Parallel <channels> -SourcePdb <source PDB> -NewPdb <new PDB name> -PdbCopy <yes/no> -AuxiliaryDb <aux CDB> -Encryption <yes/no> -EncryptionCertFile <cert> -Grpc <yes/no> [-Force] [-NoResume] [-Preview]

 (Each long name has a single-letter alias shown in parentheses, matching the original bash flags.)

 Required Parameters
 -TargetSid         (-i) : Target Oracle instance name (the duplicate database)
 -SourceConnect     (-r) : Source Oracle connection (example: "sys/<password>@<source connect string> as sysbackup")
 -View              (-v) : Cohesity View that holds the backup
 -OracleHome        (-o) : ORACLE_HOME (the folder that contains the bin directory)

 Optional Parameters
 -CatalogConnect    (-c) : RMAN Catalog connection (example: "<dbuser>/<dbpass>@<catalog connection string>")
 -SourceHost        (-h) : Source host - the Oracle database host the backup was run on
 -SourceDbName      (-d) : Deprecated - the source DB name is derived from -SourceConnect
 -PointInTime       (-t) : Point in Time (format example: "2026-01-27 13:00:00")
 -Sequence          (-e) : Log sequence number of thread 1 (use either -PointInTime or -Sequence, not both)
 -RestoreSettingFile(-b) : File with RMAN restore-location settings (e.g. set newname for database to 'D:\dup\%b';)
 -CohesityName      (-y) : Cohesity Cluster DNS name (VIPs resolved automatically)
 -VipFile           (-j) : File listing Cohesity Cluster VIPs (default name vip-list, default dir config)
 -SbtLibrary        (-s) : Cohesity SBT library name including directory or just directory (default dir lib)
 -Parallel          (-p) : number of channels (default is 4)
 -SourcePdb         (-u) : Source pluggable database (omit for standalone/CDB duplication)
 -NewPdb            (-n) : Destination pluggable database name (needs -AuxiliaryDb)
 -PdbCopy           (-l) : yes = plug PDB with COPY; default nocopy
 -AuxiliaryDb       (-a) : Temporary auxiliary CDB for restoring a PDB into an existing target CDB
 -Encryption        (-g) : yes means encryption-in-flight is used. Default is no
 -EncryptionCertFile(-k) : encryption certificate file, default directory is lib if full path not provided
 -Grpc              (-x) : yes means gRPC is used, no means SunRPC is used. Default is yes
 -Force             (-f) : switch (no value). Refresh/overwrite the target database without prompting.
 -NoResume          (-m) : switch (no value). Use Oracle duplicate NORESUME.
 -Preview           (-w) : switch (no value). Print the generated RMAN duplicate script without running it.

"@
}

if (-not $TargetSid) {
    Write-Host "

    Missing TargetSid parameter. It is required.

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

if (-not $SourceConnect -and -not $CatalogConnect) {
    Write-Host "

    Missing SourceConnect (-r) or CatalogConnect (-c). At least one is required.

    "
    Show-Usage
    exit 1
}

if ($NewPdb -and -not $AuxiliaryDb) {
    Write-Host 'An auxiliary database (-AuxiliaryDb) must be used to restore a PDB into a new CDB with a new PDB name'
    exit 1
}

if ($PointInTime -and $PointInTime -match '"') {
    Write-Host 'There should not be quote characters inside -PointInTime. Use e.g. "2026-01-27 13:00:00".'
    exit 2
}

if ($PSBoundParameters.ContainsKey('PointInTime') -and $PSBoundParameters.ContainsKey('Sequence')) {
    Write-Host 'Either -PointInTime or -Sequence may be entered. This script does not take both.'
    exit 2
}

$ErrorActionPreference = 'Continue'

# ------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------

function Get-TimeStamp { return (Get-Date -Format 'yyyyMMddHHmmss') }

function Test-Yes { param([string]$Value) return ($Value -match '^[Yy]') }

function Fail { param([string]$Message, [int]$Code = 1) Write-Host $Message; exit $Code }

function Confirm-Yes {
    param([string]$Prompt)
    $ans = Read-Host $Prompt
    return ($ans -match '^[Yy]')
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

# Run a SQL query as "/ as sysdba" (uses current $env:ORACLE_SID), spooling to $SpoolFile.
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

# Run a SQL query against the SOURCE database connection, spooling to $SpoolFile.
function Invoke-SqlplusSource {
    param([string]$Sql, [string]$SpoolFile)
    if (-not $Global:SourceSqlLogon) { return }
    if (Test-Path $SpoolFile) { Remove-Item -Path $SpoolFile -Force -ErrorAction SilentlyContinue }
    $body = @"
set echo off
set feedback off
spool "$SpoolFile"
$Sql
spool off
exit
"@
    $body | & $Global:SqlplusExe -S -L $Global:SourceSqlLogon | Out-Null
}

# Run arbitrary SQL*Plus commands as "/ as sysdba" (no spool).
function Invoke-SqlplusScript {
    param([string]$Sql)
    "$Sql`nexit`n" | & $Global:SqlplusExe -S -L '/ as sysdba'
}

# SBT_PARMS(...) for an auxiliary channel (duplicate uses data_view=<view>, gflag form for SunRPC).
function Build-SbtParms {
    param([string]$Ip)
    $p = "data_view=$View,vips=$Ip"
    if (-not (Test-Yes $Grpc))  { $p += ',gflag-name=sbt_use_grpc,gflag-value=false' }
    if (Test-Yes $Encryption)   { $p += ",sbt_certificate_file=$Global:EncryptCert" }
    return $p
}

function Build-AuxChannelParms {
    param([string]$Ip)
    return "'SBT_LIBRARY=$Global:Sbt,SBT_PARMS=($(Build-SbtParms -Ip $Ip))'"
}

function Get-FirstVip {
    foreach ($v in (Get-Content -Path $Global:VipFilePath)) {
        $t = $v.Trim()
        if ($t) { return $t }
    }
    return $null
}

# ------------------------------------------------------------------
# Instance state helpers
# (replace the old Test-OracleInstanceUp / Start-OracleService pair)
#
#   Start-OracleInstanceService : make sure the Windows service that hosts the
#                                 instance is Running (required before any STARTUP
#                                 on Windows).
#   Get-OracleDbMode            : read V$INSTANCE.STATUS and map it to the open
#                                 mode - DOWN / NOMOUNT / MOUNT / OPEN / UNKNOWN.
#                                 This is more reliable than the old service-only
#                                 check, because on Windows OracleService<SID> can
#                                 be Running while the instance is idle (DOWN).
#   Set-OracleNomount          : guarantee the instance ends up in NOMOUNT:
#                                   * DOWN                -> STARTUP NOMOUNT
#                                   * NOMOUNT/MOUNT/OPEN  -> SHUTDOWN IMMEDIATE + STARTUP NOMOUNT
#                                 Honors -ForceRefresh (no prompt) and an optional
#                                 confirmation prompt (used when the instance is up
#                                 and -Force was not supplied).
# ------------------------------------------------------------------

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
    Write-Host "WARNING: Windows service OracleService$Sid not found. Create the instance service with oradim before duplicating."
    return $false
}

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

function Set-OracleNomount {
    param(
        [string]$Sid,
        [string]$Pfile,
        [switch]$ForceRefresh,
        [string]$ConfirmPrompt
    )

    # Windows: the service must be Running before STARTUP can work.
    Start-OracleInstanceService -Sid $Sid | Out-Null

    $mode = Get-OracleDbMode -Sid $Sid
    Write-Host "Oracle database $Sid current mode is $mode"

    switch ($mode) {
        'DOWN' {
            Write-Host "Oracle database $Sid is not up; start the database in nomount mode"
            Invoke-SqlplusScript -Sql "startup nomount pfile='$Pfile';" | Out-Null
        }
        { $_ -in 'NOMOUNT', 'MOUNT', 'OPEN' } {
            if ($ForceRefresh) {
                Write-Host "Oracle database is in $mode mode. Will shut it down and start in nomount mode (target will be refreshed)"
                Invoke-SqlplusScript -Sql "shutdown immediate;`nstartup nomount pfile='$Pfile';" | Out-Null
            }
            else {
                if ($ConfirmPrompt -and -not (Confirm-Yes $ConfirmPrompt)) {
                    Write-Host "If this is PDB duplication, using an auxiliary database allows the target database $Sid to stay up"
                    exit 0
                }
                Invoke-SqlplusScript -Sql "shutdown immediate;`nstartup nomount pfile='$Pfile';" | Out-Null
            }
        }
        default {
            Fail "Could not determine the mode of instance $Sid (status UNKNOWN). Check the Windows service, ORACLE_SID, and SYSDBA privileges."
        }
    }
}

# ------------------------------------------------------------------
# Setup
# ------------------------------------------------------------------

# Target host = the host this duplicate runs on
$thost = $env:COMPUTERNAME

if ($Parallel -le 0) { Write-Host 'no input for parallel, set parallel to be 4'; $Parallel = 4 }

# ORACLE_HOME / executables
if (-not (Test-Path $OracleHome)) { Fail "ORACLE_HOME '$OracleHome' does not exist." }
$env:ORACLE_HOME = $OracleHome
$env:PATH = "$OracleHome\bin;$env:PATH"
$env:NLS_DATE_FORMAT = 'DD:MM:YYYY-HH24:MI:SS'

$Global:RmanExe    = Join-Path $OracleHome 'bin\rman.exe'
$Global:SqlplusExe = Join-Path $OracleHome 'bin\sqlplus.exe'
if (-not (Test-Path $Global:RmanExe))    { Fail "rman.exe not found under '$OracleHome\bin'. Check -OracleHome." }
if (-not (Test-Path $Global:SqlplusExe)) { Fail "sqlplus.exe not found under '$OracleHome\bin'. Check -OracleHome." }

$dbsDir = Join-Path $OracleHome 'database'   # Windows pfile/spfile location (Linux: $ORACLE_HOME/dbs)

$DATE_SUFFIX = Get-TimeStamp

$DIR = $PSScriptRoot
if (-not $DIR) { $DIR = (Get-Location).Path }

if ($SourceDbName) { Write-Host '-SourceDbName (-d) is no longer required. Source database is derived from -SourceConnect.' }

# ------------------------------------------------------------------
# Parse source / catalog connections, derive source host
# ------------------------------------------------------------------

$Global:SourceSqlLogon = $null
$shost = $SourceHost
$hostdefined = [bool]$SourceHost

if ($SourceConnect) {
    # test source database connection
    $srcOut = "connect target '$SourceConnect'`nexit;`n" | & $Global:RmanExe 2>&1
    if (-not ($srcOut | Select-String -Pattern 'connected' -Quiet)) {
        Write-Host "rman connection using the provided -SourceConnect is incorrect"
        $srcOut | ForEach-Object { Write-Host $_ }
        Fail 'Source Oracle connection syntax should be "sys/<password>@<connect string>" or "<user>/<pass>@<connect string> as sysbackup"'
    }
    Write-Host 'rman target (source) connection is successful. Continue'
}

if ($CatalogConnect) {
    $catOut = "connect catalog '$CatalogConnect'`nexit;`n" | & $Global:RmanExe 2>&1
    if (-not ($catOut | Select-String -Pattern 'connected' -Quiet)) {
        Write-Host 'rman connection using the provided -CatalogConnect is incorrect'
        $catOut | ForEach-Object { Write-Host $_ }
        Fail 'catalog syntax can be like "<catalog user>/<password>@<catalog connect string>"'
    }
    Write-Host 'rman catalog connect is successful. Continue'
}

if ($SourceConnect) {
    Write-Host 'Will use source (target) connection to duplicate the database'
    $CatalogConnect = ''    # prefer target connection over catalog, mirroring the bash logic

    $cred = ($SourceConnect -split '@')[0]
    $afterAt = ($SourceConnect -split '@', 2)[1]
    $conn = ($afterAt -split '\s+')[0]
    $systype = if ($afterAt -match '\s+as\s+(\w+)') { $Matches[1] } else { 'sysdba' }

    if (-not $shost) {
        if ($conn -match '/') {
            $shost = ($conn -split '/')[0]
            if ($shost -match ':') { $shost = ($shost -split ':')[0] }
        }
        else {
            $shost = $conn   # best effort; tnsping is not used on Windows
            Write-Host "Could not derive source host from the connect string; using '$shost'. Pass -SourceHost to override."
        }
    }
    else { $hostdefined = $true }

    if ($shost -match '\.') { $shostshort = ($shost -split '\.')[0] } else { $shostshort = $shost }
    $Global:SourceSqlLogon = "$cred@$conn as $systype"
}

Write-Host "The backup was taken from host $shost"

# RestoreSettingFile existence
if ($RestoreSettingFile -and -not (Test-Path $RestoreSettingFile)) {
    Fail "there is no $RestoreSettingFile. It is the file defined by -RestoreSettingFile"
}

# Log and config directories
$logDir    = Join-Path $DIR "log\$thost"
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
    Write-Host 'This backup will use encryption-in-flight'
    if (-not $EncryptionCertFile) { Fail "Encryption is enabled but no -EncryptionCertFile was provided. Exit" }
    if ([string]::IsNullOrEmpty((Split-Path -Parent $EncryptionCertFile))) {
        $certPath = Join-Path (Join-Path $DIR 'lib') $EncryptionCertFile
    }
    else { $certPath = $EncryptionCertFile }
    if (Test-Path $certPath -PathType Leaf) {
        $Global:EncryptCert = (Resolve-Path $certPath).Path
        Write-Host "encryption certificate is $Global:EncryptCert"
        Write-Host 'encryption certificate exists, script continue'
    }
    else { Fail "Encryption certificate file not found: $certPath. Exit" }
}

# VIP list (shuffled, like the bash 'shuf')
if (-not $CohesityName) {
    if (-not $VipFile) { $VipFile = Join-Path $configDir 'vip-list' }
    Write-Host "Cohesity Cluster name is not provided, we will use vipfile $VipFile"
    if (-not (Test-Path $VipFile)) { Fail "file $VipFile provided does not exist" }
    Write-Host "file $VipFile provided exists, script continue"
}
else {
    $VipFile = Join-Path $configDir "$TargetSid-dup-vip-list"
    Write-Host "Cohesity Cluster name is $CohesityName. VIPS will be collected and stored in $VipFile"
    try {
        $resolved = Resolve-DnsName -Name $CohesityName -Type A -ErrorAction Stop |
            Where-Object { $_.IPAddress } | Select-Object -ExpandProperty IPAddress
    }
    catch { $resolved = @() }
    if (-not $resolved -or $resolved.Count -eq 0) { Fail "Cohesity Cluster name $CohesityName provided here is not in DNS" }
    Set-Content -Path $VipFile -Value ($resolved | Get-Random -Count $resolved.Count)
}
$Global:VipFilePath = $VipFile
if (-not (Get-FirstVip)) { Fail "No VIPs found in $VipFile" }

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

# Log / RMAN / helper file names
$stdout         = Join-Path $logDir "$TargetSid.dup.$DATE_SUFFIX.std"
$pdbplug        = Join-Path $logDir "$TargetSid.$SourcePdb.$DATE_SUFFIX.xml"
$drmanlog       = Join-Path $logDir "$TargetSid.rman-duplicate.$DATE_SUFFIX.log"
$drmanfiled     = Join-Path $logDir "$TargetSid.rman-duplicate.$DATE_SUFFIX.rcv"
$destroylog     = Join-Path $logDir "$AuxiliaryDb.destroy.$DATE_SUFFIX.log"
$plug_ps1       = Join-Path $logDir "$AuxiliaryDb.plug.$DATE_SUFFIX.ps1"
$pluglog        = Join-Path $logDir "$TargetSid.plug.$DATE_SUFFIX.log"
$plug_aux_log   = Join-Path $logDir "$TargetSid.aux.plug.$DATE_SUFFIX.log"
$unplug_ps1     = Join-Path $logDir "$AuxiliaryDb.unplug.$DATE_SUFFIX.ps1"
$unpluglog      = Join-Path $logDir "$AuxiliaryDb.unplug.$DATE_SUFFIX.log"
$destroy_aux_ps1 = Join-Path $logDir "$AuxiliaryDb.delete_aux.$DATE_SUFFIX.ps1"

# ------------------------------------------------------------------
# Determine source db name, samehost, backup location
# ------------------------------------------------------------------

$sdbname = $SourceDbName
$samehost = $false

Invoke-SqlplusSource -Sql "select name from v`$database;" -SpoolFile $stdout
$qn = Get-OracleSpoolValue -SpoolFile $stdout
if ($qn -and $qn -notmatch '(?i)error|ORA-') { $sdbname = $qn }
if (-not $sdbname) { Fail 'Could not determine the source database name. Provide -SourceConnect to a running source database.' }
Write-Host "source database is $sdbname"

# Standalone samehost detection (RAC enumeration dropped)
if ($shostshort -and ($thost -ieq $shostshort)) {
    Write-Host 'The target host is the host where the backup database is running on'
    $samehost = $true
}

# ------------------------------------------------------------------
# Auxiliary-CDB / PDB pre-checks
# ------------------------------------------------------------------

$pdbguid = $null
if ($AuxiliaryDb) {
    # target database must be up when an auxiliary database is used
    $env:ORACLE_SID = $TargetSid
    Invoke-Sqlplus -Sql "select name from v`$database;" -SpoolFile $stdout
    if ((Test-Path $stdout) -and (Select-String -Path $stdout -Pattern 'ORA-01034' -Quiet)) {
        Fail "Target database $TargetSid is not up running. If restoring CDB database $TargetSid is desired, remove -AuxiliaryDb"
    }

    # GUID of the source PDB
    Invoke-SqlplusSource -Sql "select guid from v`$pdbs where name='$($SourcePdb.ToUpper())';" -SpoolFile $stdout
    $pdbguid = Get-OracleSpoolValue -SpoolFile $stdout
    Write-Host "the GUID is $pdbguid"

    # does the target already have datafiles for this PDB GUID + aux name?
    $env:ORACLE_SID = $TargetSid
    Invoke-Sqlplus -Sql "select name from v`$datafile;" -SpoolFile $stdout
    if (-not $Force -and $pdbguid) {
        $hasGuid = (Test-Path $stdout) -and (Select-String -Path $stdout -Pattern ([regex]::Escape($pdbguid)) -Quiet)
        $hasAux  = (Test-Path $stdout) -and (Select-String -Path $stdout -Pattern ([regex]::Escape($AuxiliaryDb)) -Quiet)
        if ($hasGuid -and $hasAux) {
            Write-Host "The datafile names of the target database $TargetSid have the GUID of PDB $SourcePdb and the auxiliary name $AuxiliaryDb"
            Write-Host "Running duplication may overwrite the existing data (see $stdout)"
            if (-not (Confirm-Yes 'Type yes to continue this duplication')) {
                Fail 'A new auxiliary database name is needed to restore this pdb database.' 0
            }
        }
    }

    # ensure the destination PDB name does not already exist on the target
    if (-not $NewPdb) { $NewPdb = $SourcePdb; Write-Host "new pdb name is the same as original pdb name $SourcePdb" }
    $env:ORACLE_SID = $TargetSid
    Invoke-Sqlplus -Sql "select name from v`$pdbs;" -SpoolFile $stdout
    if ((Test-Path $stdout) -and (Select-String -Path $stdout -Pattern "(?i)^\s*$([regex]::Escape($NewPdb))\s*$" -Quiet)) {
        Fail "Pluggable database $($NewPdb.ToUpper()) already exists in target database $TargetSid"
    }
}

# ------------------------------------------------------------------
# If restoring to a different host with no time/sequence, find last archivelog sequence
# ------------------------------------------------------------------

$thread = $null
if (-not $samehost -and -not $PointInTime -and -not $PSBoundParameters.ContainsKey('Sequence')) {
    Write-Host 'A restore time or sequence number were not provided. We will use the last backed up archive log sequence'
    Invoke-SqlplusSource -Sql "select SEQUENCE#,THREAD#,FIRST_TIME from v`$backup_redolog where FIRST_TIME > sysdate-7 order by FIRST_TIME desc;" -SpoolFile $stdout
    $row = Get-OracleSpoolValue -SpoolFile $stdout
    if ($row) {
        $tok = ($row -split '\s+')
        $Sequence = [int]$tok[0]
        if ($tok.Count -ge 2) { $thread = $tok[1] }
        Write-Host "The last backed up archive log sequence is $Sequence, thread is $thread"
    }
}

# Which instance we operate on (auxiliary if provided, else target)
if ($AuxiliaryDb) { $env:ORACLE_SID = $AuxiliaryDb } else { $env:ORACLE_SID = $TargetSid }
$activeSid = $env:ORACLE_SID

# ------------------------------------------------------------------
# Oracle edition / license (source)
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
    Invoke-SqlplusSource -Sql $sql -SpoolFile $stdout
    $lic = (Get-OracleSpoolValue -SpoolFile $stdout).Trim()
    Write-Host "Oracle Edition is $lic"
    return $lic
}

# ------------------------------------------------------------------
# init pfile check
# ------------------------------------------------------------------

$dbpfile  = Join-Path $dbsDir "init$activeSid.ora"
$dbspfile = Join-Path $dbsDir "spfile$activeSid.ora"

function Confirm-OracleInitFile {
    if (-not (Test-Path $dbpfile)) {
        Fail "The oracle pfile $dbpfile doesn't exist. Please check the instance name or create the pfile first." 2
    }
}

# ------------------------------------------------------------------
# duplicate_prepare: directories + start instance nomount
# ------------------------------------------------------------------

function Invoke-DuplicatePrepare {
    # Warn if newname/db_create not configured (same host)
    if (-not $Force -and $samehost) {
        Write-Host "The server $shost where the backups were taken is the server the duplicate will run on"
        $hasCreateDest = Select-String -Path $dbpfile -Pattern 'db_create_file_dest' -Quiet -ErrorAction SilentlyContinue
        $hasFileConv   = Select-String -Path $dbpfile -Pattern 'db_file_name_convert' -Quiet -ErrorAction SilentlyContinue
        if (-not $hasCreateDest -and -not $hasFileConv) {
            Write-Host "db_create_file_dest and db_file_name_convert are not defined in init file $dbpfile"
            if (-not (Confirm-Yes 'Continue MAY overwrite the target database files. Do you want to continue?')) { exit 0 }
        }
    }

    # Create adump directory from the pfile if needed
    $adump = Get-PfileValue -Pattern 'audit_file_dest'
    if ($adump) {
        Write-Host 'check adump directory. Create it if it does not exist'
        if (-not (Test-Path $adump)) {
            Write-Host "$adump does not exist, create it"
            try { New-Item -ItemType Directory -Path $adump -Force | Out-Null } catch { Fail "create new directory $adump failed" }
        }
    }

    # Create db_create_file_dest if it is a directory and doesn't exist
    $dbCreate = Get-PfileValue -Pattern 'db_create_file_dest'
    if ($dbCreate) {
        Write-Host "db_create_location is $dbCreate"
        if ($dbCreate.Substring(0, 1) -ne '+' -and -not (Test-Path $dbCreate)) {
            Write-Host "$dbCreate does not exist, create it"
            try { New-Item -ItemType Directory -Path $dbCreate -Force | Out-Null } catch { Fail "create new directory $dbCreate failed" }
        }
    }

    # Create restore-location directories from the RestoreSettingFile (whole-DB only)
    if (-not $SourcePdb -and $RestoreSettingFile) {
        Write-Host "RestoreSettingFile is $RestoreSettingFile"
        foreach ($loc in (Get-NewnameLocations)) {
            if (Test-Path $loc -PathType Container) {
                if (Get-ChildItem -Path $loc -File -ErrorAction SilentlyContinue) { Write-Host "The directory $loc has files." }
            }
            if (Test-Path $loc -PathType Leaf) { Write-Host "file $loc exist." }
            $newdbdir = Split-Path -Parent $loc
            if ($newdbdir -and $newdbdir.Substring(0, 1) -ne '+' -and -not (Test-Path $newdbdir)) {
                Write-Host "Directory $newdbdir does not exist, create it"
                try { New-Item -ItemType Directory -Path $newdbdir -Force | Out-Null } catch { Fail "create new directory $newdbdir failed" }
            }
        }
    }

    # Build the context-specific confirmation prompt (used only when -Force is NOT set
    # and the instance is currently up in nomount/mount/open).
    $refreshPrompt = if ($SourcePdb) {
        if (-not $AuxiliaryDb) { "Auxiliary database is not provided. Should target database $activeSid be refreshed with new data?" }
        else { "Auxiliary database is up, should database $activeSid be refreshed with new data?" }
    }
    else { "Oracle database is up. Should target database $activeSid be refreshed with new data?" }

    # Start the Windows service and bring the auxiliary/target instance to NOMOUNT.
    #   * DOWN                -> STARTUP NOMOUNT
    #   * NOMOUNT/MOUNT/OPEN  -> SHUTDOWN IMMEDIATE + STARTUP NOMOUNT
    #     (prompted unless -Force; declining exits without touching the instance)
    Set-OracleNomount -Sid $activeSid -Pfile $dbpfile -ForceRefresh:$Force -ConfirmPrompt $refreshPrompt
}

# Read a single-quoted value (before any %) for a parameter from the pfile.
function Get-PfileValue {
    param([string]$Pattern)
    if (-not (Test-Path $dbpfile)) { return $null }
    $line = Get-Content -Path $dbpfile | Where-Object { $_ -match "(?i)$Pattern" -and $_ -notmatch '^\s*#' } | Select-Object -First 1
    if (-not $line) { return $null }
    if ($line -match "'([^']*)'") {
        return (($Matches[1] -split '%')[0]).Trim()
    }
    return $null
}

# Read all 'set newname ... to <location>' targets (value before %) from the RestoreSettingFile.
function Get-NewnameLocations {
    if (-not $RestoreSettingFile -or -not (Test-Path $RestoreSettingFile)) { return @() }
    $out = @()
    foreach ($line in (Get-Content -Path $RestoreSettingFile)) {
        if ($line -match '^\s*#') { continue }
        if ($line -match '(?i)newname' -and $line -match "'([^']*)'") {
            $out += (($Matches[1] -split '%')[0]).Trim()
        }
    }
    return $out
}

# ------------------------------------------------------------------
# create_rman_duplicate_file
# ------------------------------------------------------------------

function New-RmanDuplicateFile {
    Write-Host 'Create rman duplicate file'
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('RUN {')

    $ip = Get-FirstVip
    for ($j = 0; $j -lt $Parallel; $j++) {
        $chIp = $vips[$j % $vips.Count]
        $lines.Add("allocate auxiliary CHANNEL c$j TYPE 'SBT_TAPE' PARMS $(Build-AuxChannelParms -Ip $chIp);")
    }

    # Restore-location settings from the RestoreSettingFile (comments stripped)
    if ($RestoreSettingFile) {
        if (-not (Test-Path $RestoreSettingFile)) { Fail "$RestoreSettingFile does not exist" }
        foreach ($para in (Get-Content -Path $RestoreSettingFile)) {
            if ($para -match '^\s*#') { continue }
            $p = $para.Trim()
            if ($p) { $lines.Add($p) }
        }
    }

    if ($PointInTime) {
        Write-Host "Set duplicate until time $PointInTime"
        $lines.Add("set until time `"to_date('$PointInTime','YYYY/MM/DD HH24:MI:SS')`";")
    }
    elseif ($PSBoundParameters.ContainsKey('Sequence') -or $Sequence) {
        $thr = if ($thread) { $thread } else { '1' }
        Write-Host "Set recover until sequence $Sequence thread $thr"
        $lines.Add("set until sequence $Sequence thread $thr;")
    }

    $nores = if ($NoResume) { ' noresume' } else { '' }
    $nofnc = if ($samehost) { '' } else { ' nofilenamecheck' }
    if (-not $SourcePdb) {
        $lines.Add("duplicate database '$sdbname' to '$activeSid'$nores$nofnc;")
    }
    else {
        $lines.Add("duplicate database '$sdbname' to '$activeSid' pluggable database '$SourcePdb'$nores$nofnc;")
    }

    $lines.Add('}')
    $lines.Add('exit;')
    Set-Content -Path $drmanfiled -Value $lines
    Write-Host 'finished creating rman duplicate file'
}

# ------------------------------------------------------------------
# Generate PowerShell helper scripts for the auxiliary-CDB PDB flow
# ------------------------------------------------------------------

function New-PdbHelperScripts {
    # unplug helper: close + unplug the restored PDB from the auxiliary CDB, drop keeping datafiles.
    # The generated .ps1 feeds SQL to sqlplus via a single-quoted here-string (values already baked in).
    $unplug = @"
`$ErrorActionPreference = 'Continue'
Write-Host "unplug the new pdb database $SourcePdb from $AuxiliaryDb started at `$(Get-Date -Format 'yyyyMMddHHmmss')"
`$env:ORACLE_HOME = '$OracleHome'
`$env:PATH = '$OracleHome\bin;' + `$env:PATH
`$env:NLS_DATE_FORMAT = 'DD:MM:YYYY-HH24:MI:SS'
`$env:ORACLE_SID = '$AuxiliaryDb'
@'
alter pluggable database $SourcePdb close immediate;
alter pluggable database $SourcePdb unplug into '$pdbplug';
drop pluggable database $SourcePdb keep datafiles;
exit
'@ | & '$Global:SqlplusExe' -S -L '/ as sysdba' | Out-File -FilePath '$unpluglog' -Encoding ascii
if (Select-String -Path '$unpluglog' -Pattern 'error' -Quiet) {
    Write-Host "Error: Unplugging pdb database from database $AuxiliaryDb failed"
    exit 1
} else {
    Write-Host "The unplug of pdb database $SourcePdb from $AuxiliaryDb is successful."
}
"@
    Set-Content -Path $unplug_ps1 -Value $unplug
    Write-Host "unplug $SourcePdb helper script is created: $unplug_ps1"

    # plug helper: create the PDB in the target CDB from the unplugged XML
    $pdbTarget = if ($NewPdb) { $NewPdb } else { $SourcePdb }
    $usingClause = if (Test-Yes $PdbCopy) { "using '$pdbplug'" } else { "using '$pdbplug' tempfile reuse nocopy" }

    $plug = @"
`$ErrorActionPreference = 'Continue'
Write-Host "plug the new pdb database $pdbTarget to $TargetSid started at `$(Get-Date -Format 'yyyyMMddHHmmss')"
`$env:ORACLE_HOME = '$OracleHome'
`$env:PATH = '$OracleHome\bin;' + `$env:PATH
`$env:NLS_DATE_FORMAT = 'DD:MM:YYYY-HH24:MI:SS'
`$env:ORACLE_SID = '$TargetSid'
@'
create pluggable database $pdbTarget as clone $usingClause;
alter pluggable database $pdbTarget open;
exit
'@ | & '$Global:SqlplusExe' -S -L '/ as sysdba' | Out-File -FilePath '$pluglog' -Encoding ascii
"@
    if (Test-Yes $PdbCopy) {
        # with COPY, also plug the PDB back into the auxiliary so it can be dropped cleanly
        $plug += @"

`$env:ORACLE_SID = '$AuxiliaryDb'
@'
create pluggable database $SourcePdb using '$pdbplug' tempfile reuse nocopy;
exit
'@ | & '$Global:SqlplusExe' -S -L '/ as sysdba' | Out-File -FilePath '$plug_aux_log' -Encoding ascii
"@
    }
    $plug += @"

if (Select-String -Path '$pluglog' -Pattern 'error' -Quiet) {
    Write-Host "Error: Plugging pdb database to database $TargetSid failed. Will not delete auxiliary database $AuxiliaryDb."
    exit 1
} else {
    Write-Host "The plug of pdb database to database $TargetSid is successful."
}
"@
    Set-Content -Path $plug_ps1 -Value $plug
    Write-Host "plug $pdbTarget helper script is created: $plug_ps1"
}

function New-DestroyAuxScript {
    Write-Host "Delete auxiliary database $AuxiliaryDb after pdb $SourcePdb restore is successful"
    $destroy = @"
`$ErrorActionPreference = 'Continue'
Write-Host "save auxiliary database $AuxiliaryDb pfile before destroying it"
Copy-Item '$dbsDir\init$AuxiliaryDb.ora' '$dbsDir\init$AuxiliaryDb.save.ora' -Force -ErrorAction SilentlyContinue
Copy-Item '$dbsDir\init$AuxiliaryDb.ora' '$logDir\init$AuxiliaryDb.save.ora' -Force -ErrorAction SilentlyContinue
Write-Host "Destroy auxiliary database $AuxiliaryDb started at `$(Get-Date -Format 'yyyyMMddHHmmss')"
`$env:ORACLE_HOME = '$OracleHome'
`$env:PATH = '$OracleHome\bin;' + `$env:PATH
`$env:NLS_DATE_FORMAT = 'DD:MM:YYYY-HH24:MI:SS'
`$env:ORACLE_SID = '$AuxiliaryDb'
@'
shutdown immediate
exit
'@ | & '$Global:SqlplusExe' -S -L '/ as sysdba' | Out-Null
@'
startup mount exclusive;
Alter system enable restricted session;
exit
'@ | & '$Global:SqlplusExe' -S -L '/ as sysdba' | Out-Null
@'
connect target /
drop database including backups noprompt;
exit;
'@ | & '$Global:RmanExe' "log=$destroylog" | Out-Null
if (Select-String -Path '$destroylog' -Pattern 'ORA-|RMAN-' -Quiet) {
    Write-Host "Error: drop auxiliary database $AuxiliaryDb failed."
    exit 1
} else {
    Write-Host "auxiliary database $AuxiliaryDb is dropped successfully."
}
"@
    Set-Content -Path $destroy_aux_ps1 -Value $destroy
    Write-Host "Delete auxiliary database $AuxiliaryDb helper script is created: $destroy_aux_ps1"
}

# ------------------------------------------------------------------
# duplicate
# ------------------------------------------------------------------

function Invoke-Duplicate {
    Write-Host "Database duplicate started at $(Get-TimeStamp)"
    Write-Host "ORACLE SID is $activeSid"

    $connect = "connect auxiliary /`n"
    if ($SourceConnect) { $connect += "connect target '$SourceConnect'`n" }
    elseif ($CatalogConnect) { $connect += "connect catalog '$CatalogConnect'`n" }
    $connect += "@$drmanfiled`n"
    $connect | & $Global:RmanExe "log=$drmanlog" | Out-Null

    if ((Test-Path $drmanlog) -and (Select-String -Path $drmanlog -Pattern 'error' -Quiet)) {
        if (Select-String -Path $drmanlog -Pattern 'c0 not allocated' -Quiet) {
            Write-Host "Database duplicate finished at $(Get-TimeStamp)"
        }
        else {
            Write-Host "Database duplicate failed at $(Get-TimeStamp)"
            Get-ChildItem -Path (Join-Path $dbsDir "spfile$TargetSid.ora") -ErrorAction SilentlyContinue | Format-Table | Out-String | Write-Host
            Write-Host "Check rmanlog file $drmanlog"
            if (Test-Path $drmanlog) { Get-Content -Path $drmanlog -Tail 10 | ForEach-Object { Write-Host $_ } }
            Fail "Once the error is identified and corrected, rerun the duplicate. Make sure the target or auxiliary database is shut down and its files removed before the rerun."
        }
    }
    else {
        Write-Host "Database duplicate finished at $(Get-TimeStamp)"
    }
}

# ------------------------------------------------------------------
# Main
# ------------------------------------------------------------------

$vips = @(Get-Content -Path $VipFile | ForEach-Object { $_.Trim() } | Where-Object { $_ })

$ora_license = Get-OracleLicense
if ($ora_license -eq 'STANDARD') {
    Write-Host "`nSince the Oracle edition is Standard, only one RMAN channel will be used to run the duplicate command`n"
    $Parallel = 1
}

if (-not $Preview) {
    Write-Host 'prepare duplication'
    Confirm-OracleInitFile
    if (-not $Force) {
        Write-Host "The init file $dbpfile needs to be created first. The success of this duplication depends on its content."
        if (-not $SourcePdb) {
            if (-not (Confirm-Yes "It is recommended to clean up the files associated with database $TargetSid first. Type yes to continue this duplication")) {
                exit 0
            }
        }
    }
    Invoke-DuplicatePrepare
}

New-RmanDuplicateFile

if ($Preview) {
    Write-Host ''
    Write-Host "ORACLE DATABASE DUPLICATE RMAN script is $drmanfiled"
    Write-Host '---------------'
    Get-Content -Path $drmanfiled | ForEach-Object { Write-Host $_ }
    Write-Host '---------------'
    if ($AuxiliaryDb) {
        New-PdbHelperScripts
        New-DestroyAuxScript
    }
    exit 0
}

if ($Force) {
    Invoke-Duplicate
    if ($AuxiliaryDb) {
        New-PdbHelperScripts
        New-DestroyAuxScript
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $unplug_ps1
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $plug_ps1
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $destroy_aux_ps1
    }
}
else {
    Invoke-Duplicate
    if ($AuxiliaryDb) {
        New-PdbHelperScripts
        New-DestroyAuxScript
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $unplug_ps1
        if (-not $PdbCopy) {
            if (-not (Confirm-Yes 'This plug operation will not move the database file structure from the auxiliary to the target database. Type yes to continue this plug operation')) {
                Write-Host "The plug script $plug_ps1 can be modified and run manually. Once successful, $destroy_aux_ps1 can be run to delete the auxiliary database."
                exit 0
            }
        }
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $plug_ps1
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $destroy_aux_ps1
    }
}
