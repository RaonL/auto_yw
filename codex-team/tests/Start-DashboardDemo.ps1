#requires -Version 7.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../scripts/TeamRunner.psm1') -Force
$fixture = Join-Path $PSScriptRoot ('.runs/ui-demo-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($fixture) | Out-Null
$shellPath = (Get-Process -Id $PID).Path
Invoke-TeamWorkflow -TeamRoot $fixture -Task '화면 자동 갱신 모의 테스트 · 모델 호출 없음' -CliCommand @($shellPath,'-NoProfile','-File',(Join-Path $PSScriptRoot 'Fake-Codex.ps1'),'-Scenario','ui-demo') -Offline
