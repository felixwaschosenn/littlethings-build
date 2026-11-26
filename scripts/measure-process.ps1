param(
    [Parameter(Mandatory)][ValidateRange(1, 2147483647)][int]$TargetProcessId,
    [ValidateRange(1, 3600)][int]$DurationSeconds = 300,
    [ValidateRange(100, 10000)][int]$IntervalMilliseconds = 1000
)

# Attach to an existing process. This sampler never starts or stops the workload.
# Private bytes are process commit, not VRAM or the total system commit.
$ErrorActionPreference = 'Stop'
$process = [Diagnostics.Process]::GetProcessById($TargetProcessId)
$clock = [Diagnostics.Stopwatch]::StartNew()
$directory = Join-Path $env:LOCALAPPDATA 'VIctory\logs\process-metrics'
$prefix = Join-Path $directory ("{0}-{1}" -f $TargetProcessId, (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
$samples = 0
$peakPrivate = 0L
$peakWorkingSet = 0L
$previousCpu = $null
$previousSeconds = 0.0
$endReason = 'DurationElapsed'
try {
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
    while ($clock.Elapsed.TotalSeconds -lt $DurationSeconds) {
        $process.Refresh()
        if ($process.HasExited) { $endReason = 'ProcessExited'; break }
        try {
            $private = $process.PrivateMemorySize64
            $working = $process.WorkingSet64
            $cpu = $process.TotalProcessorTime.TotalSeconds
        } catch [System.InvalidOperationException] {
            if ($process.HasExited) { $endReason = 'ProcessExited'; break }
            throw
        }
        $seconds = $clock.Elapsed.TotalSeconds
        # 1.0 means one logical CPU occupied over the sampling interval.
        $cpuCores = if ($null -ne $previousCpu -and $seconds -gt $previousSeconds) {
            ($cpu - $previousCpu) / ($seconds - $previousSeconds)
        } else { $null }
        [pscustomobject][ordered]@{
            Utc = [DateTime]::UtcNow.ToString('o')
            ElapsedSeconds = $seconds
            ProcessId = $TargetProcessId
            PrivateBytes = $private
            WorkingSetBytes = $working
            CpuSeconds = $cpu
            CpuCores = $cpuCores
        } | Export-Csv -LiteralPath "$prefix.csv" -NoTypeInformation -Append -Encoding UTF8
        $samples++
        $peakPrivate = [Math]::Max($peakPrivate, $private)
        $peakWorkingSet = [Math]::Max($peakWorkingSet, $working)
        $previousCpu = $cpu
        $previousSeconds = $seconds
        $remainingMs = [Math]::Ceiling(($DurationSeconds - $clock.Elapsed.TotalSeconds) * 1000)
        if ($remainingMs -le 0) { break }
        if ($process.WaitForExit([int][Math]::Min($IntervalMilliseconds, $remainingMs))) {
            $endReason = 'ProcessExited'
            break
        }
    }
    [ordered]@{
        ProcessId = $TargetProcessId
        Samples = $samples
        IntervalMilliseconds = $IntervalMilliseconds
        ElapsedSeconds = $clock.Elapsed.TotalSeconds
        EndReason = $endReason
        SampledPeakPrivateBytes = $peakPrivate
        SampledPeakWorkingSetBytes = $peakWorkingSet
        Csv = "$prefix.csv"
    } | ConvertTo-Json | Set-Content -LiteralPath "$prefix.json" -Encoding UTF8
    Write-Output "$prefix.json"
} finally {
    $process.Dispose()
}
