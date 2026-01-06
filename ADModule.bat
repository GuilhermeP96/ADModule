@echo off
chcp 65001 >nul 2>&1
setlocal EnableDelayedExpansion
title ADModule - Script Manager
cd /d "%~dp0"

:MENU
cls
echo.
echo =============================================
echo        ADModule - Script Manager
echo =============================================
echo.
echo   Available Scripts:
echo.
echo   [1] Get-ADUserInfo - Query AD user attributes
echo       (Single user or batch processing)
echo.
echo   [2] Import-ActiveDirectory - Import AD module
echo       (Load DLL for manual PowerShell use)
echo.
echo   [0] Exit
echo.
echo =============================================
echo.

set /p choice="Choose an option (0-2): "

if "%choice%"=="1" goto ADUSER
if "%choice%"=="2" goto IMPORTAD
if "%choice%"=="0" goto EXIT
echo.
echo [!] Invalid option. Press any key to try again...
pause >nul
goto MENU

:ADUSER
cls
echo.
echo =============================================
echo        Get-ADUserInfo - Options
echo =============================================
echo.
echo   [1] Interactive mode (menu)
echo.
echo   [2] Query current logged-in user
echo.
echo   [3] Batch process from file
echo.
echo   [0] Back to main menu
echo.
echo =============================================
echo.

set /p subchoice="Choose an option (0-3): "

if "%subchoice%"=="1" goto ADUSER_INTERACTIVE
if "%subchoice%"=="2" goto ADUSER_CURRENT
if "%subchoice%"=="3" goto ADUSER_BATCH
if "%subchoice%"=="0" goto MENU
echo.
echo [!] Invalid option. Press any key to try again...
pause >nul
goto ADUSER

:ADUSER_INTERACTIVE
cls
powershell.exe -ExecutionPolicy Bypass -NoProfile -Command "[Console]::OutputEncoding = [System.Text.Encoding]::UTF8; & '.\scripts\Get-ADUserInfo.ps1'"
echo.
pause
goto MENU

:ADUSER_CURRENT
cls
powershell.exe -ExecutionPolicy Bypass -NoProfile -Command "[Console]::OutputEncoding = [System.Text.Encoding]::UTF8; & '.\scripts\Get-ADUserInfo.ps1' -SamAccountName $env:USERNAME -NoMenu"
echo.
pause
goto MENU

:ADUSER_BATCH
cls
powershell.exe -ExecutionPolicy Bypass -NoProfile -Command "[Console]::OutputEncoding = [System.Text.Encoding]::UTF8; $script = '.\scripts\Get-ADUserInfo.ps1'; & $script -BatchFile '' -BatchOutput ''"
echo.
pause
goto MENU

:IMPORTAD
cls
echo.
echo =============================================
echo    Import-ActiveDirectory - PowerShell
echo =============================================
echo.
echo   This will open a PowerShell session with
echo   the Active Directory module loaded.
echo.
echo   You can use AD cmdlets like:
echo     - Get-ADUser
echo     - Get-ADGroup
echo     - Get-ADComputer
echo.
echo =============================================
echo.
echo Press any key to start PowerShell session...
pause >nul
cls
powershell.exe -ExecutionPolicy Bypass -NoProfile -NoExit -Command "[Console]::OutputEncoding = [System.Text.Encoding]::UTF8; & '.\scripts\Import-ActiveDirectory.ps1'; Write-Host ''; Write-Host '[+] AD Module loaded. You can now use Get-ADUser, Get-ADGroup, etc.' -ForegroundColor Green; Write-Host ''"
goto MENU

:EXIT
echo.
echo Exiting...
endlocal
exit /b 0
