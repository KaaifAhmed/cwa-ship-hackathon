@echo off
REM ============================================================================
REM CWA Ship Karachi 2026 - Project Bootstrap (Windows launcher)
REM
REM This .bat is just a thin launcher. All real logic lives in bootstrap.ps1
REM (PowerShell), because Windows cmd/batch has no reliable way to write
REM multi-line files (no heredocs) or manage venvs/processes the way bash can.
REM PowerShell ships with every modern Windows install, so this needs no
REM extra tools.
REM
REM Usage:
REM   bootstrap.bat [project-name]
REM
REM Requires: git, python (3.11+, "python" on PATH), node/npm (20+),
REM Docker Desktop with the `docker compose` plugin (v2)
REM ============================================================================

setlocal

set "PROJECT_NAME=%~1"
if "%PROJECT_NAME%"=="" set "PROJECT_NAME=cwa-hackathon"

REM Make sure PowerShell exists
where powershell >nul 2>nul
if errorlevel 1 (
    echo ERROR: powershell.exe not found on PATH. This script requires PowerShell.
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0bootstrap.ps1" -ProjectName "%PROJECT_NAME%"
set "EXITCODE=%ERRORLEVEL%"

endlocal
exit /b %EXITCODE%