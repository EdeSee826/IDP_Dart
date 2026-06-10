@echo off
set LOCALHOST=%COMPUTERNAME%
if /i "%LOCALHOST%"=="DESKTOP-UMPC6RM" (taskkill /f /pid 10904)
if /i "%LOCALHOST%"=="DESKTOP-UMPC6RM" (taskkill /f /pid 35136)
if /i "%LOCALHOST%"=="DESKTOP-UMPC6RM" (taskkill /f /pid 3968)
if /i "%LOCALHOST%"=="DESKTOP-UMPC6RM" (taskkill /f /pid 8040)

del /F cleanup-ansys-DESKTOP-UMPC6RM-8040.bat
