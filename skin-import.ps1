# skin-import.ps1 - import a Codex Dream Skin theme zip into themes\ (ASCII only)
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File skin-import.ps1 -Zip <path.zip> [-Force]
param(
    [Parameter(Mandatory)][string]$Zip,
    [switch]$Force
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'skin-lib.ps1')

try {
    $r = Import-CodexThemePack -ZipPath $Zip -ThemesRoot (Join-Path $PSScriptRoot 'themes') -Force:$Force
} catch {
    Write-Host ("IMPORT FAILED: " + $_.Exception.Message)
    exit 1
}

Write-Host ("Imported theme id : " + $r.Id)
Write-Host ("Name              : " + $r.Name)
Write-Host ("Directory         : " + $r.Dir)
Write-Host ("Manifest verified : " + $r.Verified)
if ($r.License) { Write-Host ("License           : " + $r.License) }
Write-Host ("Surface opacity   : " + $r.SurfaceOpacity)
Write-Host ""
Write-Host ("Apply it: powershell -NoProfile -ExecutionPolicy Bypass -File skin-start.ps1 -Theme " + $r.Id + " -Force")
