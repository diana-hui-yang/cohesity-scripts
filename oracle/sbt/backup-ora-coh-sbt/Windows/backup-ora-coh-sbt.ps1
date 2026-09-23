<#
.SYNOPSIS
    Backup Oracle databases into backup sets using the Cohesity SBT library (Windows / PowerShell port).

.DESCRIPTION
    PowerShell port of backup-ora-coh-sbt.bash (Diana Yang).
    This is the STREAMLINED Windows standalone version:
      * RAC multi-node channel logic has been dropped.
      * No check of whether the database is up/running.
      * No /etc/oratab lookup - ORACLE_HOME must be supplied (-OracleHome).

    It generates RMAN command files and runs the backup. It can do full, incremental (level 0/1),
    offline full, and archivelog-only backups, optionally using an RMAN recovery catalog.
    Retention can be managed by Oracle (recovery window) or by the SBT library.

.EXAMPLE
    .\backup-ora-coh-sbt.ps1 -DbName orcl -OracleHome "C:\app\oracle\product\19.0.0\dbhome_1" `
        -View oraback -CohesityName cohesity.example.com -Level 0 -OracleRetention 14

#>

[CmdletBinding()]
param(
    [Alias('m')]
    [string]$OracleHome,

    [Alias('v')]
    [string]$View,

    [Alias('o')]
    [string]$DbName,

    [Alias('r')]
    [string]$TargetConnect,

    [Alias('c')]
    [string]$CatalogConnect,

    [Alias('h')]
    [string]$HostName,

    # archivelog-only backup: 'yes' = archivelog only, 'no'/omitted = database + archivelog
    [Alias('a')]
    [ValidateSet('yes', 'Yes', 'YES', 'no', 'No', 'NO')]
    [string]$ArchiveOnly = 'no',

    # 0 = full (incremental level 0), 1 = cumulative incremental, full, or offline
    [Alias('i')]
    [string]$Level,

    [Alias('y')]
    [string]$CohesityName,

    [Alias('f')]
    [string]$VipFile,

    [Alias('s')]
    [string]$SbtLibrary,

    [Alias('p')]
    [int]$Parallel = 4,

    # Oracle-managed retention (recovery window, days). Files expired/deleted by Oracle.
    [Alias('e')]
    [int]$OracleRetention,

    # Long-term retention (KEEP UNTIL TIME SYSDATE+N). Requires an RMAN catalog and -OracleRetention.
    # (No single-letter alias: bash -R collides case-insensitively with -r/TargetConnect in PowerShell.)
    [int]$LongRetention,

    # Local archivelog retention (days) before delete input. 'no' = do not delete local archivelogs.
    [Alias('l')]
    [string]$ArchiveLogKeepDays,

    [Alias('b')]
    [int]$ArchiveCopies = 1,

    [Alias('z')]
    [int]$SectionSize,

    [Alias('t')]
    [string]$Tag,

    [Alias('g')]
    [ValidateSet('yes', 'Yes', 'YES', 'no', 'No', 'NO')]
    [string]$Encryption = 'no',

    [Alias('j')]
    [string]$EncryptionCertFile,

    # gRPC (yes) vs SunRPC (no)
    [Alias('x')]
    [ValidateSet('yes', 'Yes', 'YES', 'no', 'No', 'NO')]
    [string]$Grpc = 'yes',

    [Alias('k')]
    [ValidateSet('yes', 'Yes', 'YES', 'no', 'No', 'NO')]
    [string]$Compression = 'no',

    # Source-side dedup (yes) vs disable_source_side_dedup=true (no)
    [Alias('d')]
    [ValidateSet('yes', 'Yes', 'YES', 'no', 'No', 'NO')]
    [string]$SourceDedup = 'yes',

    # Record SBT activity in sbtio.log (yes) vs errors only / log_level=0 (no)
    [Alias('q')]
    [ValidateSet('yes', 'Yes', 'YES', 'no', 'No', 'NO')]
    [string]$SbtIoLog = 'yes',

    # Preview only: print the generated RMAN scripts, do not run the backup
    [Alias('w')]
    [switch]$Preview
)

function Show-Usage {
    $scriptName = Split-Path -Leaf $PSCommandPath
    if (-not $scriptName) { $scriptName = "backup-ora-coh-sbt.ps1" }

    Write-Host @"
Usage: .\$scriptName -TargetConnect <Target connection> -CatalogConnect <Catalog connection> -HostName <host> -DbName <Oracle_DB_Name> -ArchiveOnly <yes/no> -Level <incremental level> -CohesityName <Cohesity-cluster> -VipFile <vip file> -View <view> -SbtLibrary <sbt home> -Parallel <number of channels> -OracleRetention <retention> -LongRetention <long retention> -ArchiveLogKeepDays <archive log keep days> -SectionSize <section size> -Compression <yes/no> -OracleHome <ORACLE_HOME> -ArchiveCopies <number of archive logs> -Tag <tag> -Encryption <yes/no> -EncryptionCertFile <cert path or name> -Grpc <yes/no> -SourceDedup <yes/no> -SbtIoLog <yes/no> [-Preview]

 (Each long name has a single-letter alias shown in parentheses, matching the original bash flags.)

 Required Parameters
 -HostName          (-h) : host (scanname is required if it is RAC. optional if it is standalone.)
 -DbName            (-o) : ORACLE_DB_NAME (Need to have an entry of this database in oratab. If it is RAC, it is db_name)
 -CohesityName      (-y) : Cohesity Cluster DNS name
 -ArchiveOnly       (-a) : archivelog only backup (yes = archivelog backup only, no = database backup plus archivelog backup; default is no)
 -Level             (-i) : If not archivelog only backup, it is full or incremental backup. 0 is full backup, 1 is cumulative incremental backup, offline is offline full backup
 -View              (-v) : Cohesity View that is configured to be the target for Oracle backup
 -OracleRetention   (-e) : Retention time in days; expired files are deleted by Oracle
 -OracleHome        (-m) : ORACLE_HOME (the folder that contains the bin directory)

 Optional Parameters
 -TargetConnect     (-r) : Target connection (example: "<dbuser>/<dbpass>@<target connection string> as sysbackup"; optional if it is local backup)
 -CatalogConnect    (-c) : Catalog connection (example: "<dbuser>/<dbpass>@<catalog connection string>"; optional)
 -LongRetention          : Long Term Retention time (days to retain this particular backup; needs an RMAN catalog database and works only with -OracleRetention. No single-letter alias.)
 -Parallel          (-p) : number of channels (Optional, default is 4)
 -VipFile           (-f) : The file lists Cohesity Cluster VIPs (default name is vip-list and default directory is config)
 -SbtLibrary        (-s) : Cohesity SBT library name including directory or just directory (default directory is lib)
 -ArchiveLogKeepDays(-l) : Archive logs retain days (days to retain local archivelogs before deleting them. default is 1 day, "no" means not deleting local archivelogs on disk)
 -ArchiveCopies     (-b) : Number of times backing up Archive logs (default is 1)
 -SectionSize       (-z) : section size in GB (Optional, default is no section size)
 -Tag               (-t) : RMAN TAG
 -Compression       (-k) : RMAN compression (yes = RMAN compression, no = no RMAN compression; default is no)
 -Encryption        (-g) : yes means encryption-in-flight is used. Default is no
 -EncryptionCertFile(-j) : encryption certificate file, default directory is lib if full path is not provided
 -Grpc              (-x) : yes means gRPC is used, no means SunRPC is used. Default is yes
 -SourceDedup       (-d) : yes means source side dedup is used. Default is yes
 -SbtIoLog          (-q) : yes means SBT activity is recorded in sbtio.log, no means only errors are recorded. Default is yes
 -Preview           (-w) : switch (no value). Include -Preview to print the generated RMAN scripts without running the backup.

"@
}

if (-not $OracleHome) {
	Write-Host "
	
	Missing OracleHome parameter. It is required.
	
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

if (-not $DbName -and -not $TargetConnect) {
    Write-Host "
	
	Missing DbName or TargetConnect parameter. One of them is required.
	
	"
	Show-Usage
    exit 1
}

if (-not $OracleRetention) {
    Write-Host "
	
	Missing OracleRetention parameter. It is required.
	
	"
	Show-Usage
    exit 1
}

# ------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------

$ErrorActionPreference = 'Continue'

function Get-TimeStamp {
    return (Get-Date -Format 'yyyyMMddHHmmss')
}

function Write-Both {
    param([string]$Message, [string]$LogFile)
    Write-Host $Message
    if ($LogFile) { Add-Content -Path $LogFile -Value $Message }
}

function Test-Yes {
    param([string]$Value)
    return ($Value -match '^[Yy]')
}

function Fail {
    param([string]$Message, [int]$Code = 1)
    Write-Host $Message
    exit $Code
}

# Parse an sqlplus spool file the way the original get_oracle_info did:
# return the first non-empty data row that follows the "----" header separator.
function Get-OracleSpoolValue {
    param([string]$SpoolFile)
    if (-not (Test-Path $SpoolFile)) { return '' }
    $lines = Get-Content -Path $SpoolFile
    $seenSeparator = $false
    foreach ($line in $lines) {
        if ($seenSeparator) {
            $trimmed = ($line -replace '\s+', ' ').Trim()
            if ($trimmed) { return $trimmed }
        }
        if ($line -match '-{2,}') { $seenSeparator = $true }
    }
    return ''
}

# Run a SQL*Plus query, spooling output to $SpoolFile. Non-fatal on error.
function Invoke-Sqlplus {
    param([string]$Sql, [string]$SpoolFile)
    if (Test-Path $SpoolFile) { Remove-Item -Path $SpoolFile -Force -ErrorAction SilentlyContinue }
    $script = @"
set echo off
set feedback off
spool "$SpoolFile"
$Sql
spool off
exit
"@
    $script | & $Global:SqlplusExe -S -L $Global:SqlLogon | Out-Null
}

# Run an RMAN command file. Returns the RMAN exit code.
function Invoke-Rman {
    param([string]$CommandFile, [string]$LogFile)
    $connect = "connect target '$Global:RmanTargetConnect'`n"
    if ($CatalogConnect) { $connect += "connect catalog '$CatalogConnect'`n" }
    $rmanInput = $connect + "@$CommandFile`n"
    if ($LogFile) {
        $rmanInput | & $Global:RmanExe "log=$LogFile" | Out-Null
    }
    else {
        $rmanInput | & $Global:RmanExe | Out-Null
    }
    return $LASTEXITCODE
}

# Build the SBT_PARMS(...) inner content for a channel, honoring encryption / dedup / grpc / log level.
function Build-SbtParms {
    param([string]$Vip, [bool]$IncludeLogLevel)
    $parms = "data_view=$View,vips=$Vip"
    if (-not (Test-Yes $SourceDedup)) { $parms += ',disable_source_side_dedup=true' }
    if (-not (Test-Yes $Grpc))        { $parms += ',sbt_use_grpc=false' }
    if (Test-Yes $Encryption)         { $parms += ",sbt_certificate_file=$Global:EncryptCert" }
    if ($IncludeLogLevel)             { $parms += ',log_level=0' }
    return $parms
}

function Build-ChannelParms {
    param([string]$Vip, [bool]$IncludeLogLevel)
    return "'SBT_LIBRARY=$Global:Sbt,SBT_PARMS=($(Build-SbtParms -Vip $Vip -IncludeLogLevel:$IncludeLogLevel))'"
}

# ------------------------------------------------------------------
# Input validation
# ------------------------------------------------------------------

$archivelogonly = $false
if (Test-Yes $ArchiveOnly) {
    Write-Host 'Only backup archive logs'
    $archivelogonly = $true
}
else {
    Write-Host 'Will backup database backup plus archive logs'
    if (-not $Level) {
        Write-Host "
		
		Missing Level parameter. It is required.
		Backup type was not specified. The options are offline, full, 0, or 1.
		
		"
		Show-Usage
		exit 1
    }
    if ($Level -ne 'offline' -and $Level -ne 'full') {
        if ($Level -ne '0' -and $Level -ne '1') {
            Write-Host "incremental level is set to be $Level. Backup won't start"
            Fail "incremental backup level needs to be either 0, or 1"
        }
    }
}

$retday    = if ($PSBoundParameters.ContainsKey('OracleRetention')) { $OracleRetention } else { $null }
$longretday = if ($PSBoundParameters.ContainsKey('LongRetention'))  { $LongRetention }   else { $null }
$sectionsizeGB = if ($PSBoundParameters.ContainsKey('SectionSize')) { $SectionSize }     else { $null }

$DATE_SUFFIX = Get-TimeStamp

# Tag defaults
if (-not $Tag) {
    if ($Level -eq '0' -or $Level -eq 'offline' -or $Level -eq 'full') {
        $Tag = "full_$DATE_SUFFIX"
    }
    else {
        $Tag = "incremental_$DATE_SUFFIX"
    }
}

# Archive log local retention default
if (-not $ArchiveLogKeepDays) {
    Write-Host 'Only retain one day local archive logs'
    $ArchiveLogKeepDays = '1'
}

if ($Parallel -le 0) { $Parallel = 4 }

# ------------------------------------------------------------------
# Setup
# ------------------------------------------------------------------

# Script directory
$DIR = $PSScriptRoot
if (-not $DIR) { $DIR = (Get-Location).Path }

# Host name (used in log paths and RMAN format paths)
if (-not $HostName) { $HostName = $env:COMPUTERNAME }

# Determine local vs remote and build sqlplus / rman connect strings
$remote = $false
if (-not $TargetConnect -or $TargetConnect -eq '/') {
    $Global:RmanTargetConnect = '/'
    $Global:SqlLogon = '/ as sysdba'
    $env:ORACLE_SID = $DbName
}
else {
    $remote = $true
    $Global:RmanTargetConnect = $TargetConnect
    if ($TargetConnect -match '\s+as\s+') {
        $Global:SqlLogon = $TargetConnect
    }
    else {
        $Global:SqlLogon = "$TargetConnect as sysdba"
    }
}
Write-Host "target connection is $Global:RmanTargetConnect"

# ORACLE_HOME / PATH / executables
if (-not (Test-Path $OracleHome)) {
    Fail "ORACLE_HOME '$OracleHome' does not exist."
}
$env:ORACLE_HOME = $OracleHome
$env:PATH = "$OracleHome\bin;$env:PATH"
$env:NLS_DATE_FORMAT = 'DD:MM:YYYY-HH24:MI:SS'

$Global:RmanExe    = Join-Path $OracleHome 'bin\rman.exe'
$Global:SqlplusExe = Join-Path $OracleHome 'bin\sqlplus.exe'
if (-not (Test-Path $Global:RmanExe)) {
    Fail "rman.exe not found under '$OracleHome\bin'. Check -OracleHome."
}
if (-not (Test-Path $Global:SqlplusExe)) {
    Fail "sqlplus.exe not found under '$OracleHome\bin'. Check -OracleHome."
}

# Log and config directories
$logDir    = Join-Path $DIR "log\$HostName"
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
    Write-Host 'Cohesity Cluster name is not provided, we will use vipfile'
    if (-not $VipFile) { $VipFile = Join-Path $configDir 'vip-list' }
    if (-not (Test-Path $VipFile)) {
        Fail "file $VipFile provided does not exist"
    }
    Write-Host "file $VipFile provided exists, script continue"
}
else {
    $VipFile = Join-Path $configDir "$DbName-vip-list"
    Write-Host "Cohesity Cluster name is $CohesityName. VIPS will be collected and stored in $VipFile"
    try {
        $resolved = Resolve-DnsName -Name $CohesityName -Type A -ErrorAction Stop |
            Where-Object { $_.IPAddress } | Select-Object -ExpandProperty IPAddress
    }
    catch { $resolved = @() }
    if (-not $resolved -or $resolved.Count -eq 0) {
        Fail "Cohesity Cluster name $CohesityName provided here is not in DNS"
    }
    Set-Content -Path $VipFile -Value $resolved
}

$vips = @(Get-Content -Path $VipFile | ForEach-Object { $_.Trim() } | Where-Object { $_ })
if ($vips.Count -eq 0) {
    Fail "No VIPs found in $VipFile"
}
$lastip = $vips[-1]

# SBT library
if ($SbtLibrary) {
    if ($SbtLibrary -like '*.dll') {
        Write-Host "we will use the sbt library provided $SbtLibrary"
        $Global:Sbt = $SbtLibrary
    }
    else {
        Write-Host 'This may be a directory'
        $Global:Sbt = Join-Path $SbtLibrary 'cohesity_sbt.dll'
    }
}
else {
    Write-Host "we assume the sbt library is in $DIR\lib"
    $Global:Sbt = Join-Path $DIR 'lib\cohesity_sbt.dll'
}
if (Test-Path $Global:Sbt -PathType Leaf) {
    Write-Host "SBT plugin file $Global:Sbt exists, script continue"
}
else {
    Fail "file $Global:Sbt does not exist. exit"
}

# Log file names
$runlog      = Join-Path $logDir "$DbName.$DATE_SUFFIX.log"
$runrlog     = Join-Path $logDir "$DbName.r.$DATE_SUFFIX.log"
$stdout      = Join-Path $logDir "$DbName.$DATE_SUFFIX.std"
$rmanlog     = Join-Path $logDir "$DbName.rman.$DATE_SUFFIX.log"
$rmanloga    = Join-Path $logDir "$DbName.archive.$DATE_SUFFIX.log"
$rmanlogar   = Join-Path $logDir "$DbName.archive_r.$DATE_SUFFIX.log"
$rmanfiled   = Join-Path $logDir "$DbName.rman.$DATE_SUFFIX.rcv"
$rmanfilea   = Join-Path $logDir "$DbName.archive.$DATE_SUFFIX.rcv"
$rmanfilear  = Join-Path $logDir "$DbName.archive_r.$DATE_SUFFIX.rcv"
$expirelog   = Join-Path $logDir "$DbName.expire.$DATE_SUFFIX.log"
$obsoletelog = Join-Path $logDir "$DbName.obsolete.$DATE_SUFFIX.log"
$archive_tag = "archive_$DATE_SUFFIX"
$ctl_tag     = "ctl_$DATE_SUFFIX"

New-Item -ItemType File -Path (Join-Path $logDir "$DbName.$DATE_SUFFIX.jobstart") -Force | Out-Null

# Trim old logs
Get-ChildItem -Path $logDir -Filter "$DbName*" -File -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) } |
    Remove-Item -Force -ErrorAction SilentlyContinue
Get-ChildItem -Path $logDir -File -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-14) } |
    Remove-Item -Force -ErrorAction SilentlyContinue

# ------------------------------------------------------------------
# Query db_name, database role, PDB mount state (non-fatal; used for paths & retention)
# ------------------------------------------------------------------

$db_name  = $DbName
$dbstatus = 'normal'

Invoke-Sqlplus -Sql "select name from v`$database;" -SpoolFile $stdout
$queriedName = Get-OracleSpoolValue -SpoolFile $stdout
if ($queriedName -and $queriedName -notmatch '(?i)error|ORA-') {
    $db_name = $queriedName
}
else {
    Write-Host "Could not query db name from v`$database; using -DbName value '$DbName' for backup paths."
    if (-not $db_name) { Fail "No database name available. Provide -DbName." }
}

Invoke-Sqlplus -Sql "select database_role from v`$database;" -SpoolFile $stdout
$role = Get-OracleSpoolValue -SpoolFile $stdout
if ($role -match '(?i)standby') {
    Write-Host 'Database is a standby database'
    $dbstatus = 'standby'
}

# PDB mount-mode check (informational)
Invoke-Sqlplus -Sql "col name format a20`nselect name, open_mode from v`$pdbs;" -SpoolFile $stdout
if (Test-Path $stdout) {
    $pdbContent = Get-Content -Path $stdout
    if ($pdbContent -match '(?i)\bMOUNTED\b') {
        $msg = 'There are PDB databases in mount mode. These PDB databases integrity can''t be verified'
        Write-Both -Message $msg -LogFile $runlog
        $pdbContent | ForEach-Object { Write-Host $_ }
        Add-Content -Path $runlog -Value $pdbContent
    }
}

# ------------------------------------------------------------------
# RMAN command-file builders
# ------------------------------------------------------------------

$backupDir = "./$HostName/$db_name"

function Add-ConfigureHeader {
    param([System.Collections.Generic.List[string]]$Lines, [bool]$IncludeRetention)
    $Lines.Add('CONFIGURE DEFAULT DEVICE TYPE TO sbt_tape;')
    $Lines.Add('CONFIGURE BACKUP OPTIMIZATION OFF;')
    $Lines.Add('CONFIGURE CONTROLFILE AUTOBACKUP ON;')
    $Lines.Add("CONFIGURE CONTROLFILE AUTOBACKUP FORMAT FOR DEVICE TYPE sbt_tape TO '$backupDir/%d_%F.ctl';")
    if ($IncludeRetention -and $null -ne $retday -and $dbstatus -ne 'standby') {
        $Lines.Add("CONFIGURE retention policy to recovery window of $retday days;")
    }
}

# Build the database backup command (respects long retention / compression / section size).
function Get-DatabaseBackupCommand {
    $comp = if (Test-Yes $Compression) { 'AS COMPRESSED BACKUPSET ' } else { '' }
    $sec  = if ($null -ne $sectionsizeGB) { "section size ${sectionsizeGB}G " } else { '' }
    $keep = if ($null -ne $longretday) { " KEEP UNTIL TIME 'SYSDATE+$longretday'" } else { '' }

    if ($Level -eq 'offline' -or $Level -eq 'full') {
        $fmt = "$backupDir/%d_%T_%U_$Level.bdf"
        return "backup ${comp}TAG '$Tag' database ${sec}filesperset 1 format '$fmt'$keep;"
    }
    else {
        $fmt = "$backupDir/%d_%T_%U_level$Level.bdf"
        return "backup ${comp}INCREMENTAL LEVEL $Level CUMULATIVE TAG '$Tag' database ${sec}filesperset 1 format '$fmt'$keep;"
    }
}

# Build the archivelog backup command (honors ArchiveLogKeepDays: 'no' / 0 / N).
function Get-ArchiveBackupCommand {
    $comp = if (Test-Yes $Compression) { 'AS COMPRESSED BACKUPSET ' } else { '' }
    $base = "backup ${comp}TAG '$archive_tag' archivelog all filesperset 8 not backed up $ArchiveCopies times"
    if ($ArchiveLogKeepDays -match '^[Nn]') {
        return "$base;"
    }
    elseif ([int]$ArchiveLogKeepDays -eq 0) {
        return "$base delete input;"
    }
    else {
        return "$base archivelog until time 'sysdate-$ArchiveLogKeepDays' delete input;"
    }
}

# Allocate channels across the VIP list, cycling if parallel > number of VIPs.
function Get-DatabaseChannelLines {
    param([bool]$IncludeLogLevel)
    $lines = New-Object System.Collections.Generic.List[string]
    for ($j = 0; $j -lt $Parallel; $j++) {
        $ip = $vips[$j % $vips.Count]
        $lines.Add("allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS $(Build-ChannelParms -Vip $ip -IncludeLogLevel:$IncludeLogLevel);")
    }
    return $lines
}

function Get-ArchiveChannelLines {
    param([bool]$IncludeLogLevel)
    $lines = New-Object System.Collections.Generic.List[string]
    for ($j = 0; $j -lt $Parallel; $j++) {
        $ip = $vips[$j % $vips.Count]
        $lines.Add("allocate CHANNEL c$j TYPE 'SBT_TAPE' PARMS $(Build-ChannelParms -Vip $ip -IncludeLogLevel:$IncludeLogLevel) format '$backupDir/%d_%T_%U.blf';")
    }
    return $lines
}

# Create the database (.rcv) and archive (.rcv) files for a full/incremental/offline backup.
function New-RmanDatabaseFiles {
    $includeLog = -not (Test-Yes $SbtIoLog)

    # Database file
    $db = New-Object System.Collections.Generic.List[string]
    Add-ConfigureHeader -Lines $db -IncludeRetention:$true
    # Default channel config line (uses cluster name if provided, else first VIP)
    $configVip = if ($CohesityName) { $CohesityName } else { $vips[0] }
    $db.Add("CONFIGURE CHANNEL DEVICE TYPE 'SBT_TAPE' PARMS $(Build-ChannelParms -Vip $configVip -IncludeLogLevel:$includeLog);")
    $db.Add('RUN {')
    foreach ($l in (Get-DatabaseChannelLines -IncludeLogLevel:$includeLog)) { $db.Add($l) }
    $db.Add((Get-DatabaseBackupCommand))
    $db.Add("BACKUP TAG '$ctl_tag' CURRENT CONTROLFILE format '$backupDir/%d_%T_%U.ctl';")
    $db.Add('}')
    $db.Add('exit;')
    Set-Content -Path $rmanfiled -Value $db

    # Archive file (run after the database backup)
    $ar = New-Object System.Collections.Generic.List[string]
    Add-ConfigureHeader -Lines $ar -IncludeRetention:$false
    $ar.Add('RUN {')
    foreach ($l in (Get-ArchiveChannelLines -IncludeLogLevel:$includeLog)) { $ar.Add($l) }
    $ar.Add((Get-ArchiveBackupCommand))
    $ar.Add('}')
    $ar.Add('exit;')
    Set-Content -Path $rmanfilea -Value $ar

    Write-Both -Message 'finished creating rman file' -LogFile $runlog
}

# Create the archivelog-only (.rcv) file.
function New-RmanArchiveFile {
    $includeLog = -not (Test-Yes $SbtIoLog)
    $ar = New-Object System.Collections.Generic.List[string]
    Add-ConfigureHeader -Lines $ar -IncludeRetention:$false
    $ar.Add('RUN {')
    foreach ($l in (Get-ArchiveChannelLines -IncludeLogLevel:$includeLog)) { $ar.Add($l) }
    $ar.Add((Get-ArchiveBackupCommand))
    $ar.Add('}')
    $ar.Add('exit;')
    Set-Content -Path $rmanfilear -Value $ar
    Write-Both -Message 'finished creating rman file' -LogFile $runrlog
}

# ------------------------------------------------------------------
# Backup / maintenance actions
# ------------------------------------------------------------------

function Invoke-DatabaseBackup {
    Write-Both -Message "Database backup started at $(Get-TimeStamp)" -LogFile $runlog
    $rc = Invoke-Rman -CommandFile $rmanfiled -LogFile $rmanlog
    if ($rc -ne 0) {
        Write-Both -Message "Database backup failed at $(Get-TimeStamp)" -LogFile $runlog
        exit 1
    }
    Write-Both -Message "Database backup finished at $(Get-TimeStamp)" -LogFile $runlog

    Write-Host "dbstatus is $dbstatus"
    if ($dbstatus -ne 'standby' -and $Level -ne 'offline') {
        $connect = "connect target '$Global:RmanTargetConnect'`nsql 'ALTER SYSTEM ARCHIVE LOG CURRENT';`nexit;`n"
        $connect | & $Global:RmanExe | Out-Null
    }
}

function Invoke-ArchiveBackup {
    param([string]$CommandFile, [string]$LogFile, [string]$RunLog)
    Write-Both -Message "Archive logs backup started at $(Get-TimeStamp)" -LogFile $RunLog
    $rc = Invoke-Rman -CommandFile $CommandFile -LogFile $LogFile
    if ($rc -ne 0) {
        Write-Both -Message "Archive logs backup failed at $(Get-TimeStamp)" -LogFile $RunLog
        exit 1
    }
    Write-Both -Message "Archive logs backup finished at $(Get-TimeStamp)" -LogFile $RunLog

    if ((Test-Path $LogFile) -and (Select-String -Path $LogFile -Pattern 'error' -Quiet)) {
        Write-Host 'Backup is successful. However there are channels not correct'
    }
    else {
        Write-Host 'Backup is successful.'
    }
}

$script:open_mode = ''

function Set-DatabaseMount {
    Write-Host 'Change the database to mount open mode if it is not already'
    Invoke-Sqlplus -Sql "select open_mode from v`$database;" -SpoolFile $stdout
    $script:open_mode = Get-OracleSpoolValue -SpoolFile $stdout
    Write-Host "database at $script:open_mode open mode"

    if ($script:open_mode -ne 'MOUNTED') {
        Write-Host 'shutdown the database and start it at mount open mode'
        $sql = @"
set echo off
shutdown immediate;
startup mount
exit
"@
        $sql | & $Global:SqlplusExe -S -L $Global:SqlLogon | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Both -Message "Database failed to start to mount open mode at $(Get-TimeStamp)" -LogFile $runlog
            exit 1
        }
        Write-Both -Message "Database started to mount open mode at $(Get-TimeStamp)" -LogFile $runlog
    }
    else {
        Write-Both -Message 'database is at mount open mode, the backup can start' -LogFile $runlog
    }
}

function Start-OracleDatabase {
    Write-Host 'startup the database after the offline backup finishes'
    if ($script:open_mode -ne 'MOUNTED') {
        "alter database open;`nexit" | & $Global:SqlplusExe -S -L $Global:SqlLogon | Out-Null
        Invoke-Sqlplus -Sql "select open_mode from v`$database;" -SpoolFile $stdout
        $script:open_mode = Get-OracleSpoolValue -SpoolFile $stdout
        if ($script:open_mode -eq 'MOUNTED') {
            Write-Both -Message "Database failed to start at $(Get-TimeStamp)" -LogFile $runlog
            exit 1
        }
        Write-Both -Message "Database started finished at $(Get-TimeStamp)" -LogFile $runlog
    }
    else {
        Write-Host 'The database was at mount open mode. no need to start the database'
    }
}

function Remove-ObsoleteRecords {
    $cmd = "crosscheck backup device type sbt;`ndelete noprompt expired backup device type sbt;`nDelete noprompt obsolete device type sbt;`nexit;`n"
    $connect = "connect target '$Global:RmanTargetConnect'`n"
    if ($CatalogConnect) { $connect += "connect catalog '$CatalogConnect'`n" }
    ($connect + $cmd) | & $Global:RmanExe "log=$obsoletelog" | Out-Null
    if ((Test-Path $obsoletelog) -and (Select-String -Path $obsoletelog -Pattern 'error' -Quiet)) {
        Write-Host "Delete obsolete failed. The error message is in log file $obsoletelog"
    }
    else {
        Write-Host 'Delete obsolete is successful.'
    }
}

function Sync-OracleRecords {
    $cmd = "crosscheck backup device type sbt;`ndelete noprompt expired backup device type sbt;`nexit;`n"
    $connect = "connect target '$Global:RmanTargetConnect'`n"
    if ($CatalogConnect) { $connect += "connect catalog '$CatalogConnect'`n" }
    ($connect + $cmd) | & $Global:RmanExe "log=$expirelog" | Out-Null
    if ((Test-Path $expirelog) -and (Select-String -Path $expirelog -Pattern 'error' -Quiet)) {
        Write-Host "Expiration failed. The error message is in log file $expirelog"
    }
    else {
        Write-Host 'Oracle control file or Oracle recovery catalog is synced up with the actual backup files.'
    }
}

# ------------------------------------------------------------------
# Main
# ------------------------------------------------------------------

Write-Host ""
Write-Host "the backup script runs on $env:COMPUTERNAME and in directory $DIR"
Write-Host "oracle database server is $HostName"
Write-Host ""

if ($archivelogonly) {
    Write-Host 'archive logs backup only'
    New-RmanArchiveFile
    if ($Preview) {
        Write-Host ''
        Write-Host 'ORACLE ARCHIVE LOG BACKUP RMAN SCRIPT'
        Write-Host '---------------'
        Get-Content -Path $rmanfilear | ForEach-Object { Write-Host $_ }
        Write-Host '---------------'
    }
    else {
        Invoke-ArchiveBackup -CommandFile $rmanfilear -LogFile $rmanlogar -RunLog $runrlog
        if ((Test-Path $runrlog) -and (Select-String -Path $runrlog -Pattern 'error' -Quiet)) {
            Write-Host "Backup may be successful. However there are IPs in $VipFile not reachable"
        }
    }
}
else {
    Write-Host 'backup database plus archive logs'
    New-RmanDatabaseFiles
    if ($Preview) {
        Write-Host ''
        Write-Host 'ORACLE ARCHIVE LOG BACKUP RMAN SCRIPT'
        Write-Host '---------------'
        Get-Content -Path $rmanfilea | ForEach-Object { Write-Host $_ }
        Write-Host '---------------'
        Write-Host ''
        Write-Host 'ORACLE DATABASE BACKUP RMAN SCRIPT'
        Write-Host '---------------'
        Get-Content -Path $rmanfiled | ForEach-Object { Write-Host $_ }
        Write-Host '---------------'
    }
    else {
        if ($Level -eq 'offline') {
            Set-DatabaseMount
            Invoke-DatabaseBackup
            Start-OracleDatabase
        }
        else {
            Invoke-DatabaseBackup
            Invoke-ArchiveBackup -CommandFile $rmanfilea -LogFile $rmanloga -RunLog $runlog
        }
        if ($null -ne $retday) {
            Remove-ObsoleteRecords
        }
    }
    if ((Test-Path $runlog) -and (Select-String -Path $runlog -Pattern 'error' -Quiet)) {
        Write-Host "Backup may be successful. However there are IPs in $VipFile not reachable"
    }
}
