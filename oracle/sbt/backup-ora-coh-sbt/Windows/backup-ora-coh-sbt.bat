@echo off
setlocal

set "psfile=C:\oracle\cohesity\backup-ora-coh-sbt.ps1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%psfile%" %*

endlocal & exit /b %rc%