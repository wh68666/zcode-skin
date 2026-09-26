# skin-start.ps1 - ZCode Skin launcher (ASCII only, PS 5.1)
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File skin-start.ps1 [-Theme aurora] [-Port 9223] [-Force]
param(
    [string]$Theme = 'aurora',
    [int]$Port = 9223,
    [switch]$Force,
    [string]$AppExe = ''
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'skin-lib.ps1')

if (-not $AppExe) { $AppExe = Resolve-ZcodeExe '' }
if (-not $AppExe) { $AppExe = $script:ZC_EXE_DEFAULT }
$log = Join-Path $PSScriptRoot 'logs\launcher.log'

# 0. Auto-import any Codex Dream Skin zips waiting in imports\
$importsDir = Join-Path $PSScriptRoot 'imports'
if (Test-Path $importsDir) {
    $doneDir = Join-Path $importsDir 'done'
    New-Item $doneDir -ItemType Directory -Force | Out-Null
    Get-ChildItem $importsDir -Filter *.zip -File -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $r = Import-CodexThemePack -ZipPath $_.FullName -ThemesRoot (Join-Path $PSScriptRoot 'themes')
            Move-Item -LiteralPath $_.FullName -Destination (Join-Path $doneDir $_.Name) -Force
            Write-ZcLog -Path $log -Message ("Auto-imported " + $_.Name + " -> theme '" + $r.Id + "'")
            Write-Host ("Imported: " + $_.Name + " as theme '" + $r.Id + "'")
        } catch {
            Write-ZcLog -Path $log -Message ("Auto-import FAILED for " + $_.Name + ": " + $_.Exception.Message)
            Move-Item -LiteralPath $_.FullName -Destination ($_.FullName + '.failed') -Force
        }
    }
}

$themeDir = Join-Path $PSScriptRoot ("themes\" + $Theme)
if (-not (Test-Path $themeDir)) { Write-Host "Theme not found: $themeDir"; exit 1 }

Write-ZcLog -Path $log -Message "=== skin-start theme=$Theme port=$Port ==="

# 1. If ZCode is already running, restart it (skin needs the CDP launch)
$running = Get-Process $script:ZC_PROC_NAME -ErrorAction SilentlyContinue
if ($running) {
    if (-not $Force) {
        $ans = Read-Host "ZCode is running. Restart it with skin? (y/N)"
        if ($ans -notmatch '^[Yy]') { Write-Host 'Aborted.'; exit 0 }
    }
    Write-ZcLog -Path $log -Message "Closing running instance..."
    [void](Stop-ZcodeApp)
}

# 2. Launch app with CDP port
$pid2 = Start-ZcodeAppWithCdp -Port $Port -AppExe $AppExe
Write-ZcLog -Path $log -Message "App started PID=$pid2"

# 3. Wait for CDP
$v = Wait-CdpOpen -Port $Port -TimeoutSec 30
if (-not $v) {
    Write-ZcLog -Path $log -Message "CDP port did not open. App runs WITHOUT skin (no modification was made)."
    exit 2
}
Write-ZcLog -Path $log -Message ("CDP open: " + $v.Browser)

# 4. Spawn injector in a separate minimized window (keeps applying theme to new targets)
$inj = Join-Path $PSScriptRoot 'skin-injector.ps1'
Start-Process powershell.exe -ArgumentList @(
    '-NoProfile', '-ExecutionPolicy', 'Bypass',
    '-File', "`"$inj`"",
    '-Theme', $Theme, '-Port', $Port
) -WindowStyle Minimized

Write-ZcLog -Path $log -Message "Injector spawned. To restore the official look, run skin-clear.ps1 (or just close the app and start ZCode normally)."
