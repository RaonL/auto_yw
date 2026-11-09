#requires -Version 7.0
Set-StrictMode -Version Latest

function Write-TeamDashboard {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$State, [Parameter(Mandatory)][string]$OutputPath)
    $template = [IO.File]::ReadAllText((Join-Path $PSScriptRoot '../assets/team-dashboard.html'))
    # Model-controlled strings cannot terminate the JSON script element.
    $json = $State | ConvertTo-Json -Depth 12 -Compress -EscapeHandling EscapeHtml
    $html = $template.Replace('__TEAM_STATE_JSON__', $json)
    $temporaryPath = "$OutputPath.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        [IO.File]::WriteAllText($temporaryPath, $html, [Text.UTF8Encoding]::new($false))
        [IO.File]::Move($temporaryPath, $OutputPath, $true)
    } finally {
        if (Test-Path -LiteralPath $temporaryPath) { [IO.File]::Delete($temporaryPath) }
    }
}

Export-ModuleMember -Function Write-TeamDashboard
