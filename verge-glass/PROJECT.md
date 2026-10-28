# Verge Glass — 项目速览

Clash Verge Rev 的半透明主题：通过 WebView2 调试端口注入 CSS + JS，在「设置」页底部生成一张控制卡；
支持登录自启、一次注入长期生效、可卸载。

**1.9.0 起分两种形态**：

| 形态 | 说明 | 能力 |
| --- | --- | --- |
| 插件形态 | 原版 App + CDP 注入，不改源码/二进制 | 「窗口透视」= 整窗 alpha 近似：文字会跟着一起变淡 |
| **分支形态** | [源码分支](./docs/FORK.md)（`transparent` + WebView2 背景 α=0） | 窗口自带 alpha：**背景透明、内容 100% 不透明，两者独立可调** |

- 目标 App：Clash Verge Rev **2.5.8**（插件形态）/ **2.5.9**（分支形态，Windows / WebView2，Tauri v2）
- 当前版本：**1.13.0**（移除「背景模糊」只留「图片模糊」；单文件安装包 VergeGlass-Setup.exe + 第三方改版标识与构建戳）
- 安装目录：`%LOCALAPPDATA%\VergeGlass`
- 仓库目录：`verge-glass\`（本文档所在处）；分支源码：`C:\Users\394\Desktop\clash-glass\clash-verge-rev-dev`

---

## 1. 目录结构

```
verge-glass\
├─ VergeGlass.ps1        引擎：install / start / apply / status / check / update / uninstall
├─ Install.cmd           一键安装（已验证）
├─ Install.ps1           安装脚本（可复制到任意目录）
├─ Uninstall.cmd         一键卸载
├─ VergeGlass-Setup.exe  自包含安装器（C#；本机被安全软件拦截，优先用 Install.cmd）
├─ plugin.json           版本 / 兼容范围 2.4.0–2.7.0
├─ src\verge-glass.css   主题样式（~27 KB，分节 1–13）
├─ src\verge-glass.js    注入脚本 + 设置卡 + 持久化
├─ assets\clash-verge.ico 主题配色图标（16–256 七档，开始菜单入口/exe 共用）
├─ docs\FORK.md          分支形态：透明窗口原理 / 改动清单 / 构建与调试
├─ tools\                开发用：cdp-eval / screen-shot / nav-*.js / fork-run / fork-sync / build-exe.ps1
└─ README.md             中文文档 + 变更记录
```

## 2. 注入链路

```
Install.cmd → 复制文件到 %LOCALAPPDATA%\VergeGlass
            → HKCU\...\Run\VergeGlass = wscript //B VergeGlass.vbs（无窗口）
            → 开始菜单快捷方式（带 assets\clash-verge.ico）
            → 关闭 App 自带开机自启（避免抢占调试端口）
            → 以 WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS=--remote-debugging-port=9333 启动 App
            → 拉起隐藏守护进程
守护进程：每秒查页面状态 {i,v,a,t}
        → 未注入 / 版本变化 → Page.addScriptToEvaluateOnNewDocument + Runtime.evaluate
        → 页面版本 ≠ 磁盘版本 → 自动 reload（热更新）
        → persist.pending 存在 → 把主题写进 theme_setting.css_injection（一次注入长期有效）
```

- 连接：`http://127.0.0.1:9333/json/list` → WebSocket → `Runtime.evaluate`
- 应用主题切换：`window.__TAURI_INTERNALS__.invoke('patch_verge_config', { payload: { theme_mode } })`
- 主题持久化：`patch_verge_config { theme_setting: { css_injection } }`（写入 `verge.yaml`，重启仍生效）
- 卸载：停守护进程 → 删 Run 键/快捷方式 → 恢复 App 自启 → 有备份则还原原 `css_injection` → 删数据目录

## 3. 功能清单（设置卡）

| 分组 | 项 | 说明 |
| --- | --- | --- |
| 外观 | 启用 | 总开关 |
| 外观 | 基调 | 跟随应用 / 深色 / 浅色 |
| 外观 | 不透明度 | 面板底色 alpha，0–100% |
| 外观 | 毛玻璃 | backdrop blur，0–48px |
| 背景 | 背景 | 全透明 / 桌面壁纸 / 自选图片 |
| 背景 | 背景可见度 / 模糊 / 遮罩 | 壁纸层透明度、模糊、暗化（**分支形态下遮罩对桌面同样生效**） |
| 窗口 | 窗口透视 | 仅插件形态：整窗透明（`WS_EX_LAYERED` + `LWA_ALPHA`），5–100% |
| 内容 | 内容不透明度 | 仅分支形态：`#root` opacity，20–100%，与背景层互不影响 |

其它：侧栏选中胶囊随点击立即移动；图表底部「数据点/压缩后/帧率/平滑」小字自动隐藏；
关闭态开关使用加深轨道 + 实心圆钮（1.8.10）。

## 4. 关键结论 / 边界

1. **纯外部注入时，窗口透明只能是整窗 alpha**。`LWA_COLORKEY` 对 WebView2 的 DirectComposition 表面无效；
   页面透明 + CDP `Emulation.setDefaultBackgroundColorOverride` 也无效（窗口背景刷不透明）。
   要「背景透明、文字不透明」必须让宿主建窗时开 `transparent` 并把 WebView2 `DefaultBackgroundColor` 置为 α=0
   —— 也就是分支形态（见 `docs/FORK.md`）；分支下页面留空处直接透出桌面，实测不依赖 `WS_EX_LAYERED`。
2. 标题栏透明靠 `DwmExtendFrameIntoClientArea(0,0,40,0)`；去掉 accent 模糊（否则窗口外沿出现光晕）。
   分支形态改为无边框 + 前端自绘标题栏，不再需要这一步。
3. `SetWindowRgn` / `DWMWA_NCRENDERING_POLICY` 会连带裁掉原生最小化/关闭按钮，禁用。
4. 应用会把 `--background-color` 写进 `<html>` 内联样式，CSS 覆盖不到；暖色底只能靠面板基色 + 遮罩。
5. 设置卡/胶囊/选项卡类名是 emotion 生成，选择器一律用属性选择器或 JS 打标（`.vg-surface` / `.vg-hide` / `.vg-ind`）。
6. PowerShell 5.1 读 UTF-8 无 BOM 的中文会串行，脚本要么纯 ASCII，要么写 BOM；
   **用 `Get-Content -Raw` 改中文文件时必须显式 `-Encoding UTF8`，否则会把文件写坏**。

## 5. 版本线

| 版本 | 要点 |
| --- | --- |
| 1.5.x | 玻璃化打磨：发丝线、圆角、图表可读性、侧栏胶囊即时动画、去掉标题栏 accent 光晕 |
| 1.6.0–1.6.1 | 一键安装器 `Install.cmd`；主题写入 `css_injection`；守护进程改为「等窗口出现」 |
| 1.6.2–1.6.8 | 浅色背景提亮、文字描边、图表小字常驻隐藏；深浅系数功能加入后被移除 |
| 1.7.0 | 主题配色图标；安装改哈希跳过 + 持久化交给守护进程；卸载还原 `css_injection` |
| 1.7.3 | 浅色薄纱 0.66 → 0.84 |
| 1.8.0–1.8.10 | 加入「护眼黑/白」（米黄+棕、sepia 暖化、降饱和）；浅色薄纱 0.90 且不再 brightness 提亮；1.8.10 增强关闭态开关 |
| 1.9.0 | **分支形态**：Clash Verge Rev 2.5.9 源码开 `transparent` + 背景 α=0；无边框自绘标题栏；`__VERGE_GLASS_HOST__` 能力标记 |
| 1.9.1 | 原生模式下保留背景遮罩；旧透视配置迁移到可读默认值；新增「内容不透明度」 |
| 1.9.2 | 原生模式把明显不可用的旧值（面板 α<15%、遮罩<15%、模糊<8px）自动抬回可读区间；分支 NSIS 安装包落地验证 |
| 1.9.3 | 顶栏恢复玻璃并跟随「不透明度」；首页提示条玻璃化（中性色阈值 g−b < 16） |
| 1.9.4 | 顶栏两行合并为一层玻璃（去掉中间横线）；窗口圆角 14px + 1px 框线；window-state 不再恢复原生标题栏；新增 probe-chrome.js 回归探针 |

## 6. 当前状态（分支形态）

```
宿主：Clash Verge Rev 2.5.9（源码分支，NSIS 安装到 C:\Program Files\Clash Verge）+ WebView2 156.0.4314.50
主题：1.11.0 起编译进二进制（`src-tauri/assets/verge-glass/`），不再需要 CDP 守护进程/独立快捷方式
plugin 1.13.0 · 主题内置（常开） · 探针 all OK
窗口：无 WS_EX_LAYERED；body 背景 rgba(0,0,0,0)；根元素 clip-path 圆角裁切
面板 α 0.62 · 背景模糊 22px · 遮罩 0.32 · 内容不透明度 1.0
基调 dark · 内容区 filter = none
```

## 7. 常用命令

```powershell
cd verge-glass
cmd /c "Install.cmd < nul"                  # 安装（约 1 秒）
powershell -File .\VergeGlass.ps1 status    # 状态
powershell -File .\VergeGlass.ps1 apply     # 对已运行窗口重新注入
powershell -File .\VergeGlass.ps1 uninstall # 卸载
cd tools
powershell -File .\cdp-eval.ps1 -ScriptFile .\nav-settings.js
powershell -File .\screen-shot.ps1 -Out shot.png
powershell -File .\cdp-eval.ps1 -ScriptFile .\probe-chrome.js   # 窗口外壳回归（顶栏/圆角）
powershell -File .\build-exe.ps1            # 重新打包 VergeGlass-Setup.exe

# 分支形态（详见 docs\FORK.md）
powershell -File .\tools\fork-sync.ps1      # 同步插件到 %LOCALAPPDATA%\VergeGlass
powershell -File .\tools\fork-run.ps1 -Wait # 停原版、启动分支调试版（CDP 9333）
cd C:\Users\394\Desktop\clash-glass\clash-verge-rev-dev
pnpm tauri build --debug --no-bundle        # 调试版 exe
pnpm tauri build                            # 发布版 + NSIS 安装包
```

## 8. 已知待办 / 可选改进

- `VergeGlass-Setup.exe` 在本机被安全软件拦截写入（`Install.cmd` 正常）。
- 订阅页切换延迟、代理组滚动时顶栏与文字干涉：曾在 1.9.x 修过，随回退撤销，可按需重新加回。
- 浅色模式「背景更白」目前靠薄纱 0.90；若仍觉得偏灰，可单调节该值。
- 分支形态：无系统阴影 / 无 Windows 11 圆角 / 无贴边吸附提示；`backdrop-filter` 模糊不到桌面。
- 分支形态：应用自动更新已停用（避免被上游覆盖），内核更新（设置 → Clash 内核）不受影响。
- 分支形态：WebView2 154+ 有 `DefaultBackgroundColor alpha=0` 失效的社区报告；本机 156 实测正常，
  换机异常时可用 `webviewInstallMode: fixedRuntime` 固定运行时版本。
