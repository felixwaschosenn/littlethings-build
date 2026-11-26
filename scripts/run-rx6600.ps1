param(
    [Parameter(Mandatory)][string]$GameDir,
    [ValidateRange(10, 1800)][int]$TimeoutSeconds = 300,
    [ValidateSet('off', 'faults', 'light', 'full')][string]$Dred = 'off',
    [switch]$DiagnosticsBuild
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$buildPath = if ($DiagnosticsBuild) { 'target\diag\victory.exe' } else { 'target\release\victory.exe' }
$exe = Join-Path $repo $buildPath
if ($Dred -ne 'off' -and !$DiagnosticsBuild) { throw 'DRED requer -DiagnosticsBuild (cargo build --profile diag -p victory --features diagnostics --locked).' }
$game = Join-Path $GameDir 'game_scarlett_master.exe'
if (!(Test-Path -LiteralPath $exe)) { throw "Compile $buildPath primeiro." }
if (!(Test-Path -LiteralPath $game)) { throw 'game_scarlett_master.exe não encontrado no diretório indicado.' }
foreach ($dll in @('dxcompiler.dll', 'dxil.dll')) {
    if (!(Test-Path -LiteralPath (Join-Path (Split-Path $exe) $dll))) { throw "$dll não encontrado ao lado de victory.exe." }
}
$original = @{}
Get-ChildItem Env:VICTORY_* | ForEach-Object { $original[$_.Name] = $_.Value }
$settings = @{
    VICTORY_CACHE_DIR = Join-Path $env:LOCALAPPDATA 'VIctory\cache-rx6600'
    VICTORY_LOG = 'info'; VICTORY_LEVELS_ON_DEMAND = '1'
    VICTORY_RELAY = '2'; VICTORY_LATE_WAIT = '3'; VICTORY_ASYNC_SUBMIT = '1'
    VICTORY_LATE_WAIT_LISTS = '256'; VICTORY_TEXTURE_KEEP = '1'; VICTORY_KEEP_FREED = '1'
    VICTORY_THIN = '1'; VICTORY_JOIN_PARTS = '4'; VICTORY_UPLOAD_AHEAD = '1'
    VICTORY_TEXTURE_NO_WAIT = '0'; VICTORY_RELAY_COPY = '1'
    VICTORY_UNDER_WIDE = '0'; VICTORY_LAND_ECHO = '0'; VICTORY_SHOW_AFTER = '1'
    VICTORY_AMBIENT = '0.8'; VICTORY_AMBIENT_AIR = '1.5'
    VICTORY_BVH_BUILDER = '0'; VICTORY_ACTIVATE_RAYS = '0'; VICTORY_RT_RESOLVE = '0'
}
if ($Dred -ne 'off') {
    # The child inherits this setting before the first D3D12 device is created.
    $settings.VICTORY_D3D12_DRED = if ($Dred -eq 'full') { '1' } else { $Dred }
}
$logs = Join-Path $env:LOCALAPPDATA 'VIctory\logs\rx6600'
New-Item -ItemType Directory -Force -Path $logs | Out-Null
$prefix = Join-Path $logs (Get-Date -Format 'yyyyMMdd-HHmmss-fff')
$clock = [Diagnostics.Stopwatch]::StartNew()
$code = 1
$timedOut = $false
try {
    Get-ChildItem Env:VICTORY_* | ForEach-Object { Remove-Item -LiteralPath ('Env:' + $_.Name) }
    foreach ($key in $settings.Keys) { Set-Item -LiteralPath ('Env:' + $key) -Value $settings[$key] }
    $process = Start-Process -FilePath $exe -ArgumentList @('run', ('"' + $game + '"'), '--console', 'series-s', '--execute') -WorkingDirectory $repo -WindowStyle Hidden -RedirectStandardOutput "$prefix.stdout.log" -RedirectStandardError "$prefix.stderr.log" -PassThru
    Write-Host "PID $($process.Id); timeout $TimeoutSeconds s; logs: $prefix"
    if (!$process.WaitForExit($TimeoutSeconds * 1000)) {
        $timedOut = $true
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        [void]$process.WaitForExit(5000)
    }
    $process.Refresh()
    $code = if ($timedOut) { 124 } else { $process.ExitCode }
    [ordered]@{ ExitCode = $code; Timeout = $timedOut; Dred = $Dred; ElapsedSeconds = [Math]::Round($clock.Elapsed.TotalSeconds, 2); Stdout = "$prefix.stdout.log"; Stderr = "$prefix.stderr.log" } |
        ConvertTo-Json | Set-Content -LiteralPath "$prefix.result.json" -Encoding UTF8
    Write-Host "ExitCode=$code Timeout=$timedOut"
} finally {
    Get-ChildItem Env:VICTORY_* | ForEach-Object { Remove-Item -LiteralPath ('Env:' + $_.Name) }
    foreach ($key in $original.Keys) { Set-Item -LiteralPath ('Env:' + $key) -Value $original[$key] }
}
exit $code
