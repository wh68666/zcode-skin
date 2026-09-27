# publish-release.ps1 - create a GitHub Release for the current version and
# upload release\ZCodeSkin-v<version>.zip (run build-release.ps1 first).
# Version/tag are read from ZCodeSkin.app.ps1; auth comes from the stored git
# credential (Git Credential Manager) - the token is never printed or stored.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path

# version lives in app source (single source of truth, same as build-release.ps1)
$src = Get-Content (Join-Path $root 'ZCodeSkin.app.ps1') -Raw -Encoding UTF8
$v = if ($src -match '\$script:AppVersion\s*=\s*''([^'']+)''') { $Matches[1] } else { throw 'AppVersion not found in ZCodeSkin.app.ps1' }
$repo = 'wh68666/zcode-skin'
$tag = 'v' + $v
$assetName = 'ZCodeSkin-v' + $v + '.zip'
$zipPath = Join-Path $root ("release\" + $assetName)
if (-not (Test-Path $zipPath)) { throw "release zip not found: $zipPath (run build-release.ps1 first)" }
'publishing ' + $tag + ' from ' + $zipPath

# ---- token from GCM (never printed) ----
$credInput = "protocol=https`nhost=github.com`n"
$credOut = $credInput | git credential fill
$token = $null
foreach ($line in $credOut) {
    if ($line -match '^password=(.+)$') { $token = $Matches[1] }
}
if (-not $token) { throw 'no github token in credential store' }
'credential: OK (token retrieved, not shown)'

# ---- push tag ----
Set-Location $root
$existing = git tag -l $tag
if (-not $existing) {
    git tag -a $tag -m "ZCodeSkin v1.0.0"
}
# git writes progress to stderr; under EA=Stop that aborts the script - use cmd
cmd /c "git push origin $tag 2>nul"
'tag pushed'

# ---- release notes (edit per release) ----
$notes = @'
ZCode 桌面版（Electron）换肤工具，与 MonkeyCodeSkin 同架构：不修改官方安装包，通过本机 CDP 调试端口向渲染进程注入主题。

## 功能

- 托盘常驻应用：我的主题（应用 / 导入 zip / 删除 / 恢复官方外观）、远程主题仓库在线下载安装（api.dreamskin.cc，600+ 主题，与 MonkeyCodeSkin 共用同一个库）
- Codex Dream Skin 主题包 zip 零改动导入（manifest SHA-256 逐文件校验）
- 跑马灯公告（微云在线拉取，30 分钟自动刷新）、English / 简体中文 / 繁體中文 界面切换
- ZCode 安装位置自动探测（运行进程 / 常见目录 / 注册表卸载项 / 固定盘符扫描），全部失败时弹窗手动指定一次并记住
- 深色 / 浅色模式分别适配：壁纸直接绘制在窗口底层，表面面板按主题调色板半透明化，壁纸透出且文字可读
- 内置示例主题 aurora（极光渐变，壁纸程序化生成无版权问题）
- 启动时检查 GitHub Release 更新（托盘气泡提示）

## 使用

1. 解压到有写权限的独立目录（如 D:\ZCodeSkin）。注意：ZCodeSkin.exe 必须与 skin-lib.ps1 同目录
2. 双击 ZCodeSkin.exe；需本机已安装 ZCode 官方桌面版
3. 首次运行若 Windows 弹“已保护你的电脑”：点 更多信息 → 仍要运行（或右键 exe → 属性 → 解除锁定）

## 说明

- 换肤会自动重启 ZCode（带调试端口），未保存的输入会丢失
- 调试端口仅绑定 127.0.0.1，恢复官方外观（Official look）后即关闭
- exe 为 ps2exe 封装，个别杀软可能误报；介意可直接运行 ZCodeSkin.app.ps1（效果相同）
'@

# ---- create release ----
$hdr = @{ Authorization = "Bearer $token"; Accept = 'application/vnd.github+json'; 'X-GitHub-Api-Version' = '2022-11-28' }
$bodyObj = @{
    tag_name         = $tag
    name             = 'ZCodeSkin ' + $tag
    body             = $notes
    draft            = $false
    prerelease       = $false
    make_latest      = 'true'
}
$json = $bodyObj | ConvertTo-Json
$jsonFile = Join-Path $env:TEMP 'release-body.json'
[IO.File]::WriteAllText($jsonFile, $json, (New-Object Text.UTF8Encoding($false)))

try {
    $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases" -Method Post -Headers $hdr -InFile $jsonFile -ContentType 'application/json'
    'release created: id ' + $rel.id
} catch {
    # 422 already_exists -> fetch it
    $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/tags/$tag" -Headers $hdr
    'release already exists: id ' + $rel.id
}

# ---- upload asset (replace if exists) ----
foreach ($a in @($rel.assets)) {
    if ($a.name -eq $assetName) {
        Invoke-RestMethod -Uri ("https://api.github.com/repos/$repo/releases/assets/" + $a.id) -Method Delete -Headers $hdr | Out-Null
        'old asset deleted'
    }
}
$upUri = 'https://uploads.github.com/repos/' + $repo + '/releases/' + $rel.id + '/assets?name=' + $assetName
$asset = Invoke-RestMethod -Uri $upUri -Method Post -Headers $hdr -InFile $zipPath -ContentType 'application/zip'
'asset uploaded: ' + $asset.name + ' (' + [math]::Round($asset.size / 1KB) + ' KB)'
'asset url: ' + $asset.browser_download_url
'release url: ' + $rel.html_url
