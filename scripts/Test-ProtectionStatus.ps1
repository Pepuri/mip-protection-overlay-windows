[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Path,
    [string]$AgentPath = "$env:ProgramFiles\PurviewProtectionOverlay\Agent\PurviewProtectionAgent.exe"
)

$ErrorActionPreference = 'Stop'
$resolved = (Resolve-Path $Path).Path
if (-not (Test-Path $AgentPath)) {
    throw "Agent not found: $AgentPath"
}

$outputPath = Join-Path $env:TEMP "PurviewProtectionProbe-$([Guid]::NewGuid().ToString('N')).json"
try {
    $process = Start-Process $AgentPath `
        -ArgumentList @('--probe', "`"$resolved`"", '--output', "`"$outputPath`"") `
        -Wait `
        -PassThru

    if (Test-Path $outputPath) {
        Get-Content $outputPath -Raw
    }
    exit $process.ExitCode
}
finally {
    Remove-Item $outputPath -Force -ErrorAction SilentlyContinue
}
