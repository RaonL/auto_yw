#requires -Version 7.0
param(
    [string]$Task,
    [string]$TaskFile,
    [ValidateRange(0,3)][int]$MaxRevisions = 1,
    [ValidateRange(1,3600)][int]$StageTimeoutSeconds = 600,
    [switch]$Offline
)
$ErrorActionPreference = 'Stop'
if ($Task -and $TaskFile) { throw '-Task와 -TaskFile 중 하나만 지정하세요.' }
if ($TaskFile) { $Task = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $TaskFile).Path) }
if (-not $Task) { $Task = Read-Host '팀에 맡길 업무를 입력하세요' }
Import-Module (Join-Path $PSScriptRoot 'scripts/TeamRunner.psm1') -Force
$run = Invoke-TeamWorkflow -TeamRoot $PSScriptRoot -Task $Task -MaxRevisions $MaxRevisions -StageTimeoutSeconds $StageTimeoutSeconds -Offline:$Offline
Write-Host "`n상태: $($run.status)"
Write-Host $run.message
if ($run.error) { Write-Host $run.error -ForegroundColor Red }
Write-Host "실행 기록: $(Join-Path $PSScriptRoot "runs/$($run.task_id)/status.json")"
if ($run.final_path) { Write-Host "최종 결과: $(Join-Path $PSScriptRoot $run.final_path)" }
$exitCode = switch ($run.status) { 'COMPLETED' {0} 'NEEDS_APPROVAL' {3} 'BLOCKED' {4} 'NEEDS_CHANGES' {5} default {1} }
exit $exitCode
