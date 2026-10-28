# Verge Glass 分支（原生透明窗口）

本仓库是 **Clash Verge Rev 2.5.9** 源码的本地分支，用来把「窗口透明度」和「内容透明度」彻底解耦：
窗口自带 alpha 通道，页面留空的地方直接就是桌面；文字、图标、面板不受整窗 alpha 影响。

上游改动只有 **3 个文件**，其余全部靠运行时注入的 Verge Glass 插件（1.9.4）驱动。

产物：

| 产物 | 路径 | 说明 |
| --- | --- | --- |
| 调试版 | `target\debug\clash-verge.exe`（84 MB） | 带符号、devtools 可用，配 `tools\fork-run.ps1` 起 CDP |
| 发布版 | `target\release\clash-verge.exe`（52 MB） | 已实测可跑 |
| 安装包 | `target\release\bundle\nsis\Clash Verge_2.5.9_x64-setup.exe`（57 MB） | NSIS perMachine；**未签名，与原版 2.5.8 一致**（原版 exe 也是 `NotSigned`） |

---

## 1. 为什么上游做不到

`WS_EX_LAYERED + LWA_ALPHA` 只能整窗等比淡化，内容 α 永远 ≤ 窗口 α。要让「背景 40% + 文字 100%」同时成立，
窗口合成表面必须带 alpha 通道，这只能由宿主（本仓库）决定：

- `wry` 在 `attributes.transparent == true` 时会把 WebView2 的 `DefaultBackgroundColor` 设成 `(0,0,0,0)`，
  否则页面再怎么透明都会被不透明画刷盖住（`src/webview2/mod.rs:127,458`）；
- `tao` 用 `DwmEnableBlurBehindWindow` + 空区域把窗口变成透明合成（`src/platform_impl/windows/window.rs:1203`）。

所以改动点就是：**建窗时打开 transparent，并把背景色 alpha 归零**。

## 2. 改动清单

| 文件 | 改动 |
| --- | --- |
| `src-tauri/src/utils/resolve/window.rs` | `.transparent(true)`；背景色 α=0；Windows 默认 `decorations(false)`；`strip_native_frame()` 去掉 `WS_CAPTION/WS_THICKFRAME`；`apply_rounded_window_region()` 用 `SetWindowRgn` 按客户区裁圆角（区域向外扩 6px，避免切到 CSS 抗锯齿） |
| `src-tauri/src/lib.rs` | 窗口状态插件不再恢复/保存 `DECORATIONS`；`Resized` / `ScaleFactorChanged` 时重算圆角区域（区域是物理像素，尺寸或 DPI 变了必须重建） |
| `src-tauri/src/utils/resolve/window_script.rs` | 初始脚本注入 `window.__VERGE_GLASS_HOST__ = { transparent: true }`，供插件识别原生透明宿主 |
| `src-tauri/tauri.conf.json` | `createUpdaterArtifacts: false`、`plugins.updater.endpoints: []`（防止上游更新把分支覆盖掉；内核更新不受影响） |

插件侧（`verge-glass` 仓库）对应 1.10.x：

- 检测 `__VERGE_GLASS_HOST__.transparent` → `data-vg-native="1"`；
- 原生模式下隐藏「窗口透视」，`windowAlpha` 恒为 1（守护进程不会再加 `WS_EX_LAYERED`）；
- 新增「内容不透明度」（`--vg-content-alpha` → `#root` 的 opacity），与背景层完全独立；
- 旧配置（透视模式下把面板/遮罩拉到 0）一次性迁移到可读默认值（α 0.62 / 模糊 22 / 遮罩 0.32）；
- 「全透明」背景不再顺手关掉遮罩——原生模式下遮罩是唯一可读性保障。

### 2.1 窗口外壳（顶栏 / 圆角）

无边框后，v1.9.4 之前顶部是**两行**：自绘标题栏（最小化/最大化/关闭）和应用自己的 `.the-bar`。
两层各画各的背景就会出现「中间一条横线 + 上下透明度不一致」。

**1.9.6 起把标题条并进页面头部**：标题条变成 58px 高、`margin-bottom: -58px` 的覆盖层（不占行），
窗口按钮浮在头部行右上角；玻璃只由页面头部绘制一次，`.the-bar` 退化成空占位：

```css
html[data-vg-native="1"] {
  --vg-chrome-bg: rgba(var(--vg-base), calc(var(--vg-alpha) * 0.8));
  --vg-chrome-blur: blur(calc(var(--vg-blur) * 0.5)) saturate(150%);
  --vg-header-h: 58px;
}

/* 标题条 = 零占位覆盖层，只负责放按钮和拖拽区 */
html[data-vg-native="1"] body .the_titlebar {
  height: var(--vg-header-h) !important;
  margin-bottom: calc(var(--vg-header-h) * -1) !important;
  background: transparent !important;
  backdrop-filter: none !important;
  pointer-events: none;               /* 不挡头部点击 */
  z-index: 6;
}
html[data-vg-native="1"] body .the_titlebar-drag-region {
  position: absolute; left: 0; top: 0;
  height: 36px; width: calc(100% - 360px);
  pointer-events: auto;               /* 只留左侧可拖拽区 */
}
html[data-vg-native="1"] body .the_titlebar button,
html[data-vg-native="1"] body .the_titlebar > div:not(.the_titlebar-drag-region) {
  pointer-events: auto;
}

/* 玻璃画在页面头部上（它的高度才是真正的顶栏高度），并给窗口按钮让位 */
html[data-vg-native="1"] body .the-content .base-page > header {
  padding-right: 140px !important;
  margin-top: -5px !important;
  padding-top: 5px !important;
  background-color: var(--vg-chrome-bg) !important;
  backdrop-filter: var(--vg-chrome-blur) !important;
  border-bottom: 1px solid var(--vg-hairline) !important;
}
html[data-vg-native="1"] body .the-bar { background: transparent !important; border: 0 !important; }

/* 圆角：遮罩层和壁纸层必须同半径，否则四角会露出方形的半透明块；
   窗口不再画边框线，四角只有裁切出来的 r 角 */
html[data-vg-native="1"] { --vg-window-radius: 26px; }
html[data-vg-native="1"] body::before,
html[data-vg-native="1"] body::after { border-radius: var(--vg-window-radius) !important; }
html[data-vg-native="1"] body .MuiPaper-root.layout {
  border-radius: var(--vg-window-radius) !important;
  border: 0 !important;
  overflow: hidden !important;
  box-shadow: none !important;
}
```

### 2.2 原生形状（去标题栏 + 圆角）

CSS 的圆角只裁页面，裁不到窗口外沿。这个无边框窗口还带 `WS_THICKFRAME` 的 12px 隐形边框，
DWM 会在矩形边上画外框线。做法是把原生 frame 摘掉，圆角完全交给页面：

```rust
// 去掉 caption / sizing frame，窗口就成了纯弹出窗口
SetWindowLongW(hwnd, GWL_STYLE, style & !(WS_CAPTION | WS_THICKFRAME | WS_SYSMENU));
SetWindowPos(hwnd, .., SWP_FRAMECHANGED | SWP_NOMOVE | SWP_NOSIZE);
RedrawWindow(hwnd, .., RDW_FRAME | RDW_ALLCHILDREN | RDW_UPDATENOW);
DwmFlush();
```

**窗口外沿那条白线**：摘掉 caption 后，窗口仍有一圈非客户区（NC），Windows 用窗口类画刷把它涂成
白色，于是透明窗口左边/上边会露出一条 1–8px 的白边（截图里那条竖线就是它）。修法是给窗口设一个
**贴着客户区的矩形 region**，把整圈 NC 裁掉：

```rust
let rgn = CreateRectRgn(client_x, client_y, client_x + w + 1, client_y + h + 1);
SetWindowRgn(hwnd, rgn, true);
```

注意这里是**矩形**而不是圆角 region：圆角 region 是 1bit 掩码，会把 CSS 的抗锯齿角切成锯齿，
而且和 DWM 透明合成配合时遮挡/重露会残留旧像素。圆角本身由页面的 `border-radius` 负责。

尺寸 / DPI 变化时在 `lib.rs` 的 `Resized`、`ScaleFactorChanged` 里重新 `ensure()`。

**外框线**：用 `outline` 而不是 `border`，因为 `border` 会占布局把内容挤偏 1px（`.layout` 是 content-box）：

```css
.layout {
  border-radius: 26px;
  outline: 1px solid var(--window-border-color, rgba(255,255,255,.12)); /* 深色 #1E1E1E / 浅色 #CCCCCC，沿用应用自己的窗口描边色 */
  outline-offset: -1px;   /* 往里收 1px，跟着圆角走 */
}
```

**DWM 幽灵帧（切换/重叠窗口时的灰标题栏）**：DWM 会保留一份「去标题栏之前」的快照，
窗口重新获得焦点、或从别的窗口后面露出来时又把旧帧合成回来。修法是：
`recompose()` = `RedrawWindow(RDW_FRAME|RDW_ALLCHILDREN|RDW_UPDATENOW)` + `DwmFlush()`，
在 `Focused` 事件里调用，并在建窗后 1.2s 补一次。`ensure()` 负责样式，`start_window_guard()`
每 1.5s 兜底一次（自动把被加回来的 caption/frame 再摘掉）。

**悬停反馈**：插件给三个按钮打上 `data-vg-label`（最小化/最大化/关闭）；
Windows 风格按钮在 `:hover` 时加半透明底、轻微放大，并浮出功能名（关闭按钮用 Windows 的红色悬停）。

回归保护（两层）：

1. `tools\probe-chrome.js`（页面侧）：无原生边框（`decorated=false`）；标题条不占行、`pointer-events: none`；
   页面头部从 y=0 承载玻璃；窗口按钮与页面操作组不重叠；三个按钮是 12px 红/黄/绿圆点且外面没有框；
   圆角 26px、遮罩/壁纸层同半径。
2. `tools\verify-window.ps1`（原生侧，页面看不到的部分）：
   `WS_CAPTION` / `WS_THICKFRAME` 必须已被移除（否则 Windows 会在玻璃上画一条灰色标题栏），
   窗口必须存在 region 且 region 完整覆盖客户区（否则圆角会被切出锯齿）。

```powershell
powershell -File tools\cdp-eval.ps1 -ScriptFile tools\probe-chrome.js
# => {"ok":true,"problems":[],"decorated":false,"controlsGap":37,...}

powershell -File tools\verify-window.ps1
# => {"ok":true,"problems":[],"caption":false,"thickframe":false,...}
```

> 这两个探针就是「不再复发」的护栏：SetWindowRgn 会让 Windows 重新计算非客户区并画出标题栏，
> 所以 `strip_native_frame()` 和 region 必须成对出现；只改其中一边，上面两个探针会有一个开始报错。

## 3. 构建（本机实测通过）

工具链：Rust 1.99.1（rustup，`rust-toolchain.toml` 固定）、Node 24.22.1、pnpm 12.15.0、
VS BuildTools 17.14（VCTools）+ Windows 11 SDK 10.0.26100。

国内网络下的实用设置（都已写入本机全局配置）：

```powershell
# ~/.cargo/config.toml
# [source.crates-io] replace-with = "rsproxy-sparse"（sparse+https://rsproxy.cn/index/）
# [net] git-fetch-with-cli = true          # libgit2 不读代理，必须用 git CLI 才能过 Clash 代理
# ~/.npmrc: registry=https://registry.npmmirror.com
# 环境变量：HTTPS_PROXY/HTTP_PROXY=http://127.0.0.1:7897，NO_PROXY=rsproxy.cn
```

```powershell
pnpm install --frozen-lockfile
pnpm prebuild                 # 下载 verge-mihomo / geo 数据 / 服务程序到 src-tauri\{sidecar,resources}
pnpm tauri build --debug --no-bundle    # 调试版：target\debug\clash-verge.exe（带符号）
pnpm tauri build                        # 发布版 + NSIS 安装包：target\release\bundle\nsis\
```

`cargo` 依赖已全量缓存，构建时建议 `CARGO_NET_OFFLINE=true`，避免 git 依赖重新联网。

## 4. 调试流程

```powershell
# 1) 把工作区的插件同步到 %LOCALAPPDATA%\VergeGlass（守护进程按 plugin.json 版本热重载）
powershell -File verge-glass\tools\fork-sync.ps1

# 2) 停掉原版实例（同一 app id 单实例），用 CDP 端口启动分支版
powershell -File verge-glass\tools\fork-run.ps1 -Profile debug -Wait

# 3) 首次注入（守护进程未运行时）或手动重推
powershell -File verge-glass\VergeGlass.ps1 apply

# 4) 探针 / 截图
powershell -File verge-glass\tools\cdp-eval.ps1 -ScriptFile probe.js
powershell -File verge-glass\tools\screen-shot.ps1 -Out shot.png
```

注意：`enable_silent_start: true`（静默启动）会让应用进入轻量模式、不建窗口也不开 CDP；
调试前在 `verge.yaml` 里关掉，或在托盘菜单里退出轻量模式。

## 5. 已验证 / 未覆盖

已验证（本机 2.5.9 + WebView2 156.0.4314.50）：

- 窗口 ex-style 无 `WS_EX_LAYERED`、无 `WS_EX_NOREDIRECTIONBITMAP`，页面 `body` 背景为 `rgba(0,0,0,0)`；
- 后方窗口（终端/桌面图标）透过面板间隙可见，文字保持 100% 不透明；
- 内容不透明度 0.6 → `#root` opacity 0.6，背景遮罩不受影响（两者独立）；
- 页面 reload 后守护进程自动重注入，版本热更新正常；
- 窗口 `decorated=false`（自绘标题栏生效），顶栏两行同色：α 0.62 → `rgba(16,18,24,0.494)`，α 0.35 → `0.28`，标题栏无中间边框；
- 窗口圆角 14px + 1px 发丝线（`overflow:hidden` 真实裁切）；
- 首页「系统代理已启用…」提示条已玻璃化（`rgba(16,18,24,0.137)`）；
- NSIS 静默安装到 `C:\Program Files\Clash Verge` 成功，`Uninstall` 注册表项版本 2.5.9，原配置与订阅保留。

未覆盖 / 已知限制：

- 无边框窗口没有系统阴影、没有 Windows 11 圆角，也没有贴边分屏的吸附布局提示；
- `backdrop-filter` 只能模糊页面内部，**模糊不到桌面**（真透明后「毛玻璃」只对层内内容生效）；
- 应用自身更新（updater）已停用，内核（mihomo）更新走「设置 → Clash 内核」，不受影响；
- WebView2 154 起有 `DefaultBackgroundColor alpha=0` 失效的社区报告（WebView2Feedback #5752），
  本机 156 实测正常；若换机器异常，可在 `tauri.windows.conf.json` 用 `webviewInstallMode: fixedRuntime` 固定版本。

## 4. 主题内置（1.11.0 起）

主题不再依赖外部 CDP 守护进程：`src-tauri/assets/verge-glass/{verge-glass.css,js}` 会被
`include_str!` 编译进二进制，建窗时通过 `initialization_script` 注入：

```rust
const VG_CSS: &str = include_str!("../../../assets/verge-glass/verge-glass.css");
const VG_JS: &str = include_str!("../../../assets/verge-glass/verge-glass.js");
// window.__VG_HOST__ = { version, appVersion, css }; (0, eval)(VG_JS);
```

好处：
- 从桌面快捷方式、开机自启、命令行启动都一样生效，不需要先跑 `VergeGlass.ps1 start`；
- 不再需要 9333 调试端口和守护进程；
- `VergeGlass.ps1 uninstall` 可以整个删掉（`%LOCALAPPDATA%\VergeGlass`、Run 键、开始菜单快捷方式），
  只保留 Clash Verge 自己的快捷方式（图标已替换为 glass 版）。

资源同步：插件仓库改动后复制到 `src-tauri/assets/verge-glass/` 再重新编译。

**窗口缩放**：Tauri 的 `WindowResizeHandles` 原本只在 Linux 渲染（`if (getSystem() !== 'linux') return null`）。
因为这里摘掉了原生 sizing frame，Windows 也必须在 `src/components/layout/window-controller.tsx` 里
放行 `windows`，否则窗口无法调整大小。
**region 必须精确等于客户区**：早先的判断只看「region ≥ 客户区」，窗口变矮/变窄后旧的大 region
会被判成合格，底部/右侧的 NC 白边就会重新露出来（表现为「缩放时白边消失、过一会又出现」）。
现在 `region_ok()` 用 `ClientToScreen` 求出客户区在窗口内的偏移，逐边比较（±1px），不匹配就重建；
并且 `apply_region()` 设完 region 立刻 `recompose()`（RedrawWindow + DwmFlush），
否则 DWM 会继续显示裁切前的白色像素。
**首启 / 最小化恢复 / 切主题时的白边**：这三条路径都会让 Windows 重新绘制非客户区，
而单次同步重绘不够——重绘本身还会再排一帧。做法是 `refresh()`：在 120ms / 400ms / 900ms
各做一次 `ensure() + recompose()`，挂在

- 建窗后（`build_new_window`）、
- `on_page_load(Finished)`（首次绘制）、
- `WindowEvent::Focused`（最小化恢复、焦点切换）、
- `WindowEvent::ThemeChanged`（深/浅色切换）。

缩放路径仍然走 `Resized → ensure()`（region 精确匹配 + 立即 recompose）。

## 6. 角部裁切与浅色半透明（1.12.0）

### 6.1 选「自选图片」时四角露出方形的一块

壁纸层为了提高背景可见度、又不想让 `filter: blur()` 的软边露白，做了 `transform: scale(1.025)`：

```css
html body::before {
  position: fixed; inset: 0;
  border-radius: 26px;              /* 自己也有圆角 */
  transform: scale(1.025);          /* ← 问题在这 */
  filter: blur(var(--vg-wall-blur));
}
```

`scale` 会把这一层整体放大，**它的圆角也被推到窗口外**：放大后元素左上角落在 `(-1.25%, -1.25%)`，
圆弧圆心移到 `(1.75px, 10.7px)`，于是窗口四角那一小块仍然是「有内容」的，只是被视口裁成方的。
没开背景图时那里是全透明的，看不出问题；一旦铺了图片，四角就是四块方形壁纸——就是「边角出框」。

修法不是在壁纸层上打补丁，而是在**根元素**上按窗口圆角裁一刀，任何绘制结果（壁纸、玻璃、遮罩、
`backdrop-filter` 的合成结果）都跑不出这个圆角：

```css
html[data-vg-native="1"] {
  --vg-window-radius: 26px;
  clip-path: inset(0 round var(--vg-window-radius));
}
```

`clip-path` 作用在元素的最终绘制结果上，位于 `filter` / `transform` 之后，所以不受这一层 scale 影响。
代价是根元素多一个屏幕空间的圆角裁切，实测无掉帧。

### 6.2 浅色模式下半透明完全失效

第 12 节还留着「不透明宿主时代」的浅色补偿：给整窗再压一层近乎不透明的白纱。

```css
html[data-vg-tone="light"] body::after {
  background: rgba(250, 251, 254, min(0.97, calc(var(--vg-veil) + 0.90))) !important;  /* α ≥ 0.90 */
}
```

那个年代窗口本身不透明，需要它把深色壁纸「提亮」；原生透明宿主下它等于给窗口糊了一张白纸，
面板 α 拉到 0% 也还是白的——所以「浅色模式半透明不起用」。现在只对非原生宿主保留：

```css
html[data-vg-tone="light"]:not([data-vg-native="1"]) body::after { /* 同上 */ }
```

原生宿主的浅色可读性交给「背景遮罩」（`--vg-veil`，默认 0.32）。

### 6.3 回归护栏

`tools\probe-chrome.js` 新增两条断言：

- `getComputedStyle(html).clipPath` 必须是 `inset(... round ...)`，否则报
  `root has no clip-path: the wallpaper layer squares off the window corners`；
- 把 `data-vg-tone` 临时切成 `light` 后读 `body::after` 的 α，> 0.55 就报
  `light tone veil is nearly opaque: no translucency in light mode`。

角部还可以直接看像素（`tools\cdp-alpha-map.ps1`：把壁纸层刷成纯色 + 打印左上角 alpha 图，
`.`=全透明 `+`=半透明 `#`=不透明）：圆角正常时左上角是一条弧，不是整块方形。

```powershell
powershell -File tools\fork-run.ps1 -Profile release -Wait        # 带 CDP 起发布版
powershell -File tools\cdp-alpha-map.ps1 -ExprFile tools\.js-lime.js -Out corner.png
powershell -File tools\push-css.ps1 -CssFile src\verge-glass.css   # 热推 CSS 做实时调参
```

## 7. 「关掉窗口再打开就出现外框」（1.12.1）

### 7.1 那是谁画的

窗口的客户区只有 1991×1326，而 `GetWindowRect` 是 2015×1338：左右各多 12px、底部多 12px。
这圈 **12px 非客户区（NC）** 是 Windows 给每个顶层窗口保留的隐形缩放边框，平时靠
`SetWindowRgn` 把它挡在区域外面。一旦区域丢了（托盘隐藏 → 再显示这条路径上最常见），
**窗口类画刷**就把这圈涂成纯白：

```
region 被移除后，右边缘逐像素（窗口内坐标）：
12..0 = 255,255,255 ……（12px 纯白）
```

实测：`SetWindowRgn(NULL)` 之后整圈 NC 立刻变白；再调用

```rust
DwmSetWindowAttribute(hwnd, DWMWA_NCRENDERING_POLICY /*2*/, &DWMNCRP_DISABLED /*1*/, 4)
```

同一个窗口、同样的状态下，NC 变成**桌面**（`204,136,135`）——DWM 不再渲染非客户区，
白框从源头消失。所以 1.12.1 把它加进 `quiet_dwm()`（每次 `ensure()` 都会跑一遍）。

### 7.2 为什么「调整大小就好了」

调整大小会重建区域 + 触发 `SWP_FRAMECHANGED`，把 NC 重新挡掉，所以白框消失；
而托盘隐藏/显示时 `Resized` 不会触发，`Focused` 又不一定来（程序化 `show()` 不保证给焦点），
于是白框一直留着。现在的兜底：

- `quiet_dwm()` 关掉 NC 渲染（白框根本没机会出现）；
- 守护线程（1.5s）监视 `IsWindowVisible`，一旦「隐藏 → 可见」，直接跑一次完整的
  `refresh()` 阶梯（120/400/900ms）。

### 7.3 剩下那条 1px 亮线

区域以前写成 `CreateRectRgn(left, top, right + 1, bottom + 1)`，那个 `+1` 不是"抗锯齿留白"，
而是**多圈进了一个 NC 像素**：GDI 区域 `(l,t,r,b)` 覆盖的是 `x ∈ [l, r-1]`，客户端像素本来
就正好落在 `[offset, offset+width-1]`。所以右/下边缘会多出一条 1px 白线：

```
区域 = client + 1 时（旧）：  …… 内容 | 255,255,255 | 桌面 桌面 …
区域 = client     时（新）：  …… 内容 | 桌面 桌面 …
```

`region_ok()` 也跟着从"±1 容差"改成**精确相等**——容差正是当年「旧的大区域蒙混过关、
白边复发」的原因。

### 7.4 「背景模糊」为什么没反应

`backdrop-filter` 只能模糊**页面内部**的内容：真透明窗口后面是桌面，桌面在页面之外，
CSS 永远模糊不到它。所以：

| 背景 | 模糊是否有用 |
| --- | --- |
| 自选图片 / 桌面壁纸（可见度 > 0） | 有：模糊面板背后的那张图 |
| 全透明，或背景可见度 0% | 没有：背后没有任何图层 |

1.12.1 起滑杆会在「全透明」时置灰，并在下面写清「想看到模糊先换成桌面壁纸/自选图片」；
背景可见度 0% 时保留滑杆但换一条提示。实测（把背景图换成棋盘格，比较模糊 0/40px 的两张截图）
差别 2.8 万个像素，说明有图层时 `backdrop-filter` 是正常工作的。

**1.13.0 起「背景模糊」整行移除**：一个「透着桌面时永远没效果」的滑杆留着只会误导。
现在卡片里只有「图片模糊」（`--vg-wall-blur`，模糊导入的那张背景图本身）；面板玻璃的
`backdrop-filter` 仍用上次保存的 `settings.blur`（默认 22px），只是不再暴露滑杆——
视觉上「其他保持不变」。

## 8. 第三方改版打包（1.13.0）

产物：**单文件安装包 `VergeGlass-Setup.exe`**（NSIS perMachine，静默安装到
`C:\Program Files\Clash Verge`，与原版/上一版同一目录、同一卸载项，可以覆盖升级）。

| 位置 | 写了什么 |
| --- | --- |
| 安装包 / 程序 exe 的版本信息 | ProductName `Clash Verge`；Publisher `Verge Glass 第三方改版（非官方）`；Copyright `GPL-3.0 · 第三方改版（非官方）：Verge Glass，基于 Clash Verge Rev 2.5.9 源码构建` |
| 安装程序图标 | `icons/icon.ico`（glass 紫色猫，7 档 16→256px），即 `VergeGlass-Setup.ico` |
| 安装界面语言 | SimpChinese + English，不弹语言选择框 |
| 主题卡片副标题 | `Clash Verge Rev 2.5.9 · Verge Glass 第三方改版（非官方）· 构建 <时间>` |

构建戳来自编译期环境变量，未设置时显示「未标注」：

```rust
const VG_BUILD_AT: &str = match option_env!("VERGE_GLASS_BUILD_AT") { Some(v) => v, None => "未标注" };
// window.__VG_HOST__ = { version, appVersion, build, css }
```

```powershell
$env:VERGE_GLASS_BUILD_AT = (Get-Date).ToString("yyyy-MM-dd HH:mm")
pnpm tauri build
Copy-Item target\release\bundle\nsis\Clash Verge_2.5.9_x64-setup.exe VergeGlass-Setup.exe
```

`productName` 故意保留 `Clash Verge`：安装目录、卸载项、`identifier`（单实例/配置目录）都不变，
否则会变成"装了两个"。改的只有发布者/描述/图标这些展示字段。


