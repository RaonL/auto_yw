#requires -Version 7.0
Set-StrictMode -Version Latest
if (-not ('CodexTeam.ProcessJob' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'ProcessJob.cs') }

function Invoke-TeamProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$Command,
        [Parameter(Mandatory)][string[]]$Arguments,
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [Parameter(Mandatory)][string]$Prompt,
        [Parameter(Mandatory)][string]$LogPrefix,
        [ValidateRange(1,3600)][int]$TimeoutSeconds = 600,
        [scriptblock]$OnProgress,
        [ValidateRange(1,60)][int]$ProgressIntervalSeconds = 5
    )
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $Command[0]
    $startInfo.WorkingDirectory = $WorkingDirectory
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.WindowStyle = 'Hidden'
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $utf8 = [Text.UTF8Encoding]::new($false)
    $startInfo.StandardInputEncoding = $utf8
    $startInfo.StandardOutputEncoding = $utf8
    $startInfo.StandardErrorEncoding = $utf8
    foreach ($argument in @($Command | Select-Object -Skip 1) + $Arguments) { $startInfo.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    $stdoutTask = $null
    $stderrTask = $null
    $inputTask = $null
    $job = $null
    $started = $false
    $timedOut = $false
    $stdoutText = ''
    $stderrText = ''
    $watch = [Diagnostics.Stopwatch]::StartNew()
    try {
        $started = $process.Start()
        if (-not $started) { throw 'CLI process did not start' }
        $job = [CodexTeam.ProcessJob]::new($process)
        # Drain both streams concurrently; close stdin so exec does not wait for more input.
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $inputTask = $process.StandardInput.WriteAsync($Prompt)
        $inputClosed = $false
        $nextHeartbeat = 20
        $nextProgress = 0
        while ($true) {
            if ($OnProgress -and $watch.Elapsed.TotalSeconds -ge $nextProgress) {
                & $OnProgress ([pscustomobject]@{process_id=$process.Id;elapsed_seconds=[int]$watch.Elapsed.TotalSeconds;heartbeat_utc=[datetime]::UtcNow.ToString('o')}) | Out-Null
                $nextProgress = $watch.Elapsed.TotalSeconds + $ProgressIntervalSeconds
            }
            if (-not $inputClosed -and $inputTask.IsCompleted) {
                [void]$inputTask.GetAwaiter().GetResult()
                $process.StandardInput.Close()
                $inputClosed = $true
            }
            if ($process.HasExited -and $stdoutTask.IsCompleted -and $stderrTask.IsCompleted -and $inputClosed) { break }
            if ($watch.Elapsed.TotalSeconds -ge $TimeoutSeconds) {
                $timedOut = $true
                # Closing the job also kills descendants after their parent has exited.
                $job.Dispose()
                if (-not $process.HasExited) { $process.Kill($true) }
                [void]$process.WaitForExit(5000)
                break
            }
            if ($watch.Elapsed.TotalSeconds -ge $nextHeartbeat) {
                Write-Host "  진행 중: $([int]$watch.Elapsed.TotalSeconds)초 / 제한 ${TimeoutSeconds}초"
                $nextHeartbeat += 20
            }
            Start-Sleep -Milliseconds 100
        }
        if ($timedOut) {
            $grace = [Diagnostics.Stopwatch]::StartNew()
            while ((-not $stdoutTask.IsCompleted -or -not $stderrTask.IsCompleted) -and $grace.Elapsed.TotalSeconds -lt 3) { Start-Sleep -Milliseconds 50 }
        }
        if ($stdoutTask.IsCompletedSuccessfully) { $stdoutText = $stdoutTask.GetAwaiter().GetResult() }
        if ($stderrTask.IsCompletedSuccessfully) { $stderrText = $stderrTask.GetAwaiter().GetResult() }
        $exitCode = if ($process.HasExited) { $process.ExitCode } else { -1 }
        return [pscustomobject]@{ExitCode=$exitCode;Stdout=$stdoutText;Stderr=$stderrText;TimedOut=$timedOut}
    } finally {
        # Also runs on Ctrl+C: terminate only this invocation's process tree.
        try {
            if ($job) { $job.Dispose() }
            if ($started -and -not $process.HasExited) {
                $process.Kill($true)
                [void]$process.WaitForExit(5000)
            }
            if ($stdoutTask -and $stdoutTask.IsCompletedSuccessfully) { $stdoutText = $stdoutTask.GetAwaiter().GetResult() }
            if ($stderrTask -and $stderrTask.IsCompletedSuccessfully) { $stderrText = $stderrTask.GetAwaiter().GetResult() }
        } finally {
            try {
                [IO.File]::WriteAllText("$LogPrefix.stdout.jsonl", $stdoutText, $utf8)
                [IO.File]::WriteAllText("$LogPrefix.stderr.log", $stderrText, $utf8)
            } finally { $process.Dispose() }
        }
    }
}

Export-ModuleMember -Function Invoke-TeamProcess
