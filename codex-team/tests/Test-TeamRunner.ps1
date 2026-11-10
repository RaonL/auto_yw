#requires -Version 7.0
$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $PSScriptRoot '../scripts/TeamRunner.psm1'
Import-Module $modulePath -Force
Import-Module (Join-Path $PSScriptRoot '../scripts/CodexProcess.psm1') -Force
$testRoot = Join-Path $PSScriptRoot ('.runs/' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($testRoot) | Out-Null
$shellPath = (Get-Process -Id $PID).Path
$fakePath = Join-Path $PSScriptRoot 'Fake-Codex.ps1'
$script:testCount = 0
function Assert-True($Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function New-Fixture([string]$Name) {
    $path = Join-Path $testRoot "$Name 한글 space"
    foreach ($role in @('leader','researcher','writer','reviewer')) {
        foreach ($folder in @('inbox','output')) { [IO.Directory]::CreateDirectory((Join-Path $path "$role/$folder")) | Out-Null }
    }
    return $path
}
function Run-Scenario([string]$Name, [string]$Scenario = 'success', [int]$Timeout = 20) {
    $fixture = New-Fixture $Name
    $result = Invoke-TeamWorkflow -TeamRoot $fixture -Task '한글 "quote"; $(never execute) 업무' -CliCommand @($shellPath,'-NoProfile','-File',$fakePath,'-Scenario',$Scenario) -StageTimeoutSeconds $Timeout -Offline
    return $result
}
function Test-Case([string]$Name, [scriptblock]$Body) {
    & $Body
    $script:testCount++
    Write-Host "PASS $Name"
}
Test-Case 'success: 7 stages and same leader session' {
    $run = Run-Scenario 'success'
    Assert-True ($run.status -eq 'COMPLETED') 'Workflow did not complete'
    Assert-True ($run.stages.Count -eq 7) 'Unexpected stage count'
    $leaders = @($run.stages | Where-Object role -eq 'leader' | ForEach-Object session_id | Select-Object -Unique)
    Assert-True ($leaders.Count -eq 1) 'Leader session not resumed'
    $request = [IO.File]::ReadAllText((Join-Path $run.team_root $run.request_path))
    Assert-True ($request.Contains('$(never execute)')) 'Task text was not preserved literally'
    Assert-True (Test-Path -LiteralPath (Join-Path $run.team_root $run.final_path)) 'Final artifact missing'
}
foreach ($scenario in @('blocked','approval')) {
    Test-Case "stop: $scenario" {
        $run = Run-Scenario $scenario $scenario
        $expected = if ($scenario -eq 'blocked') { 'BLOCKED' } else { 'NEEDS_APPROVAL' }
        Assert-True ($run.status -eq $expected -and $run.stages.Count -eq 2) 'Halt did not stop downstream stages'
        Assert-True (-not $run.final_path) 'Halted workflow published a final path'
    }.GetNewClosure()
}
Test-Case 'review requests one correction and passes' {
    $run = Run-Scenario 'revise-once' 'revise-once'
    Assert-True ($run.status -eq 'COMPLETED' -and $run.revision -eq 2) 'Revision did not complete'
    Assert-True ($run.stages.Count -eq 11) 'Unexpected revision stage count'
    $reviewers = @($run.stages | Where-Object role -eq 'reviewer' | ForEach-Object session_id | Select-Object -Unique)
    Assert-True ($reviewers.Count -eq 2) 'Re-review must use an independent new session'
}
foreach ($fault in @('계산 오류','원자료 충돌')) {
    Test-Case "견적 수정 경로: $fault" {
        $fixture = New-Fixture $fault
        $conflict = $fault -eq '원자료 충돌'
        $draftTotal = if ($conflict) { 30000 } else { 20000 }
        $annexMonths = if ($conflict) { 24 } else { 12 }
        Set-Content (Join-Path $fixture 'quote.csv') "quantity,unit_price,months,draft_total`n3,10000,12,$draftTotal"
        Set-Content (Join-Path $fixture 'annex.csv') "months`n$annexMonths"
        Set-Content (Join-Path $fixture 'signed-amendment.txt') '최종 지원 기간 12개월, 이전 부속서 대체'
        $run = Invoke-TeamWorkflow -TeamRoot $fixture -Task '견적 합계와 지원 조건을 검토해줘' -Offline -CliCommand @($shellPath,'-NoProfile','-File',$fakePath,'-Scenario','quote')
        Assert-True ($run.status -eq 'COMPLETED' -and $run.revision -eq 2) "Correction failed: $($run.error)"
        $review = $run.stages[5]
        $owner = if ($conflict) { 'researcher' } else { 'writer' }
        Assert-True ($review.status -eq 'NEEDS_CHANGES' -and $review.next_owner -eq $owner) 'Wrong correction owner'
        $workers = @($run.stages | Where-Object { $_.revision -eq 2 -and $_.role -ne 'leader' } | ForEach-Object role)
        $expected = if ($conflict) { 'researcher,writer,reviewer' } else { 'writer,reviewer' }
        Assert-True (($workers -join ',') -eq $expected) 'Unexpected corrective stage order'
        $final = Get-Content -Raw (Join-Path $fixture $run.final_path)
        Assert-True ($final -match '(?m)^합계: 30000$') 'Wrong final amount'
        if ($conflict) {
            $research = @($run.stages | Where-Object kind -eq 'research')
            Assert-True ($research[0].artifact_path -ne $research[1].artifact_path) 'Original research overwritten'
            Assert-True ($final.Contains('서명 정정본: 최종 지원 기간 12개월')) 'Writer did not consume new evidence'
        }
        Write-Host "검수 원인 $($review.cause) → $($workers -join ' → ') → $($run.stages[-2].status)"
    }.GetNewClosure()
}
Test-Case 'user decision stops without publishing final result' {
    $run = Run-Scenario 'choice' 'needs-choice'
    Assert-True ($run.status -eq 'BLOCKED' -and $run.stages[-1].next_owner -eq 'user' -and $run.message.Contains('어느 조건') -and -not $run.final_path) 'Missing user handoff'
}
Test-Case 'light summary runs only the writer without an independent PASS' {
    $run = Invoke-TeamWorkflow -TeamRoot (New-Fixture 'light') -Task '간단 내부 요약' -Mode Light -CliCommand @($shellPath,'-NoProfile','-File',$fakePath)
    Assert-True ($run.status -eq 'COMPLETED' -and $run.stages.Count -eq 1 -and $run.stages[0].kind -eq 'light_write') 'Unexpected light workflow'
    Assert-True ($run.stages[0].status -eq 'DONE' -and (Test-Path (Join-Path $run.team_root $run.final_path))) 'Invalid light output'
}
Test-Case 'review limit stops instead of looping' {
    $run = Run-Scenario 'always-revise' 'always-revise'
    Assert-True ($run.status -eq 'NEEDS_CHANGES' -and $run.revision -eq 2) 'Revision limit not enforced'
    Assert-True (-not $run.final_path) 'Failed review produced a final artifact'
}
foreach ($scenario in @('bad-json','wrong-id','wrong-path','missing-artifact','exit-error','mutate-draft','final-mutate-draft','mixed-verdict','unchecked-pass')) {
    Test-Case "reject: $scenario" {
        $run = Run-Scenario $scenario $scenario
        Assert-True ($run.status -eq 'FAILED') "Expected FAILED for $scenario"
        Assert-True (-not $run.final_path) 'Failure was treated as completion'
    }.GetNewClosure()
}
Test-Case 'timeout stops child process and records failure' {
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $run = Run-Scenario 'timeout' 'timeout' 2
    Assert-True ($run.status -eq 'FAILED' -and $watch.Elapsed.TotalSeconds -lt 12) 'Timeout did not stop promptly'
    Assert-True ($run.error -match 'timeout') 'Timeout reason missing'
}
Test-Case 'exclusive lock rejects a second run and releases afterwards' {
    $fixture = New-Fixture 'lock'
    $lock = [IO.File]::Open((Join-Path $fixture '.team-run.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
    try {
        $caught = $false
        try { Invoke-TeamWorkflow -TeamRoot $fixture -Task 'another' -CliCommand @($shellPath,'-NoProfile','-File',$fakePath) | Out-Null } catch { $caught = $true }
        Assert-True $caught 'Concurrent run accepted'
    } finally { $lock.Dispose() }
    $run = Invoke-TeamWorkflow -TeamRoot $fixture -Task 'after release' -CliCommand @($shellPath,'-NoProfile','-File',$fakePath) -Offline
    Assert-True ($run.status -eq 'COMPLETED') 'Lock not reusable'
}
Test-Case 'empty task rejected before model invocation' {
    $caught = $false
    try { Invoke-TeamWorkflow -TeamRoot (New-Fixture 'empty') -Task ' ' | Out-Null } catch { $caught = $true }
    Assert-True $caught 'Empty task accepted'
}
Test-Case 'deadline includes blocked standard input' {
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $processResult = Invoke-TeamProcess -Command @($shellPath) -Arguments @('-NoProfile','-Command','Start-Sleep -Seconds 20') -WorkingDirectory $testRoot -Prompt ('x' * 1000000) -LogPrefix (Join-Path $testRoot 'blocked-input') -TimeoutSeconds 2
    Assert-True ($processResult.TimedOut -and $watch.Elapsed.TotalSeconds -lt 10) 'Blocked stdin escaped timeout'
}
Test-Case 'inherited output pipe is bounded and descendant is terminated' {
    $pipeRoot = New-Fixture 'inherited-pipe'
    $parentScript = Join-Path $pipeRoot 'Parent.ps1'
    $parentCode = @'
$startInfo = [Diagnostics.ProcessStartInfo]::new()
$startInfo.FileName = (Get-Process -Id $PID).Path
$startInfo.UseShellExecute = $false
$startInfo.CreateNoWindow = $true
$startInfo.ArgumentList.Add('-NoProfile')
$startInfo.ArgumentList.Add('-Command')
$startInfo.ArgumentList.Add('Start-Sleep -Seconds 20')
$child = [Diagnostics.Process]::Start($startInfo)
[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'child.pid'), [string]$child.Id)
'@
    [IO.File]::WriteAllText($parentScript, $parentCode)
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $result = Invoke-TeamProcess -Command @($shellPath) -Arguments @('-NoProfile','-File',$parentScript) -WorkingDirectory $pipeRoot -Prompt 'input' -LogPrefix (Join-Path $pipeRoot 'pipes') -TimeoutSeconds 2
    Assert-True ($result.TimedOut -and $watch.Elapsed.TotalSeconds -lt 10) 'Inherited pipe escaped deadline'
    $childId = [int][IO.File]::ReadAllText((Join-Path $pipeRoot 'child.pid'))
    Assert-True (-not (Get-Process -Id $childId -ErrorAction SilentlyContinue)) 'Descendant survived job cleanup'
}
Test-Case 'status persistence failure still releases lock' {
    $fixture = New-Fixture 'unwritable-status'
    $caught = $false
    try { Invoke-TeamWorkflow -TeamRoot $fixture -Task 'fail status save' -CliCommand @($shellPath,'-NoProfile','-File',$fakePath,'-Scenario','unwritable-status') -Offline | Out-Null } catch { $caught=$true }
    Assert-True $caught 'Status write failure was not surfaced'
    $probe = [IO.File]::Open((Join-Path $fixture '.team-run.lock'), 'Open', 'ReadWrite', 'None')
    $probe.Dispose()
}
Write-Host "ALL PASS: $script:testCount tests"
