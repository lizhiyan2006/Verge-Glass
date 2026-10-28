# 宿主分支改动（fork patch）

这些文件来自 **Clash Verge Rev 2.5.9** 的本地分支，是把「原生透明窗口 + 内置 glass 主题」
做出来所需的**全部**改动。路径与上游源码一一对应，覆盖过去即可复现。

只关心主题（CSS/JS）的话，可以把这个 `fork-patch/` 目录整个删掉，主题本身在 `src/`。

| 路径 | 作用 |
| --- | --- |
| `src-tauri/src/utils/resolve/window.rs` | 原生窗口外壳：`.transparent(true)`、去 caption/sizing frame、矩形 `SetWindowRgn`、`DWMNCRP_DISABLED`、`RedrawWindow + DwmFlush` 重绘阶梯、隐藏→可见守护 |
| `src-tauri/src/utils/resolve/window_script.rs` | `include_str!` 把主题 CSS/JS 编进二进制，注入 `window.__VG_HOST__`（含编译期构建戳） |
| `src-tauri/src/lib.rs` | `Focused` / `ThemeChanged` / `Resized` 时重新断言外壳 |
| `src-tauri/tauri.conf.json` | 停用应用自更新、第三方改版版本信息、NSIS 安装包图标与语言 |
| `src/components/layout/window-controller.tsx` | 放行 Windows 的自定义缩放手柄（原本只在 Linux 渲染） |
| `src-tauri/assets/verge-glass/*` | 内置主题资源，与主题仓库的 `src/verge-glass.{css,js}` 是同一份文件 |
| `src-tauri/icons/*` | glass 紫色猫图标（ico 7 档 + png 各尺寸） |

## 复现构建

```powershell
git clone <Clash Verge Rev 2.5.9 源码>
# 把本目录的内容覆盖到源码根目录
pnpm install --frozen-lockfile
pnpm prebuild                       # 下载 verge-mihomo / geo 数据 / 服务程序
$env:CARGO_NET_OFFLINE = "true"
$env:NODE_OPTIONS = "--max-old-space-size=4096"
$env:VERGE_GLASS_BUILD_AT = "2026-10-29 03:01"   # 会显示在主题卡片副标题
pnpm tauri build
# 产物：target\release\bundle\nsis\Clash Verge_2.5.9_x64-setup.exe
```

工具链：Rust 1.99.1、Node 24.22.1、pnpm 12.15.0、VS BuildTools 17.14 + Windows SDK 10.0.26100。

> 改完 `src/verge-glass.{css,js}` 后记得同步一份到 `src-tauri/assets/verge-glass/`，
> 否则程序里跑的仍是旧主题（编译期 `include_str!`）。
