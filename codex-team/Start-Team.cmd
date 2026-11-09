@echo off
cd /d "%~dp0"
set "TEAM_PWSH=%ProgramFiles%\PowerShell\7\pwsh.exe"
if not exist "%TEAM_PWSH%" set "TEAM_PWSH=%USERPROFILE%\.cache\codex-runtimes\codex-primary-runtime\dependencies\native\powershell\pwsh.exe"
if not exist "%TEAM_PWSH%" (
  echo PowerShell 7 was not found. Run Start-Team.ps1 from PowerShell 7.
  pause
  exit /b 1
)
"%TEAM_PWSH%" -NoProfile -File "%~dp0Start-Team.ps1"
set "TEAM_EXIT=%ERRORLEVEL%"
pause
exit /b %TEAM_EXIT%
