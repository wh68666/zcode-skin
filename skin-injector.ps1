# skin-injector.ps1 - ZCode Skin injector (ASCII only, PS 5.1)
# Pushes the theme into every page target via CDP, then watches for new targets.
# Exits automatically when ZCode exits.
param(
    [string]$Theme = 'aurora',
    [int]$Port = 9223
)

$ErrorActionPreference = 'Continue'
$Host.UI.RawUI.WindowTitle = 'ZCode Skin Injector'
. (Join-Path $PSScriptRoot 'skin-lib.ps1')

$log = Join-Path $PSScriptRoot 'logs\injector.log'
$themeDir = Join-Path $PSScriptRoot ("themes\" + $Theme)

Write-ZcLog -Path $log -Message "=== injector start theme=$Theme port=$Port pid=$PID ==="

$pack = Get-ThemePack -ThemeDir $themeDir
$bootstrap = New-ZcodeSkinBootstrapJs -ThemePack $pack
$marker = ([string]$pack.Meta.id) + '@' + ([string]$pack.Meta.version)
Write-ZcLog -Path $log -Message ("Theme loaded: {0} v{1} bg={2} cssLen={3} bootstrapLen={4}" -f $pack.Name, $pack.Version, [bool]$pack.BgPath, $pack.Css.Length, $bootstrap.Length)

$injected = @{}
$script:cid = 10
while ($true) {
    try {
        $pages = Get-CdpPageTargets -Port $Port
        foreach ($p in $pages) {
            # target id changes on reload -> treated as new; marker check covers
            # same-id redocs the injector process itself may have missed
            if ($injected.ContainsKey($p.id) -and ((Get-TargetSkinMarker -Target $p) -eq $marker)) { continue }
            $script:cid++
            $ok = Push-ThemeToTarget -Target $p -BootstrapJs $bootstrap -LogPath $log
            if ($ok) { $injected[$p.id] = $true }
        }
    } catch {
        # HTTP endpoint failed: app may be closing or starting
    }
    if (-not (Get-Process $script:ZC_PROC_NAME -ErrorAction SilentlyContinue)) {
        Write-ZcLog -Path $log -Message "ZCode exited. Injector stopping."
        break
    }
    Start-Sleep -Seconds 5
}
Write-ZcLog -Path $log -Message "=== injector exit ==="
