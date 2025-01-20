::
:: This script performs RMAN backup.
::

@ECHO OFF
SETLOCAL EnableExtensions
SETLOCAL EnableDelayedExpansion

set rmanscript=%~1
set scriptdir=c:\ora-scripts\sbt

set savedate=%date:~10,4%%date:~7,2%%date:~4,2%
set savedate=%savedate: =%
set savetime=%time::=.%
set savetime=%savetime: =%
set logfile=rman.log.%savedate%.%savetime%
set logdir=%scriptdir%\logs
set oratempfile=%scriptdir%\orafile.txt

dir /B %logdir%

if %errorlevel%==1 (
   echo "the directory %logdir% doesn't exist, creating it"
   mkdir %logdir%
)

if %errorlevel%==1 (
   echo "Creating directory %logdir% failed"
   EXIT /B 2
)

forfiles /p %logdir% /s /m *.* /D -7 /C "cmd /c del @file"

del %oratempfile%

SET ORACLE_BASE=c:\app\oracle
SET ORACLE_HOME=c:\app\oracle\product\12.2.0\dbhome_1
SET ORACLE_SID=SIDA
SET PATH=%ORACLE_HOME%/bin;%PATH%

rman msglog="%logdir%\%logfile%" < "%scriptdir%\%rmanscript%"

if %errorlevel%==0 (
   echo "Full database backup is successful"
   echo success > %oratempfile%
) else (
   echo "Full database backup failed"
) 
