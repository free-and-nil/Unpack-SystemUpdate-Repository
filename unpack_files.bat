@echo off
echo.
echo Unpack SystemInstaller files?
echo.
pause
echo.

if not exist C:\Temp\SCCM\. mkdir C:\Temp\SCCM

rem This changes the PowerShell "ExecutionPolicy" system-wide
rem powershell.exe -Command "& {Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine -Force}"

powershell.exe -file Unpack_SystemUpdate_Repository.ps1 C:\ProgramData\Lenovo\SystemUpdate\sessionSE\Repository C:\Temp\SCCM
