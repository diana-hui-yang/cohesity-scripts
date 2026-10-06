@echo off
setlocal

set "psfile=C:\oracle\cohesity\backup-ora-coh-sbt.ps1"
for %%A in ("%psfile%") do set "scriptdir=%%~dpA"
set "oratempfile=%scriptdir%orafile.txt"
REM echo %scriptdir%

if exist "%oratempfile%" del "%oratempfile%"

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%psfile%" %*
set "rc=%ERRORLEVEL%"

if %rc%==0 (
    echo Full database backup is successful
    echo success > "%oratempfile%"
) else (
    echo Full database backup failed
)

endlocal & exit /b %rc%