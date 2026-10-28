// Verge Glass theme, compiled into the binary so the glass look works no matter how
// the app was started (desktop shortcut, autostart, CLI) and without a CDP daemon.
// The files are generated from the Verge Glass plugin repo; see docs/FORK.md.
const VG_CSS: &str = include_str!("../../../assets/verge-glass/verge-glass.css");
const VG_JS: &str = include_str!("../../../assets/verge-glass/verge-glass.js");

/// Build stamp of this third-party fork, shown on the theme card so users (and bug
/// reports) can tell which build is running. Set at compile time, e.g.
/// `VERGE_GLASS_BUILD_AT="2026-10-29 03:20"`.
const VG_BUILD_AT: &str = match option_env!("VERGE_GLASS_BUILD_AT") {
    Some(value) => value,
    None => "未标注",
};

pub fn build_window_initial_script(
    initial_theme_mode: &str,
    dark_background: &str,
    light_background: &str,
    app_version: &str,
) -> String {
    let theme_mode = match initial_theme_mode {
        "dark" => "dark",
        "light" => "light",
        _ => "system",
    };
    let css_literal = serde_json::to_string(VG_CSS).unwrap_or_else(|_| "\"\"".to_string());
    let js_literal = serde_json::to_string(VG_JS).unwrap_or_else(|_| "\"\"".to_string());
    let build_literal = serde_json::to_string(VG_BUILD_AT).unwrap_or_else(|_| "\"\"".to_string());
    format!(
        r#"
    // Marks a build whose window owns a real alpha channel, so in-page clients
    // (Verge Glass) can drive transparency with CSS instead of window alpha.
    window.__VERGE_GLASS_HOST__ = {{ transparent: true }};
    window.__VG_HOST__ = {{
        version: "{app_version}",
        appVersion: "{app_version}",
        build: {build},
        css: {css}
    }};
    window.__VERGE_INITIAL_THEME_MODE = "{theme_mode}";
    window.__VERGE_INITIAL_THEME_COLORS = {{
        darkBg: "{dark_background}",
        lightBg: "{light_background}",
    }};
{script}
    // Boot the bundled theme once the page scripts are available.
    try {{
        (0, eval)({js});
    }} catch (error) {{
        console.warn('[VergeGlass] theme bootstrap failed', error);
    }}
"#,
        theme_mode = theme_mode,
        dark_background = dark_background,
        light_background = light_background,
        app_version = app_version,
        build = build_literal,
        css = css_literal,
        js = js_literal,
        script = WINDOW_INITIAL_SCRIPT,
    )
}

pub const WINDOW_INITIAL_SCRIPT: &str = r##"
    console.log('[Tauri] 窗口初始化脚本开始执行');

    const initialColors = (() => {
        try {
            const colors = window.__VERGE_INITIAL_THEME_COLORS;
            if (colors && typeof colors === "object") {
                const { darkBg, lightBg } = colors;
                if (typeof darkBg === "string" && typeof lightBg === "string") {
                    return { darkBg, lightBg };
                }
            }
        } catch (error) {
            console.warn("[Tauri] 读取初始主题颜色失败:", error);
        }
        return { darkBg: "#2E303D", lightBg: "#F5F5F5" };
    })();

    const prefersDark = (() => {
        try {
            return !!window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)")?.matches;
        } catch (error) {
            console.warn("[Tauri] 读取系统主题失败:", error);
            return false;
        }
    })();

    const initialThemeMode = typeof window.__VERGE_INITIAL_THEME_MODE === "string"
        ? window.__VERGE_INITIAL_THEME_MODE
        : "system";

    let initialTheme = prefersDark ? "dark" : "light";
    if (initialThemeMode === "dark") {
        initialTheme = "dark";
    } else if (initialThemeMode === "light") {
        initialTheme = "light";
    }

    const applyInitialTheme = (theme) => {
        const isDark = theme === "dark";
        const root = document.documentElement;
        const bgColor = isDark ? initialColors.darkBg : initialColors.lightBg;
        const textColor = isDark ? "#ffffff" : "#333";
        if (root) {
            root.dataset.theme = theme;
            root.style.setProperty("--bg-color", bgColor);
            root.style.setProperty("--text-color", textColor);
            root.style.colorScheme = isDark ? "dark" : "light";
            root.style.color = textColor;
        }
        const paintBody = () => {
            if (!document.body) return;
            document.body.style.color = textColor;
        };
        if (document.readyState === "loading") {
            document.addEventListener("DOMContentLoaded", paintBody, { once: true });
        } else {
            paintBody();
        }
        try {
            localStorage.setItem("verge-theme-mode-cache", theme);
        } catch (error) {
            console.warn("[Tauri] 缓存主题模式失败:", error);
        }
        return isDark;
    };

    applyInitialTheme(initialTheme);

    console.log('[Tauri] 窗口初始化脚本执行完成');
"##;
