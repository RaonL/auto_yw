#requires -Version 7.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../scripts/TeamRunner.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '../scripts/TeamDashboard.psm1')
Import-Module (Join-Path $PSScriptRoot '../scripts/CodexProcess.psm1')
$testRoot = Join-Path $PSScriptRoot ('.runs/dashboard-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($testRoot) | Out-Null
$shellPath = (Get-Process -Id $PID).Path
function Assert-True($Value, [string]$Message) { if (-not $Value) { throw $Message } }
$past = [pscustomobject]@{ task_id='fixture-completed'; status='COMPLETED'; message='fixture'; started_utc='2026-11-09T13:00:00Z'; updated_utc='2026-11-09T13:01:00Z'; revision=1; final_path='leader/output/fixture-final.md'; stages=@([pscustomobject]@{number=1;kind='review';role='reviewer';revision=1;status='PASS';session_id='11111111-1111-1111-1111-111111111111';artifact_path='reviewer/output/fixture-review.md';started_utc='2026-11-09T13:00:00Z';finished_utc='2026-11-09T13:01:00Z'}) }
$outputPath = Join-Path $testRoot 'completed.html'
Write-TeamDashboard -State $past -OutputPath $outputPath
$html = [IO.File]::ReadAllText($outputPath)
Assert-True ($html.Contains('"COMPLETED"') -and $html.Contains('11111111-1111-1111-1111-111111111111')) 'Recorded state/session data not embedded'
Assert-True (-not $html.Contains('__TEAM_STATE_JSON__')) 'Unreplaced state placeholder'
Write-Host 'PASS completed fixture rendering'
$past.message = '</script><img src=x onerror=alert(1)>'
Write-TeamDashboard -State $past -OutputPath (Join-Path $testRoot 'escaped.html')
$escaped = [IO.File]::ReadAllText((Join-Path $testRoot 'escaped.html'))
Assert-True (-not $escaped.Contains($past.message)) 'Unsafe model HTML was not escaped'
Assert-True ($escaped.Contains('\u003c')) 'Expected escaped JSON content'
Write-Host 'PASS untrusted summary escaping'
$progressEvents = [Collections.Generic.List[object]]::new()
$result = Invoke-TeamProcess -Command @($shellPath) -Arguments @('-NoProfile','-Command','Start-Sleep -Seconds 3') -WorkingDirectory $testRoot -Prompt 'heartbeat probe' -LogPrefix (Join-Path $testRoot 'heartbeat') -TimeoutSeconds 10 -ProgressIntervalSeconds 1 -OnProgress { param($progress); $progressEvents.Add($progress) }
Assert-True ($result.ExitCode -eq 0 -and $progressEvents.Count -ge 3) 'Progress callback did not fire during process execution'
Assert-True ($progressEvents[-1].elapsed_seconds -ge 2 -and $progressEvents[-1].process_id -gt 0) 'Progress payload incomplete'
Write-Host 'PASS progress callbacks while child process is alive'
$fixture = Join-Path $testRoot 'workflow'
[IO.Directory]::CreateDirectory($fixture) | Out-Null
$run = Invoke-TeamWorkflow -TeamRoot $fixture -Task '대시보드 모의 테스트 (모델 호출 없음)' -CliCommand @($shellPath,'-NoProfile','-File',(Join-Path $PSScriptRoot 'Fake-Codex.ps1')) -Offline
Assert-True ($run.status -eq 'COMPLETED') 'Fixture workflow failed'
$dashboardPath = Join-Path $fixture "runs/$($run.task_id)/dashboard.html"
$dashboard = [IO.File]::ReadAllText($dashboardPath)
Assert-True ($dashboard.Contains('"COMPLETED"') -and $dashboard.Contains($run.task_id)) 'Workflow dashboard not finalized'
Assert-True ($run.dashboard_path -eq $dashboardPath) 'Dashboard path not exposed to caller'
Write-Host 'PASS workflow writes final dashboard and path'
Write-Host 'ALL PASS: 4 dashboard checks'
