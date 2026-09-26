# skin-clear.ps1 - restore ZCode's official look (ASCII only, PS 5.1)
# Closes ZCode (and the skin injector with it) and relaunches it normally,
# without the CDP debug port.
param([string]$AppExe = '')

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'skin-lib.ps1')

if (-not $AppExe) { $AppExe = Resolve-ZcodeExe '' }
if (-not $AppExe) { $AppExe = $script:ZC_EXE_DEFAULT }
$log = Join-Path $PSScriptRoot 'logs\clear.log'
Write-ZcLog -Path $log -Message "=== skin-clear: restoring official look ==="

[void](Stop-ZcodeApp)
Start-Process -FilePath $AppExe -WorkingDirectory (Split-Path $AppExe)
Write-ZcLog -Path $log -Message "App relaunched normally (no CDP, no skin)."
