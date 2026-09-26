# ZCode Skin

给 ZCode 桌面版（Electron）换肤的工具，与 [MonkeyCodeSkin](https://github.com/wh68666/monkeyscode-skin) 同源同架构：
**不修改官方安装包**，通过本机 CDP（Chrome DevTools Protocol）向渲染进程注入主题。
远程主题库与 MonkeyCodeSkin 完全共用（api.dreamskin.cc，600+ 主题），Codex Dream Skin
主题包 zip 可零改动导入。

## 目录结构

```
ZCodeSkin\
├─ skin-lib.ps1         共享库：CDP 客户端、应用启停、主题包加载、注入脚本生成
├─ ZCodeSkin.exe        托盘应用（双击即用）
├─ ZCodeSkin.app.ps1    托盘应用源码（与 exe 等效）
├─ app\                 构建：build.ps1（ps2exe 打包）、app.ico
├─ skin-start.ps1       启动器：自动导入 imports\ 下的 zip → 关闭现有实例 → 带调试端口重启 → 拉起注入器
├─ skin-injector.ps1    注入器：向所有页面目标推送主题，监听新窗口，应用退出时自动结束
├─ skin-import.ps1      导入器：Codex Dream Skin 主题包 zip -> themes\<id>\
├─ skin-clear.ps1       恢复：关闭并正常重启 ZCode（无调试端口、无皮肤）
├─ themes\aurora\       示例主题包（极光渐变 + 暗色玻璃，壁纸程序化生成，无版权问题）
│   ├─ theme.json       元数据与壁纸参数（surfaceOpacity / fit / position / appearance）
│   ├─ theme.css        附加 CSS（ZCode 调色板变量覆盖）
│   └─ background.jpg   壁纸（1920x1080）
└─ logs\                运行日志
```

## 安装与分发（发给其他用户）

发布包：仓库根目录 `build-release.ps1` 一键产出 `release\ZCodeSkin-v<版本>.zip`，
内含 `ZCodeSkin.exe` + `skin-lib.ps1` + 本 README。**exe 必须与 skin-lib.ps1 同目录**（运行时读取）。

1. 解压到一个有写权限的独立目录（如 `D:\ZCodeSkin`），首次运行会在旁边生成
   config.json / themes\ / logs\ / assets\，这些是用户数据，升级时不要删
2. 双击 `ZCodeSkin.exe`。需本机已安装 ZCode 官方桌面版：程序会自动探测安装位置
   （运行中的进程 / 常见目录 / 注册表），找不到时会弹窗让你选择 ZCode.exe，
   选择会被记住（存于 config.json 的 appExe 字段）
3. 首次运行若 Windows 弹“已保护你的电脑”：点 **更多信息 → 仍要运行**；或右键 exe →
   属性 → 勾选 **解除锁定** 后再运行。ps2exe 封装的 exe 可能被个别杀软误报；
   介意可直接运行 ZCodeSkin.app.ps1（效果相同）
4. 升级新版本：用新 zip 覆盖 `ZCodeSkin.exe` 和 `skin-lib.ps1` 两个文件即可，
   配置与已装主题自动保留

## ZCodeSkin.exe（托盘应用，推荐）

```
ZCodeSkin.exe   双击启动，常驻托盘；主窗口含两个标签页
```

- **跑马灯公告**：主窗口顶部滚动显示微云分享笔记的内容（share.weiyun.com/8ptg57V2，
  与 MonkeyCodeSkin 共用同一条公告，微云里改内容即生效）；启动时在线拉取，失败回退到
  logs\announcement.txt 缓存，之后每 30 分钟自动刷新
- **语言切换**：右上角下拉框 English / 简体中文 / 繁體中文，切换后全界面立即更新；
  选择保存在 config.json 的 lang 字段，首次启动按系统语言自动选择
- **My Themes**：已装主题列表（双击或点 Apply 应用，会自动重启 ZCode 并注入）；
  拖拽 zip 到列表或点 Import zip... 导入；选中主题后点 Delete theme 删除主题包
  （弹窗确认，删除使用中的主题会同时清除皮肤记录）；Official look 恢复官方外观
- **Repository (Remote)**（中文页签：主题仓库）：内置远程图库浏览器（api.dreamskin.cc，
  与 MonkeyCodeSkin 同一个库，600+ 主题），主题名后以太阳/月亮小图标标注 light / dark
  外观；双击或点 Download and install selected 直接下载安装，Load more 加载更多，
  也可点 Open in browser 去网页看预览
- **托盘图标**：左键双击打开主窗口；右键菜单直接切换已装主题 / 恢复官方外观 / 退出
- 应用本身即注入器（常驻期间自动给新开的 ZCode 窗口补注入）；当前主题记录在 config.json，
  重启 exe 后若 ZCode 已带调试端口运行则自动接管
- 若 ZCode 正在运行，切换主题会先关闭它再带调试端口重启（会话内未保存的输入会丢失）
- 重新构建：`powershell -File app\build.ps1`（需网络安装 ps2exe 模块）
- exe 为 ps2exe 封装，个别杀软可能误报；介意可直接运行 ZCodeSkin.app.ps1（效果相同）

## 使用方法（脚本模式）

```powershell
# 换肤（会自动重启 ZCode；-Force 跳过确认）
powershell -NoProfile -ExecutionPolicy Bypass -File skin-start.ps1 -Theme aurora -Force

# 恢复官方外观
powershell -NoProfile -ExecutionPolicy Bypass -File skin-clear.ps1
```

要求：Windows PowerShell 5.1（系统自带）。ZCode 安装位置自动探测（本机实测
`D:\PCSoftware\ZCode\ZCode.exe`），也可用 `-AppExe` 指定。

## 直接使用 Codex Dream Skin 主题包（已实测）

从 dreamskin.cc 等渠道下载的 Codex 主题包（zip）可以零改动使用，两种方式任选：

```powershell
# 方式一：手动导入后换肤
powershell -NoProfile -ExecutionPolicy Bypass -File skin-import.ps1 -Zip C:\path\to\theme.zip

# 方式二：把 zip 丢进 imports\ 文件夹，skin-start 会自动导入（处理完移入 imports\done\）
powershell -NoProfile -ExecutionPolicy Bypass -File skin-start.ps1 -Theme <主题id> -Force
```

导入器兼容 Dream Skin v1 契约（zip ≤32MiB / ≤32 条目 / 解压后 ≤64MiB），带 manifest.json
的包会逐文件校验 SHA-256；也兼容无 manifest 的简化包。文件在 zip 根目录或单一子目录均可。

导入时的字段映射：

| Codex 主题包 | ZCode 主题 |
|---|---|
| `image` 背景图 | `background.<ext>` 壁纸 |
| `art.focusX/focusY` | `position: "X% Y%"` 背景定位 |
| `colors.panel` 的 alpha（如 `#1e1e1e55`） | `surfaceOpacity: 0.33`（作者透明度意图） |
| `colors.*` 九个色板 token | `--color-background`、`--color-panel`、`--color-primary` 等 Tailwind v4 变量 |
| `theme.css`（选择器面向 Codex DOM） | 存为 `codex-extra.css` 备查，不注入 |
| `manifest.json` 许可证/作者 | 写入 `theme.json` 的 `imported` 字段 |

## 工作原理（全部经过实测验证）

ZCode 桌面版是 **Electron** 应用（MonkeyCode 是 Tauri/WebView2，启动方式不同）：

1. Electron 原生支持 Chromium 命令行开关，启动器直接以
   `ZCode.exe --remote-debugging-port=9223` 拉起（会话级，仅作用于该次启动的实例），
   零修改打开 CDP 调试端口
2. 注入器通过 `http://127.0.0.1:9223/json` 枚举页面目标（主窗口为
   `file://.../app.asar/out/renderer/index.html`，另有内嵌页与 worker，worker 自动跳过），
   经 WebSocket 附加后执行注入脚本，并用 `Page.addScriptToEvaluateOnNewDocument`
   注册持久化注入
3. ZCode 前端是 React + Tailwind v4，主题切换 = `html` 上的 `theme-zai-dark` /
   `theme-zai-light` 类，全部界面颜色引用 `--color-background`、`--color-panel`、
   `--color-sidebar`、`--color-background-win-alt` 等语义变量。ZCode **没有**
   MonkeyCode 的内置壁纸层（data-mc-background 机制不存在），所以注入脚本：
   - 把壁纸以 `background-image` 直接画在 `#root` 上（普通声明 + `!important`，
     不经过自定义属性，规避 Chromium 对 CSS 变量值 2^21 字符的静默上限）
   - 用 `color-mix(in srgb, <底色> 50%, transparent) !important` 把上述表面变量改成
     半透明，壁纸即从面板后透出（浅色/深色各自变体分别适配，文字可读性不受影响）
   - 主题包若声明了调色板（导入器生成或手写），按包的 `appearance` 字段落到对应
     变体：dark 包重配深色模式，浅色模式保留 ZCode 原生配色半透明化

## 应用时自动调教（reference tuning）

与 MonkeyCodeSkin 相同的“壁纸为主角”参考配方，应用任何主题（内置 / 导入 / 图库下载）时
注入器在运行时统一处理，**主题包文件本身不做任何修改**：

- 面板不透明度强制 50%（color-mix 混入 50% 透明），壁纸透过面板清晰可见
- 壁纸 fit=cover；背景定位使用主题包自己的 position
- 壁纸上叠加主题底色 25% 压暗渐变
- 参数可在 skin-lib.ps1 的 `$script:ZC_TUNING` 中调整

## 关键坑（调试记录）

- CDP 的 `Page.addScriptToEvaluateOnNewDocument` 注册在注入端 WebSocket 断开后即失效：
  页面刷新后皮肤会丢失。监控循环每 5 秒校验 `window.__ZC_SKIN` 标记，缺失即自动补注
  （独立注入器按目标 id 判断，刷新产生新 id，天然重注）
- ZCode 带单实例锁（requestSingleInstanceLock）：换肤启动前必须完全退出已运行实例，
  否则新进程会把参数移交给旧实例后退出、调试端口开不出来
- ZCode 支持环境变量 `ZCODE_DESKTOP_USER_DATA_DIR` 自定义数据目录（锁随目录走），
  可用不同目录并行启动第二个实例做开发测试，不影响正常使用的实例
- Chromium 对 CSS 自定义属性值有 2^21（2,097,152）字符上限：大壁纸（PNG 常超 2MB）的
  data-URI 一旦放进 `var(...)` 会被解析器静默丢弃——壁纸因此用普通
  `background-image:url(...)` 声明直接绘制
- ps2exe `-noConsole` 封装的 exe 里 `Write-Output` 会永久阻塞（无控制台可写）：
  自检结果只写 `logs\selftest.txt`，不向 stdout 输出
- 含中文的 .ps1 必须带 UTF-8 BOM，否则 PowerShell 5.1 按 ANSI 读取，中文字符串乱码
  甚至吞掉引号造成语法错误

## 安全说明

- 不修改官方二进制与签名，应用更新后重新执行 skin-start 即可
- 调试端口绑定 127.0.0.1 但**无鉴权**，同机其他进程可连接；不用皮肤时执行
  skin-clear 或正常重启即可关闭端口
- 注入内容仅为 CSS 与设置属性的 JS，不涉及网络与数据读取

## 主题包格式

```
themes/<name>/
├─ theme.json     必需：id / version / appearance(light|dark) / surfaceOpacity(0~1) / fit(cover|contain) / position
├─ theme.css      可选：附加 CSS（注入为 #zc-skin-style，用 ZCode 的 Tailwind 变量名）
└─ background.jpg 支持 .jpg/.jpeg/.png/.webp，以 data-URI 内嵌注入
```

## 已知限制与路线图

- [x] MVP：启动器 + 注入器 + 示例主题
- [x] Codex Dream Skin 主题包导入（manifest 校验 + token 映射 + imports\ 自动导入）
- [x] ZCodeSkin.exe：托盘常驻 + UI + 图库在线安装 + 一键切换
- [x] 启动时检查 GitHub Release 更新并提示（托盘气泡，点击打开下载页；
      仓库发布 Release 后自动生效）
- [ ] 壁纸模糊（blurPx）暂未实现：ZCode 无独立壁纸层，filter 模糊 #root 会连 UI 一起糊
- [ ] 外观不匹配的主题包（如 dark 包 + 浅色模式）只应用壁纸，调色板保留 ZCode 原生
- [ ] Safe CSS 白名单 + 选择器 doctor（对抗应用更新导致的 DOM 漂移）
