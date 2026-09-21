[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Miner,
    [Parameter(Mandatory = $true)][string]$Address,
    [Parameter(Mandatory = $true)][string]$Worker,
    [Parameter(Mandatory = $true)][string]$PoolHost,
    [Parameter(Mandatory = $true)][int]$PoolPort,
    [Parameter(Mandatory = $true)][string]$Password,
    [Parameter(Mandatory = $true)][string]$Gpu
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Stop-FleetProcess {
    param([System.Diagnostics.Process]$Process)
    if ($null -eq $Process -or $Process.HasExited) { return }
    try { [void]$Process.CloseMainWindow() } catch { }
    try {
        if ($Process.WaitForExit(5000)) { return }
    } catch { }
    try { Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue } catch { }
    try { [void]$Process.WaitForExit(5000) } catch { }
}

if ($Address -notmatch '^prl1[0-9a-z]{59}$') { throw 'PRL address is malformed' }
if ($Worker -notmatch '^[A-Za-z0-9_-]{1,64}$') { throw 'Worker must use letters, numbers, underscore, or hyphen' }
if ($PoolHost -notmatch '^(?=.{1,253}$)[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?$') { throw 'Pool host is malformed' }
if ($PoolPort -lt 1 -or $PoolPort -gt 65535) { throw 'Pool port must be 1..65535' }
if ($Password -notmatch '^x(?:;d=[0-9]{1,10})?$') { throw 'Password must be x or x;d=<integer>' }
if ($Gpu -notmatch '^(?:all|[0-9]{1,2})$') { throw 'GPU must be all or a device index' }

$minerPath = (Resolve-Path -LiteralPath $Miner -ErrorAction Stop).Path
if ([IO.Path]::GetExtension($minerPath) -ne '.exe') { throw 'Miner must be an executable' }
$nvidia = @(Get-Command nvidia-smi.exe -CommandType Application -ErrorAction Stop)[0]
$nvidiaPath = $nvidia.Source
$rows = @(& $nvidiaPath '--query-gpu=index,compute_cap' '--format=csv,noheader,nounits')
if ($LASTEXITCODE -ne 0) { throw 'nvidia-smi inventory failed' }

$devices = @()
foreach ($row in $rows) {
    if ($row -notmatch '^\s*([0-9]+)\s*,\s*([0-9]+\.[0-9]+)\s*$') { throw 'Unexpected nvidia-smi inventory shape' }
    $index = [int]$Matches[1]
    $capability = $Matches[2]
    if ($capability -in @('8.6', '8.9', '12.0')) {
        $devices += [pscustomobject]@{ Index = $index; Capability = $capability }
    } else {
        Write-Host "AlphaMiner: skipping GPU $index (unsupported CC $capability)"
    }
}
if ($Gpu -ne 'all') {
    $requested = [int]$Gpu
    $devices = @($devices | Where-Object { $_.Index -eq $requested })
    if ($devices.Count -ne 1) { throw "Requested GPU $requested is absent or unsupported" }
}
if ($devices.Count -eq 0) { throw 'No supported NVIDIA GPU found (need CC 8.6, 8.9, or 12.0)' }

$processes = @()
$sentinel = $null
$forcedCleanup = $false
$exitCode = 2
try {
    $sentinel = Start-Process -FilePath powershell.exe -ArgumentList '-NoProfile -NonInteractive -Command "Start-Sleep -Seconds 2147483"' -WindowStyle Hidden -PassThru
    $env:ALPHA_MINER_FLEET_PARENT_PID = [string]$sentinel.Id
    foreach ($device in $devices) {
        $gpuWorker = $Worker + '.g' + $device.Index
        $fullWorker = $Address + '.' + $gpuWorker
        $arguments = '--host "' + $PoolHost + '" --port "' + $PoolPort + '" --worker "' + $fullWorker + '" --password "' + $Password + '" --gpu "' + $device.Index + '"'
        Write-Host "AlphaMiner: starting GPU $($device.Index) CC $($device.Capability) worker $gpuWorker"
        $processes += Start-Process -FilePath $minerPath -ArgumentList $arguments -WorkingDirectory (Split-Path -Parent $minerPath) -NoNewWindow -PassThru
    }
    Remove-Item Env:ALPHA_MINER_FLEET_PARENT_PID -ErrorAction SilentlyContinue
    while ($true) {
        Start-Sleep -Seconds 1
        $exited = @($processes | Where-Object { $_.HasExited })
        if ($exited.Count -gt 0) {
            $exitCode = $exited[0].ExitCode
            Write-Host "AlphaMiner: GPU process exited with code $exitCode; stopping fleet"
            break
        }
    }
} finally {
    Remove-Item Env:ALPHA_MINER_FLEET_PARENT_PID -ErrorAction SilentlyContinue
    if ($null -ne $sentinel -and -not $sentinel.HasExited) {
        Stop-Process -Id $sentinel.Id -Force -ErrorAction SilentlyContinue
    }
    $deadline = [DateTime]::UtcNow.AddSeconds(15)
    while (@($processes | Where-Object { -not $_.HasExited }).Count -gt 0 -and [DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 200
    }
    foreach ($process in $processes) {
        if (-not $process.HasExited) {
            $forcedCleanup = $true
            Stop-FleetProcess -Process $process
        }
        $process.Dispose()
    }
    if ($null -ne $sentinel) { $sentinel.Dispose() }
    if ($forcedCleanup) { $exitCode = 75 }
}
exit $exitCode
