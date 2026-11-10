param(
    [string]$Scenario = 'success',
    [Parameter(ValueFromRemainingArguments)][string[]]$CliArgs
)
$ErrorActionPreference = 'Stop'
[Console]::InputEncoding = [Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$outputIndex = [Array]::IndexOf($CliArgs, '--output-last-message')
$lastPath = $CliArgs[$outputIndex + 1]
$promptText = [Console]::In.ReadToEnd()
[IO.File]::WriteAllText("$lastPath.stdin.txt", $promptText)
$contextLine = @($promptText -split "`n" | Where-Object { $_.StartsWith('RUN_CONTEXT_JSON=') })[0]
$context = $contextLine.Substring('RUN_CONTEXT_JSON='.Length) | ConvertFrom-Json
if ($Scenario -eq 'timeout') { Start-Sleep -Seconds 30 }
if ($Scenario -eq 'ui-demo') { Start-Sleep -Seconds 5 }
if ($Scenario -eq 'exit-error') { [Console]::Error.WriteLine('fake transport failure'); exit 12 }
$sessionId = if ($context.session_id) { $context.session_id } else { [guid]::NewGuid().ToString() }
@{type='thread.started';thread_id=$sessionId} | ConvertTo-Json -Compress | Write-Output
@{type='turn.started'} | ConvertTo-Json -Compress | Write-Output
if ($Scenario -eq 'bad-json') { Set-Content -LiteralPath $lastPath -Value 'not JSON'; exit 0 }
$status = if ($context.kind -eq 'review') { 'PASS' } else { 'DONE' }
if ($context.kind -eq 'research' -and $Scenario -in @('blocked','approval')) {
    $status = if ($Scenario -eq 'blocked') { 'BLOCKED' } else { 'NEEDS_APPROVAL' }
}
if ($context.kind -eq 'review' -and ($Scenario -eq 'always-revise' -or ($Scenario -eq 'revise-once' -and $context.revision -eq 1))) { $status = 'NEEDS_CHANGES' }
$cause = 'DRAFT'
$summary = 'fake stage response'
if ($Scenario -eq 'needs-choice' -and $context.kind -eq 'review') {
    $status = 'BLOCKED'
    $summary = '가격과 지원 기간 중 어느 조건을 우선할까요?'
}
# The quote reviewer computes its verdict from the fixture files and the actual
# draft. It receives the same scenario name for both routing tests.
if ($Scenario -eq 'quote') {
    $quote = Import-Csv -LiteralPath (Join-Path $context.team_root 'quote.csv')
    $annex = Import-Csv -LiteralPath (Join-Path $context.team_root 'annex.csv')
    $total = [int]$quote.quantity * [int]$quote.unit_price
    if ($context.kind -eq 'review') {
        $researchText = Get-Content -Raw (Join-Path $context.team_root $context.paths.research)
        $draftText = Get-Content -Raw (Join-Path $context.team_root $context.paths.draft)
        if ($quote.months -ne $annex.months -and $researchText -notmatch '서명 정정본') {
            $status = 'NEEDS_CHANGES'; $cause = 'SOURCE'; $summary = '견적 본문과 부속서의 지원 기간 불일치'
        } elseif ($draftText -notmatch "(?m)^합계: ${total}$") {
            $status = 'NEEDS_CHANGES'; $summary = '원문 수량과 단가의 곱이 초안 합계와 불일치'
        }
    }
}
if ($status -notin @('BLOCKED','NEEDS_APPROVAL')) {
    if ($Scenario -eq 'final-mutate-draft' -and $context.kind -eq 'leader_finalize') { Add-Content -LiteralPath (Join-Path $context.team_root $context.draft_path) -Value 'post-review change' }
    foreach ($relativePath in $context.expected_paths) {
        $fullPath = Join-Path $context.team_root $relativePath
        [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($fullPath)) | Out-Null
        $body = "task_id: $($context.task_id)`nstatus: $status`n"
        if ($relativePath -eq $context.paths.plan) { $body += "- [ ] C1 원자료 확인 및 합계·지원 조건 대조`n" }
        if ($context.kind -eq 'review' -and $relativePath -eq $context.artifact_path) {
            $body += if ($status -eq 'PASS') { "- [x] C1 원문·계산 확인`n" } else { "- [ ] C1 $summary`n- 원인: $cause`n" }
            if ($Scenario -eq 'unchecked-pass') { $body = "status: PASS`n" }
        }
        if ($Scenario -eq 'mixed-verdict' -and $context.kind -eq 'review' -and $relativePath -eq $context.artifact_path) { $body += "- 판정: NEEDS_CHANGES`n" }
        if ($relativePath -eq $context.draft_path) { $body = "# 가상 요약`n- 완료 4건, 전체 6건, 완료율 66.7%`n" }
        if ($Scenario -eq 'quote' -and $relativePath -eq $context.paths.research) {
            $body = "지원 기간: $($quote.months)개월"
            if ($context.previous_paths) {
                $correction = Get-Content -Raw (Join-Path $context.team_root 'signed-amendment.txt')
                $body += "`n서명 정정본: $correction"
            }
        }
        if ($Scenario -eq 'quote' -and $relativePath -eq $context.paths.draft) {
            $amount = if ($context.revision -eq 1) { $quote.draft_total } else { $total }
            $evidence = Get-Content -Raw (Join-Path $context.team_root $context.paths.research)
            $body = "합계: $amount`n$evidence"
        }
        if ($context.kind -eq 'leader_finalize' -and $relativePath -eq $context.artifact_path) { $body += [IO.File]::ReadAllText((Join-Path $context.team_root $context.draft_path)) }
        if ($Scenario -eq 'missing-artifact' -and $relativePath -eq $context.artifact_path) { continue }
        [IO.File]::WriteAllText($fullPath, $body)
    }
}
if ($Scenario -eq 'mutate-draft' -and $context.kind -eq 'review') { Add-Content -LiteralPath (Join-Path $context.team_root $context.draft_path) -Value 'unexpected edit' }
$responseId = if ($Scenario -eq 'wrong-id') { 'another-run' } else { $context.task_id }
$artifactPath = if ($Scenario -eq 'wrong-path') { '../escape.md' } else { $context.artifact_path }
@{task_id=$responseId;status=$status;artifact_path=$artifactPath;summary=$summary} | ConvertTo-Json -Compress | Set-Content -LiteralPath $lastPath -Encoding utf8
if ($Scenario -eq 'unwritable-status') { [IO.File]::SetAttributes((Join-Path ([IO.Path]::GetDirectoryName($lastPath)) 'status.json'), [IO.FileAttributes]::ReadOnly) }
@{type='turn.completed';usage=@{input_tokens=1;output_tokens=1}} | ConvertTo-Json -Compress | Write-Output
