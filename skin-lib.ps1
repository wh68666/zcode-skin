# skin-lib.ps1 - shared library for ZCode Skin MVP (ASCII only, PS 5.1)
# Dot-source this file: . "$PSScriptRoot\skin-lib.ps1"
#
# ZCode desktop is an ELECTRON app (not Tauri/WebView2 like MonkeyCode):
#   - CDP port is opened via the Chromium command line switch
#     "--remote-debugging-port=<port>" passed at launch (session-only)
#   - theming is Tailwind v4 semantic vars on html.theme-zai-dark/.theme-zai-light
#     (--color-background / --color-panel / --color-sidebar / --color-background-win-alt)
#   - there is NO built-in wallpaper layer (no data-mc-background), so the skin
#     paints the wallpaper on #root itself and turns the surface vars translucent
#     via color-mix(...) so the photo shows through the UI panels.

$script:ZC_EXE_DEFAULT = 'D:\PCSoftware\ZCode\ZCode.exe'
$script:ZC_PROC_NAME   = 'ZCode'
$script:ZC_CT          = [System.Threading.CancellationToken]::None

# Reference tuning profile - applied at inject time to EVERY theme (built-in /
# imported / gallery download) so every pack gets the same "wallpaper is the
# hero" treatment; theme pack files are never modified.
$script:ZC_TUNING = @{
    SurfaceOpacity = 0.5    # surface vars mixed to 50% opaque -> wallpaper shows through
    WallpaperTint  = 0.25   # theme base color laid over the photo (reference recipe)
    WallpaperSat   = 0.9    # photo saturation (reference recipe)
}

# ZCode's own palette per theme variant (measured in ZCode 3.14.3 stylesheet).
# Used when a theme pack does not supply the color itself.
$script:ZC_VARIANT_DEFAULTS = @{
    'dark'  = @{ bg = '#161616'; winAlt = '#2b2b2b'; panel = '#202020' }
    'light' = @{ bg = '#f8f8f8'; winAlt = '#ececee'; panel = '#ffffff' }
}

function Write-ZcLog {
    param([string]$Path, [string]$Message, [switch]$NoHost)
    $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss.fff'), $Message
    Add-Content -Path $Path -Value $line -Encoding UTF8
    # NoHost: ps2exe -noConsole pops Write-Host from dispatcher callbacks as MessageBoxes
    if (-not $NoHost) { Write-Host $line }
}

function Stop-ZcodeApp {
    param([string]$ProcName)
    if (-not $ProcName) { $ProcName = $script:ZC_PROC_NAME }
    # Close ZCode gracefully, then force. Electron child processes (GPU/renderer,
    # embedded browser) all share the ZCode.exe image name and die with the tree.
    $procs = Get-Process $ProcName -ErrorAction SilentlyContinue
    if (-not $procs) { return $false }
    foreach ($p in $procs) { [void]$p.CloseMainWindow() }
    [void](Wait-Process -Name $ProcName -Timeout 5 -ErrorAction SilentlyContinue)
    $left = Get-Process $ProcName -ErrorAction SilentlyContinue
    if ($left) { $left | Stop-Process -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Seconds 3
    return $true
}

function Start-ZcodeAppWithCdp {
    param([int]$Port = 9223, [string]$AppExe = $script:ZC_EXE_DEFAULT)
    if (-not (Test-Path $AppExe)) { throw "ZCode exe not found: $AppExe" }
    # Electron handles the Chromium switch natively; it only affects this launch.
    Start-Process -FilePath $AppExe -ArgumentList "--remote-debugging-port=$Port" -WorkingDirectory (Split-Path $AppExe)
    Start-Sleep -Milliseconds 500
    $procName = [IO.Path]::GetFileNameWithoutExtension($AppExe)
    return (Get-Process $procName -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Id)
}

# Locate the ZCode desktop exe on any machine: config choice -> running
# process -> well-known folders -> registry uninstall entries. Returns $null if all fail.
function Resolve-ZcodeExe {
    param([string]$Configured, [string[]]$Roots = @('D:\PCSoftware\ZCode', 'D:\ZCode', 'C:\ZCode', "$env:LOCALAPPDATA\Programs", $env:ProgramFiles, ${env:ProgramFiles(x86)}))
    if ($Configured -and (Test-Path $Configured)) { return $Configured }
    try {
        $p = Get-Process $script:ZC_PROC_NAME -ErrorAction SilentlyContinue | Where-Object { $_.Path } | Select-Object -First 1
        if ($p -and $p.Path) { return $p.Path }
    } catch { }
    foreach ($r in $Roots) {
        if (-not $r -or -not (Test-Path $r)) { continue }
        try {
            $hit = Get-ChildItem $r -Filter 'ZCode.exe' -Recurse -Depth 3 -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($hit) { return $hit.FullName }
        } catch { }
    }
    foreach ($k in @('HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
                     'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
                     'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*')) {
        try {
            $rows = Get-ItemProperty $k -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like '*ZCode*' }
            foreach ($row in $rows) {
                $loc = if ($row.InstallLocation) { ([string]$row.InstallLocation).Trim('"').Trim() } else { $null }
                if ($loc) {
                    $cand = Join-Path $loc 'ZCode.exe'
                    if (Test-Path $cand) { return $cand }
                }
                $icon = if ($row.DisplayIcon) { ([string]$row.DisplayIcon).Trim('"') -replace ',\d+$', '' } else { $null }
                if ($icon -and ($icon -like '*ZCode.exe') -and (Test-Path $icon)) { return $icon }
            }
        } catch { }
    }
    return $null
}

function Wait-CdpOpen {
    param([int]$Port = 9223, [int]$TimeoutSec = 30)
    for ($i = 1; $i -le $TimeoutSec; $i++) {
        Start-Sleep -Seconds 1
        try {
            $v = Invoke-RestMethod "http://127.0.0.1:$Port/json/version" -TimeoutSec 2
            return $v
        } catch { }
    }
    return $null
}

# ---------- minimal CDP-over-WebSocket client (verified in PoC) ----------

function Connect-CdpWs {
    param([string]$WsUrl)
    $ws = New-Object System.Net.WebSockets.ClientWebSocket
    [void]$ws.ConnectAsync([Uri]$WsUrl, $script:ZC_CT).Wait(8000)
    if ($ws.State -ne [System.Net.WebSockets.WebSocketState]::Open) {
        $st = $ws.State; $ws.Dispose(); throw "WS connect failed: $st"
    }
    return $ws
}

function Disconnect-CdpWs {
    param($Ws)
    try {
        if ($Ws -and $Ws.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
            [void]$Ws.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, 'done', $script:ZC_CT).Wait(2000)
        }
    } catch { }
    if ($Ws) { $Ws.Dispose() }
}

function Send-CdpJson {
    param($Ws, $Obj)
    $b = [Text.Encoding]::UTF8.GetBytes(($Obj | ConvertTo-Json -Depth 8 -Compress))
    [void]$Ws.SendAsync([ArraySegment[byte]]::new($b), [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $script:ZC_CT).Wait(10000)
}

function Receive-CdpMsg {
    param($Ws, [int]$TimeoutMs = 15000)
    $buf = New-Object byte[] 4194304
    $ms  = New-Object System.IO.MemoryStream
    $sw  = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sw.ElapsedMilliseconds -lt $TimeoutMs) {
        $t = $Ws.ReceiveAsync([ArraySegment[byte]]::new($buf), $script:ZC_CT)
        if (-not $t.Wait(2000)) { continue }
        $r = $t.Result
        if ($r.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) { throw 'ws closed by peer' }
        $ms.Write($buf, 0, $r.Count)
        if ($r.EndOfMessage) {
            $s = [Text.Encoding]::UTF8.GetString($ms.ToArray()); $ms.SetLength(0); return $s
        }
    }
    throw 'recv timeout'
}

function Invoke-Cdp {
    param($Ws, [int]$Id, [string]$Method, $Params)
    Send-CdpJson -Ws $Ws -Obj @{ id = $Id; method = $Method; params = $Params }
    $want = '"id":' + $Id + '\b'
    while ($true) {
        $m = Receive-CdpMsg -Ws $Ws -TimeoutMs 20000
        if ($m -match $want) { return $m }
    }
}

function Get-CdpPageTargets {
    param([int]$Port = 9223)
    $targets = Invoke-RestMethod "http://127.0.0.1:$Port/json" -TimeoutSec 3
    return @($targets | Where-Object { $_.type -eq 'page' -and $_.webSocketDebuggerUrl })
}

# ---------- theme pack ----------

function Get-ThemePack {
    param([string]$ThemeDir)
    $jsonPath = Join-Path $ThemeDir 'theme.json'
    if (-not (Test-Path $jsonPath)) { throw "theme.json not found in $ThemeDir" }
    $meta = [IO.File]::ReadAllText($jsonPath, [Text.Encoding]::UTF8) | ConvertFrom-Json

    $bgPath = $null
    foreach ($ext in '.jpg', '.jpeg', '.png', '.webp') {
        $cand = Join-Path $ThemeDir ("background" + $ext)
        if (Test-Path $cand) { $bgPath = $cand; break }
    }
    $cssPath = Join-Path $ThemeDir 'theme.css'
    $css = ''
    if (Test-Path $cssPath) { $css = [IO.File]::ReadAllText($cssPath, [Text.Encoding]::UTF8) }

    return @{
        Meta    = $meta
        BgPath  = $bgPath
        Css     = $css
        Name    = $meta.id
        Version = [string]$meta.version
    }
}

# Pull a 6-digit hex color that a theme pack CSS assigns to one of the ZCode
# surface variables (importer writes them; hand-made packs may too).
function Get-ZcodePackSurfaceColor {
    param([string]$Css, [string]$VarName)
    if ($Css -match ('--' + $VarName + '\s*:\s*#([0-9a-fA-F]{6})[0-9a-fA-F]{0,2}\s*;')) { return '#' + $Matches[1] }
    return ''
}

function New-ZcodeSkinBootstrapJs {
    # Build the injected bootstrap for ZCode. Paints the wallpaper on #root and
    # turns ZCode's Tailwind surface variables translucent via color-mix, so the
    # photo shows through the UI. Theme-variant scoped: a dark pack recolors the
    # dark variant, the light variant keeps ZCode's own (translucent) palette so
    # text stays readable. Idempotent: safe to run on every new document.
    # The (potentially huge) wallpaper data-URI is embedded as a raw single-quoted
    # JS string (base64 is JS-string-safe) in a plain background-image declaration,
    # so Chromium's 2^21 char cap on custom properties never applies.
    param($ThemePack, $Tuning)
    $tun = if ($Tuning) { $Tuning } else { $script:ZC_TUNING }
    $meta = $ThemePack.Meta
    $opacity = [double]($(if ($null -ne $tun.SurfaceOpacity) { $tun.SurfaceOpacity } else { $meta.surfaceOpacity }))
    if ($opacity -le 0 -or $opacity -gt 1) { $opacity = 0.5 }
    $op = [int]($opacity * 100)
    $tintA = [string]$tun.WallpaperTint
    $fit = [string]$meta.fit
    if (-not $fit) { $fit = 'cover' }
    $pos = [string]$meta.position
    if (-not $pos) { $pos = 'center' }

    # pack palette (empty when the pack does not set it)
    $packBg    = Get-ZcodePackSurfaceColor -Css $ThemePack.Css -VarName 'color-background'
    $packPanel = Get-ZcodePackSurfaceColor -Css $ThemePack.Css -VarName 'color-panel'
    $packWin   = Get-ZcodePackSurfaceColor -Css $ThemePack.Css -VarName 'color-background-win-alt'
    $appearance = [string]$meta.appearance

    $d = $script:ZC_VARIANT_DEFAULTS['dark']
    $l = $script:ZC_VARIANT_DEFAULTS['light']
    # a pack recolors its own appearance variant; no appearance field -> both
    $dBg    = if (($appearance -ne 'light') -and $packBg) { $packBg } else { $d.bg }
    $dPanel = if (($appearance -ne 'light') -and $packPanel) { $packPanel } else { $d.panel }
    $dWin   = if (($appearance -ne 'light') -and $packWin) { $packWin } else { $d.winAlt }
    $lBg    = if (($appearance -ne 'dark') -and $packBg) { $packBg } else { $l.bg }
    $lPanel = if (($appearance -ne 'dark') -and $packPanel) { $packPanel } else { $l.panel }
    $lWin   = if (($appearance -ne 'dark') -and $packWin) { $packWin } else { $l.winAlt }

    $varsCss = @"
html.theme-zai-dark[data-zc-skin=`"active`"]{
  --color-background:color-mix(in srgb, $dBg $op%, transparent) !important;
  --color-sidebar:color-mix(in srgb, $dBg $op%, transparent) !important;
  --color-panel:color-mix(in srgb, $dPanel $op%, transparent) !important;
  --color-header:color-mix(in srgb, $dPanel $op%, transparent) !important;
  --color-background-win-alt:color-mix(in srgb, $dWin $op%, transparent) !important;
}
html.theme-zai-light[data-zc-skin=`"active`"]{
  --color-background:color-mix(in srgb, $lBg $op%, transparent) !important;
  --color-sidebar:color-mix(in srgb, $lBg $op%, transparent) !important;
  --color-panel:color-mix(in srgb, $lPanel $op%, transparent) !important;
  --color-header:color-mix(in srgb, $lPanel $op%, transparent) !important;
  --color-background-win-alt:color-mix(in srgb, $lWin $op%, transparent) !important;
}
"@

    $bgExpr = 'false'
    $imgExpr = 'null'
    if ($ThemePack.BgPath) {
        $mime = @{ '.jpg' = 'image/jpeg'; '.jpeg' = 'image/jpeg'; '.png' = 'image/png'; '.webp' = 'image/webp' }[[IO.Path]::GetExtension($ThemePack.BgPath).ToLower()]
        $b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($ThemePack.BgPath))
        $dataUrl = 'data:' + $mime + ';base64,' + $b64
        $tint = if ($packBg) { $packBg } else { $d.bg }
        $tr = [Convert]::ToInt32($tint.Substring(1, 2), 16); $tg = [Convert]::ToInt32($tint.Substring(3, 2), 16); $tb = [Convert]::ToInt32($tint.Substring(5, 2), 16)
        # paint the wallpaper DIRECTLY on #root (plain declaration, no custom property)
        $paintCss = 'html[data-zc-skin="active"] #root{background-image:linear-gradient(rgba(' + $tr + ',' + $tg + ',' + $tb + ',' + $tintA + '), rgba(' + $tr + ',' + $tg + ',' + $tb + ',' + $tintA + ')), url("' + $dataUrl + '") !important;background-size:' + $fit + ' !important;background-position:' + $pos + ' !important;background-repeat:no-repeat !important;}'
        $imgExpr = "'" + $paintCss + "'"
        $bgExpr = 'true'
    }

    $cssJson = ($varsCss + "`n" + $ThemePack.Css) | ConvertTo-Json -Compress

    return @"
(function(){
try{
  var t=document.documentElement;
  var OLD=document.getElementById('zc-skin-style'); if(OLD) OLD.remove();
  if($bgExpr){ t.setAttribute('data-zc-skin','active'); } else { t.removeAttribute('data-zc-skin'); }
  var css=$cssJson;
  var IMG=$imgExpr;
  if(IMG){ css+=`"\n`"+IMG; }
  var s=document.createElement('style'); s.id='zc-skin-style'; s.textContent=css;
  (document.head||document.documentElement).appendChild(s);
  window.__ZC_SKIN='$([string]$meta.id)@$([string]$meta.version)';
}catch(e){}
})()
"@
}

function Push-ThemeToTarget {
    param($Target, $BootstrapJs, $LogPath)
    try {
        $ws = Connect-CdpWs -WsUrl $Target.webSocketDebuggerUrl
        try {
            [void](Invoke-Cdp -Ws $ws -Id 1 -Method 'Runtime.enable' -Params @{})
            [void](Invoke-Cdp -Ws $ws -Id 2 -Method 'Page.enable' -Params @{})
            $r1 = Invoke-Cdp -Ws $ws -Id 3 -Method 'Runtime.evaluate' -Params @{ expression = $BootstrapJs; returnByValue = $true }
            if ($r1 -match '"subtype":"error"') {
                Write-ZcLog -Path $LogPath -Message ("APPLY ERROR -> {0} : {1}" -f $Target.url, $r1.Substring(0, [Math]::Min(200, $r1.Length)))
                return $false
            }
            $r2 = Invoke-Cdp -Ws $ws -Id 4 -Method 'Page.addScriptToEvaluateOnNewDocument' -Params @{ source = $BootstrapJs }
            Write-ZcLog -Path $LogPath -Message ("THEME OK -> {0} | apply={1}" -f $Target.url, $r1.Substring(0, [Math]::Min(80, $r1.Length)))
            return $true
        } finally { Disconnect-CdpWs -Ws $ws }
    } catch {
        Write-ZcLog -Path $LogPath -Message ("THEME FAIL -> {0} : {1}" -f $Target.url, $_.Exception.Message)
        return $false
    }
}

# Read the skin marker (window.__ZC_SKIN = "<id>@<version>") from a page target.
# CDP drops addScriptToEvaluateOnNewDocument registrations when the injector's
# WebSocket disconnects, so a reloaded page silently loses the skin - the watch
# loops use this marker to detect that and re-push. Returns '' when missing.
function Get-TargetSkinMarker {
    param($Target)
    try {
        $ws = Connect-CdpWs -WsUrl $Target.webSocketDebuggerUrl
        try {
            [void](Invoke-Cdp -Ws $ws -Id 1 -Method 'Runtime.enable' -Params @{})
            $r = Invoke-Cdp -Ws $ws -Id 2 -Method 'Runtime.evaluate' -Params @{ expression = 'window.__ZC_SKIN||""'; returnByValue = $true }
            $m = [regex]::Match($r, '"value"\s*:\s*"([^"]*)"')
            if ($m.Success) { return $m.Groups[1].Value }
            return ''
        } finally { Disconnect-CdpWs -Ws $ws }
    } catch { return '' }
}

# ---------- Codex Dream Skin theme pack import ----------

function Read-ZipEntryBytes {
    param($Entry)
    $ms = New-Object IO.MemoryStream
    $s = $Entry.Open()
    try { $s.CopyTo($ms) } finally { $s.Dispose() }
    , $ms.ToArray()
}

function Read-ZipEntryText {
    param($Entry)
    [Text.Encoding]::UTF8.GetString((Read-ZipEntryBytes -Entry $Entry))
}

function New-ZcodeCssFromCodexColors {
    # Map Codex Dream Skin color tokens to ZCode (Tailwind v4) palette vars.
    param($Colors)
    function HexOk([string]$h) { $h -match '^#([0-9a-fA-F]{3}|[0-9a-fA-F]{4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$' }
    function HexStrip([string]$h) { if ($h -match '^#[0-9a-fA-F]{8}$') { $h.Substring(0, 7) } else { $h } }
    $pairs = @(
        @('background', '--color-background'),
        @('background', '--color-sidebar'),
        @('panel', '--color-panel'),
        @('panel', '--color-header'),
        @('panelAlt', '--color-background-win-alt'),
        @('accent', '--color-primary'),
        @('accent', '--color-brand'),
        @('accentAlt', '--color-accent'),
        @('secondary', '--color-secondary'),
        @('highlight', '--color-info'),
        @('text', '--color-foreground'),
        @('line', '--color-border')
    )
    $lines = @('/* generated by ZCode Skin from a Codex Dream Skin package */', 'html[data-zc-skin="active"]{')
    foreach ($p in $pairs) {
        $h = ''
        if ($Colors) { $h = [string]$Colors.($p[0]) }
        if ($h -and (HexOk $h)) { $lines += ('  ' + $p[1] + ':' + (HexStrip $h) + ';') }
    }
    $lines += '}'
    (($lines -join "`r`n") + "`r`n")
}

function Import-CodexThemePack {
    # Import a Codex Dream Skin theme package (zip) into themes\<id>\.
    # Supports manifest packs (packageVersion 1, sha256 verified) and simplified
    # local zips (theme.json + optional theme.css + background image). Mirrors the
    # Dream Skin contract limits: zip <=32 MiB, <=32 entries, <=64 MiB extracted.
    # Files may sit at zip root or inside a single top-level directory.
    param(
        [Parameter(Mandatory)][string]$ZipPath,
        [Parameter(Mandatory)][string]$ThemesRoot,
        [switch]$Force
    )
    if (-not (Test-Path $ZipPath)) { throw ("zip not found: " + $ZipPath) }
    $zipLen = (Get-Item $ZipPath).Length
    if ($zipLen -gt 32MB) { throw ("zip larger than 32 MiB: " + $zipLen) }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
        if ($zip.Entries.Count -gt 32) { throw ("zip has more than 32 entries: " + $zip.Entries.Count) }
        $sum = ($zip.Entries | Measure-Object -Property Length -Sum).Sum
        if ($sum -gt 64MB) { throw ("extracted content larger than 64 MiB: " + $sum) }
        foreach ($e in $zip.Entries) {
            if ($e.FullName -match '(^|[\\/])\.\.([\\/]|$)' -or $e.FullName -match '^[A-Za-z]:') { throw ("unsafe entry path: " + $e.FullName) }
        }

        # locate theme.json (zip root or single top-level directory)
        $prefix = ''
        $themeEntry = $zip.Entries | Where-Object { $_.FullName -eq 'theme.json' } | Select-Object -First 1
        if (-not $themeEntry) {
            $cands = @($zip.Entries | Where-Object { $_.FullName -match '^[^/\\]+[/\\]theme\.json$' })
            if ($cands.Count -gt 0) {
                $themeEntry = $cands[0]
                $prefix = $themeEntry.FullName.Substring(0, $themeEntry.FullName.Length - 'theme.json'.Length)
            }
        }
        if (-not $themeEntry) { throw 'theme.json not found (zip root or single subdir)' }

        function FindZip([string]$name) {
            $e = $zip.Entries | Where-Object { $_.FullName -eq ($prefix + $name) } | Select-Object -First 1
            if (-not $e -and $prefix) { $e = $zip.Entries | Where-Object { $_.FullName -eq $name } | Select-Object -First 1 }
            return $e
        }

        $t = (Read-ZipEntryText -Entry $themeEntry) | ConvertFrom-Json
        $id = [string]$t.id
        if ($id -notmatch '^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$') { throw ("invalid or missing theme id: " + $id) }
        $imageName = [string]$t.image
        if (-not $imageName) { throw 'theme.json has no image field' }
        $imgExt = [IO.Path]::GetExtension($imageName).ToLower()
        if ('.jpg', '.jpeg', '.png', '.webp' -notcontains $imgExt) { throw ("unsupported background image type: " + $imgExt) }
        $imgEntry = FindZip $imageName
        if (-not $imgEntry) { throw ("background image entry not found: " + $imageName) }

        # integrity: verify sha256 for every file listed in manifest.json (if present)
        $manifest = $null
        $manEntry = FindZip 'manifest.json'
        if ($manEntry) {
            $manifest = (Read-ZipEntryText -Entry $manEntry) | ConvertFrom-Json
            $sha = [Security.Cryptography.SHA256]::Create()
            try {
                foreach ($f in $manifest.files) {
                    $fe = FindZip ([string]$f.path)
                    if (-not $fe) { throw ("manifest lists missing file: " + $f.path) }
                    $hash = [BitConverter]::ToString($sha.ComputeHash((Read-ZipEntryBytes -Entry $fe))).Replace('-', '').ToLower()
                    if ($hash -ne ([string]$f.sha256).ToLower()) { throw ("sha256 mismatch: " + $f.path) }
                }
            } finally { $sha.Dispose() }
        }

        $dest = Join-Path $ThemesRoot $id
        if ((Test-Path $dest) -and -not $Force) { throw ("theme dir already exists: " + $dest + " (use -Force to overwrite)") }
        New-Item $dest -ItemType Directory -Force | Out-Null
        $utf8 = New-Object Text.UTF8Encoding($false)

        $bgName = 'background' + $imgExt
        [IO.File]::WriteAllBytes((Join-Path $dest $bgName), (Read-ZipEntryBytes -Entry $imgEntry))

        # original Codex theme.css targets the Codex DOM ([data-ds-part=...]); keep
        # for reference but do NOT inject (selectors are meaningless inside ZCode)
        $cssEntry = FindZip 'theme.css'
        if ($cssEntry) {
            $orig = Read-ZipEntryText -Entry $cssEntry
            if ($orig.Trim()) { [IO.File]::WriteAllText((Join-Path $dest 'codex-extra.css'), $orig, $utf8) }
        }

        # surface opacity: honor the author's panel alpha (e.g. #1e1e1e55 -> 0.33)
        $opacity = 0.72
        $panelHex = ''
        if ($t.colors) { $panelHex = [string]$t.colors.panel }
        if ($panelHex -match '^#[0-9a-fA-F]{8}$') {
            $a = [Convert]::ToInt32($panelHex.Substring(7, 2), 16) / 255.0
            if ($a -ge 0.10 -and $a -le 1.0) { $opacity = [math]::Round($a, 2) }
        }
        # focus point -> background-position percentage
        $fx = 0.5; $fy = 0.5
        if ($t.art) {
            if ($null -ne $t.art.focusX) { $fx = [double]$t.art.focusX }
            if ($null -ne $t.art.focusY) { $fy = [double]$t.art.focusY }
        }
        $pos = ('{0}%' -f [int][math]::Round($fx * 100)) + ' ' + ('{0}%' -f [int][math]::Round($fy * 100))

        $meta = [ordered]@{
            id             = $id
            name           = [string]$t.name
            version        = $(if ($manifest) { [string]$manifest.version } else { '0.0.0' })
            appearance     = [string]$t.appearance
            surfaceOpacity = $opacity
            blurPx         = 0
            fit            = 'cover'
            position       = $pos
            background     = $bgName
            imported       = [ordered]@{
                source     = 'codex-dream-skin'
                license    = $(if ($manifest -and $manifest.license) { [string]$manifest.license } else { '' })
                publisher  = $(if ($manifest -and $manifest.publisher) { [string]$manifest.publisher.displayName } else { '' })
                importedAt = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
            }
        }
        [IO.File]::WriteAllText((Join-Path $dest 'theme.json'), ($meta | ConvertTo-Json -Depth 5), $utf8)
        [IO.File]::WriteAllText((Join-Path $dest 'theme.css'), (New-ZcodeCssFromCodexColors -Colors $t.colors), $utf8)

        $lic = ''
        if ($manifest -and $manifest.license) { $lic = [string]$manifest.license }
        return @{ Id = $id; Name = [string]$t.name; Dir = $dest; SurfaceOpacity = $opacity; Verified = [bool]$manifest; License = $lic }
    } finally { $zip.Dispose() }
}
