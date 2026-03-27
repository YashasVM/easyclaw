@echo off
REM EasyClaw CLI wrapper for cmd.exe
REM Delegates to the PowerShell script
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0easyclaw.ps1" %*
