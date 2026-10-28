use tauri::utils::config::Color;
use tauri::webview::PageLoadEvent;
use tauri::{Theme, WebviewWindow};

use crate::{config::Config, core::handle, utils::resolve::window_script::build_window_initial_script};
#[cfg(target_os = "macos")]
use clash_verge_logging::logging;
use clash_verge_logging::{Type, logging_error};

// The WebView2 controller must keep an alpha channel: the page decides how much
// of the desktop shows through, and an opaque controller background would paint
// over whatever the CSS leaves transparent.
const TRANSPARENT_BACKGROUND_COLOR: Color = Color(0, 0, 0, 0);
const DARK_BACKGROUND_HEX: &str = "#2E303D";
const LIGHT_BACKGROUND_HEX: &str = "#F5F5F5";

const DEFAULT_WIDTH: f64 = 940.0;
const DEFAULT_HEIGHT: f64 = 700.0;

const MINIMAL_WIDTH: f64 = 520.0;
const MINIMAL_HEIGHT: f64 = 520.0;

// DWM paints the native non-client frame opaque, which would leave a solid title
// bar on top of a transparent client area. Windows builds therefore use the
// frameless mode the frontend already implements for Linux.
#[cfg(any(target_os = "linux", target_os = "windows"))]
const DEFAULT_DECORATIONS: bool = false;
#[cfg(not(any(target_os = "linux", target_os = "windows")))]
const DEFAULT_DECORATIONS: bool = true;

/// CSS radius of the glass window, mirrored by the native window region.
pub const WINDOW_RADIUS_CSS: f64 = 26.0;

/// Drops the native caption and sizing border from the HWND, keeps the window
/// clipped to a rounded region, and watches both invariants.
///
/// `decorations(false)` hides the frame through `WM_NCCALCSIZE`, but any
/// `SetWindowRgn` call makes Windows recompute the non-client area and draw the
/// caption again (a grey title bar over the glass). Windows also re-composites a
/// stale pre-strip frame when windows overlap, so the guard below re-asserts the
/// invariants periodically instead of trusting a single startup repair.
#[cfg(target_os = "windows")]
#[allow(dead_code)]
mod shell {
    use std::ffi::c_void;
    use std::time::Duration;

    use tauri::WebviewWindow;

    #[repr(C)]
    pub struct WinRect {
        left: i32,
        top: i32,
        right: i32,
        bottom: i32,
    }

    #[repr(C)]
    struct WinPoint {
        x: i32,
        y: i32,
    }

    #[link(name = "user32")]
    unsafe extern "system" {
        fn GetWindowLongW(hwnd: *mut c_void, index: i32) -> i32;
        fn SetWindowLongW(hwnd: *mut c_void, index: i32, value: i32) -> i32;
        fn SetWindowPos(hwnd: *mut c_void, after: *mut c_void, x: i32, y: i32, cx: i32, cy: i32, flags: u32) -> i32;
        fn RedrawWindow(hwnd: *mut c_void, rect: *const c_void, rgn: *mut c_void, flags: u32) -> i32;
        fn GetWindowRect(hwnd: *mut c_void, rect: *mut WinRect) -> i32;
        fn GetClientRect(hwnd: *mut c_void, rect: *mut WinRect) -> i32;
        fn ClientToScreen(hwnd: *mut c_void, point: *mut WinPoint) -> i32;
        fn SetWindowRgn(hwnd: *mut c_void, rgn: *mut c_void, redraw: i32) -> i32;
        fn GetWindowRgn(hwnd: *mut c_void, rgn: *mut c_void) -> i32;
        fn IsWindowVisible(hwnd: *mut c_void) -> i32;
    }

    #[link(name = "gdi32")]
    unsafe extern "system" {
        fn CreateRoundRectRgn(x1: i32, y1: i32, x2: i32, y2: i32, w: i32, h: i32) -> *mut c_void;
        fn CreateRectRgn(x1: i32, y1: i32, x2: i32, y2: i32) -> *mut c_void;
        fn DeleteObject(obj: *mut c_void) -> i32;
        fn GetRgnBox(rgn: *mut c_void, rect: *mut WinRect) -> i32;
    }

    #[link(name = "dwmapi")]
    unsafe extern "system" {
        fn DwmFlush() -> i32;
        fn DwmSetWindowAttribute(hwnd: *mut c_void, attr: u32, value: *const c_void, size: u32) -> i32;
    }

    // Windows 11 DWM attributes that keep the system from decorating our window.
    const DWMWA_WINDOW_CORNER_PREFERENCE: u32 = 33;
    const DWMWA_BORDER_COLOR: u32 = 34;
    const DWMWCP_DONOTROUND: i32 = 1;
    const DWMWA_COLOR_NONE: u32 = 0xFFFF_FFFE;

    // Windows 10+ : "the DWM does not render the non-client area at all".
    // Without it Windows paints the ~12px invisible sizing border with the window
    // class brush (opaque white) whenever the region is (re)applied or the window is
    // shown again from the tray, which is the "white frame" users see; it also keeps
    // a stale pre-strip frame that a resize alone used to clear.
    const DWMWA_NCRENDERING_POLICY: u32 = 2;
    const DWMNCRP_DISABLED: i32 = 1;

    /// Windows draws a 1px system border and its own corner rounding on top of the
    /// page; turn both off so the page's rounded, anti-aliased edge is the only one.
    /// Also disables non-client rendering so the window never paints its sizing
    /// border, which is what the white frame around the glass actually is.
    fn quiet_dwm(hwnd: *mut c_void) {
        let corner: i32 = DWMWCP_DONOTROUND;
        let border: u32 = DWMWA_COLOR_NONE;
        let nc_rendering: i32 = DWMNCRP_DISABLED;
        unsafe {
            let _ = DwmSetWindowAttribute(
                hwnd,
                DWMWA_WINDOW_CORNER_PREFERENCE,
                &corner as *const i32 as *const c_void,
                std::mem::size_of::<i32>() as u32,
            );
            let _ = DwmSetWindowAttribute(
                hwnd,
                DWMWA_BORDER_COLOR,
                &border as *const u32 as *const c_void,
                std::mem::size_of::<u32>() as u32,
            );
            let _ = DwmSetWindowAttribute(
                hwnd,
                DWMWA_NCRENDERING_POLICY,
                &nc_rendering as *const i32 as *const c_void,
                std::mem::size_of::<i32>() as u32,
            );
        }
    }

    const GWL_STYLE: i32 = -16;
    const WS_CAPTION: i32 = 0x00C0_0000;
    const WS_THICKFRAME: i32 = 0x0004_0000;
    const WS_SYSMENU: i32 = 0x0008_0000;
    const SWP_NOSIZE: u32 = 0x0001;
    const SWP_NOMOVE: u32 = 0x0002;
    const SWP_NOZORDER: u32 = 0x0004;
    const SWP_NOACTIVATE: u32 = 0x0010;
    const SWP_FRAMECHANGED: u32 = 0x0020;
    const RDW_INVALIDATE: u32 = 0x0001;
    const RDW_ERASE: u32 = 0x0004;
    const RDW_FRAME: u32 = 0x0400;
    const RDW_ALLCHILDREN: u32 = 0x0080;
    const RDW_UPDATENOW: u32 = 0x0100;

    fn zero_rect() -> WinRect {
        WinRect {
            left: 0,
            top: 0,
            right: 0,
            bottom: 0,
        }
    }

    /// Removes caption / sizing border. Returns `true` when the style changed.
    pub fn strip(window: &WebviewWindow) -> bool {
        let Ok(hwnd) = window.hwnd() else {
            return false;
        };
        unsafe {
            let style = GetWindowLongW(hwnd.0, GWL_STYLE);
            let unwanted = WS_CAPTION | WS_THICKFRAME | WS_SYSMENU;
            quiet_dwm(hwnd.0);
            if style & unwanted == 0 {
                return false;
            }
            SetWindowLongW(hwnd.0, GWL_STYLE, style & !unwanted);
            let _ = SetWindowPos(
                hwnd.0,
                std::ptr::null_mut(),
                0,
                0,
                0,
                0,
                SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED,
            );
            // DWM can keep composing the pre-strip snapshot (a ghost caption band)
            // until the window, frame included, is invalidated and flushed.
            let _ = RedrawWindow(
                hwnd.0,
                std::ptr::null(),
                std::ptr::null_mut(),
                RDW_INVALIDATE | RDW_ERASE | RDW_FRAME | RDW_ALLCHILDREN | RDW_UPDATENOW,
            );
            let _ = DwmFlush();
            true
        }
    }

    /// True when the current region is at least as large as the client area, i.e.
    /// it can never cut into the anti-aliased corners painted by the page.
    pub fn region_ok(window: &WebviewWindow) -> bool {
        let Ok(hwnd) = window.hwnd() else {
            return false;
        };
        unsafe {
            let mut client = zero_rect();
            let mut window_rect = zero_rect();
            let mut origin = WinPoint { x: 0, y: 0 };
            if GetClientRect(hwnd.0, &mut client) == 0
                || GetWindowRect(hwnd.0, &mut window_rect) == 0
                || ClientToScreen(hwnd.0, &mut origin) == 0
            {
                return false;
            }
            let rgn = CreateRectRgn(0, 0, 0, 0);
            if rgn.is_null() {
                return false;
            }
            let kind = GetWindowRgn(hwnd.0, rgn);
            let mut bounds = zero_rect();
            // The region has to match the client area exactly: a stale *larger* region
            // (e.g. left over from a taller window) passes a size-only check and leaves
            // the non-client ring visible again, which is exactly the white edge bug.
            // Exact equality, no tolerance: one pixel of slack on the right/bottom edge
            // is already a non-client pixel that gets painted white.
            let expected_left = origin.x - window_rect.left;
            let expected_top = origin.y - window_rect.top;
            let ok = kind != 0
                && GetRgnBox(rgn, &mut bounds) != 0
                && bounds.left == expected_left
                && bounds.top == expected_top
                && bounds.right == expected_left + client.right
                && bounds.bottom == expected_top + client.bottom;
            let _ = DeleteObject(rgn);
            ok
        }
    }

    /// Clips the HWND to the client area. The region is deliberately a plain rectangle:
    /// a rounded GDI region is a 1-bit mask and would saw the page's anti-aliased corner,
    /// so the visible rounding is left entirely to CSS (`--vg-window-radius`).
    pub fn apply_region(window: &WebviewWindow, _radius_css: f64) {
        let Ok(hwnd) = window.hwnd() else {
            return;
        };
        unsafe {
            let mut window_rect = zero_rect();
            let mut client_rect = zero_rect();
            let mut client_origin = WinPoint { x: 0, y: 0 };
            if GetWindowRect(hwnd.0, &mut window_rect) == 0
                || GetClientRect(hwnd.0, &mut client_rect) == 0
                || ClientToScreen(hwnd.0, &mut client_origin) == 0
            {
                return;
            }

            let offset_x = client_origin.x - window_rect.left;
            let offset_y = client_origin.y - window_rect.top;
            let width = client_rect.right - client_rect.left;
            let height = client_rect.bottom - client_rect.top;
            if width <= 0 || height <= 0 {
                return;
            }

            // No padding at all: the region covers exactly the client area, so no
            // non-client pixel is inside it. One pixel of slack used to be added to
            // "cover rounding", but that extra pixel is a non-client pixel and the
            // window class brush paints it white — a 1px bright line along the right
            // and bottom edge of the glass.
            let win_w = window_rect.right - window_rect.left;
            let win_h = window_rect.bottom - window_rect.top;
            let left = offset_x.max(0);
            let top = offset_y.max(0);
            let right = (offset_x + width).min(win_w);
            let bottom = (offset_y + height).min(win_h);

            // Rectangular clip on the client area: the window class brush paints the
            // non-client ring white, which shows up as a 1-8px bright line around the
            // transparent glass. Clipping to the client removes it; the rounded shape
            // itself comes from CSS (a rounded GDI region would alias the corners and
            // leave stale pixels when the window is occluded).
            let rgn = CreateRectRgn(left, top, right, bottom);
            if rgn.is_null() {
                return;
            }
            if SetWindowRgn(hwnd.0, rgn, 1) == 0 {
                let _ = DeleteObject(rgn);
            }
        }
        // A region change only rescales the clip; DWM keeps the old (white) non-client
        // pixels until the frame is invalidated. That is why the white edge disappeared
        // on some resizes and came back on others.
        recompose(window);
    }

    /// Forces DWM to rebuild the window composition.
    ///
    /// After the caption is stripped, DWM can keep a pre-strip snapshot and paint it
    /// again whenever the window is focused or revealed from behind another window
    /// (the grey "Clash Verge" band). Invalidating the whole frame and flushing the
    /// composition drops that snapshot.
    pub fn recompose(window: &WebviewWindow) {
        let Ok(hwnd) = window.hwnd() else {
            return;
        };
        unsafe {
            let _ = RedrawWindow(
                hwnd.0,
                std::ptr::null(),
                std::ptr::null_mut(),
                RDW_INVALIDATE | RDW_ERASE | RDW_FRAME | RDW_ALLCHILDREN | RDW_UPDATENOW,
            );
            let _ = DwmFlush();
        }
    }

    /// Re-applies the shell a few times shortly after a system-driven repaint.
    ///
    /// Showing the window, restoring it from the taskbar and switching the app theme all
    /// make Windows (re)paint the white non-client ring. A single synchronous redraw is
    /// not enough, because that redraw schedules another frame; a short ladder of
    /// redraws covers the tail end of the transition.
    pub fn refresh(window: &WebviewWindow, radius_css: f64) {
        let window = window.clone();
        std::thread::spawn(move || {
            let mut waited = 0_u64;
            for target in [120_u64, 400, 900] {
                std::thread::sleep(std::time::Duration::from_millis(target - waited));
                waited = target;
                ensure(&window, radius_css);
                recompose(&window);
            }
        });
    }

    /// Re-asserts the shell: stripped frame + a region clipped to the client area.
    pub fn ensure(window: &WebviewWindow, radius_css: f64) {
        if strip(window) {
            recompose(window);
        }
        if !region_ok(window) {
            apply_region(window, radius_css);
        }
    }

    /// Keeps the shell repaired while the app runs: Windows re-adds the frame on
    /// some transitions (overlap, unminimize, monitor move) and the region goes
    /// stale after DPI changes, both of which used to need a manual restart.
    ///
    /// The tray round-trip (close → hide, click the tray icon → show) is the path
    /// users hit most often: Windows repaints the non-client ring while the window is
    /// hidden and DWM may composite the pre-strip frame again, so a hidden → visible
    /// edge triggers the full `refresh()` ladder instead of waiting for a resize.
    pub fn start_guard(window: WebviewWindow, radius_css: f64) {
        std::thread::spawn(move || {
            let mut was_visible = false;
            loop {
                std::thread::sleep(Duration::from_millis(1500));
                let Ok(hwnd) = window.hwnd() else {
                    return;
                };
                let visible = unsafe { IsWindowVisible(hwnd.0) != 0 };
                if visible && !was_visible {
                    refresh(&window, radius_css);
                }
                was_visible = visible;
                ensure(&window, radius_css);
            }
        });
    }
}

#[cfg(target_os = "windows")]
pub fn ensure_window_shell(window: &WebviewWindow, radius_css: f64) {
    shell::ensure(window, radius_css);
}

#[cfg(target_os = "windows")]
pub fn start_window_guard(window: WebviewWindow, radius_css: f64) {
    shell::start_guard(window, radius_css);
}

#[cfg(target_os = "windows")]
pub fn recompose_window(window: &WebviewWindow) {
    shell::recompose(window);
}

#[cfg(target_os = "windows")]
pub fn refresh_window_shell(window: &WebviewWindow) {
    shell::refresh(window, WINDOW_RADIUS_CSS);
}

#[cfg(not(target_os = "windows"))]
pub fn refresh_window_shell(_window: &WebviewWindow) {}

const fn restored_window_size_is_too_small(width: u32, height: u32) -> bool {
    width < MINIMAL_WIDTH as u32 || height < MINIMAL_HEIGHT as u32
}

fn restore_default_size_if_needed(window: &WebviewWindow) {
    let Ok(size) = window.outer_size() else {
        return;
    };

    if !restored_window_size_is_too_small(size.width, size.height) {
        return;
    }

    logging_error!(
        Type::Window,
        window.set_size(tauri::LogicalSize::new(DEFAULT_WIDTH, DEFAULT_HEIGHT))
    );
    logging_error!(Type::Window, window.center());
}

pub async fn build_new_window() -> Result<WebviewWindow, String> {
    let app_handle = handle::Handle::app_handle();

    let config = Config::verge().await;
    let latest = config.latest_arc();
    let start_page = latest.start_page.as_deref().unwrap_or("/");
    let initial_theme_mode = match latest.theme_mode.as_deref() {
        Some("dark") => "dark",
        Some("light") => "light",
        _ => "system",
    };

    let resolved_theme = match initial_theme_mode {
        "dark" => Some(Theme::Dark),
        "light" => Some(Theme::Light),
        _ => None,
    };

    let initial_script = build_window_initial_script(
        initial_theme_mode,
        DARK_BACKGROUND_HEX,
        LIGHT_BACKGROUND_HEX,
        env!("CARGO_PKG_VERSION"),
    );

    let mut builder = tauri::WebviewWindowBuilder::new(
        app_handle,
        "main", /* the unique window label */
        tauri::WebviewUrl::App(start_page.into()),
    )
    .title("Clash Verge")
    .center()
    .decorations(DEFAULT_DECORATIONS)
    .transparent(true)
    .fullscreen(false)
    .inner_size(DEFAULT_WIDTH, DEFAULT_HEIGHT)
    .min_inner_size(MINIMAL_WIDTH, MINIMAL_HEIGHT)
    .visible(false) // 等待主题色准备好后再展示，避免启动色差
    .initialization_script(&initial_script)
    .general_autofill_enabled(false) // 禁用自动填充
    .on_page_load(move |window, payload| {
        if payload.event() != PageLoadEvent::Finished {
            return;
        }

        logging_error!(Type::Window, window.show());
        logging_error!(Type::Window, window.set_focus());
        // First paint also triggers a system repaint of the frame: re-apply the shell.
        refresh_window_shell(&window);
    });

    if let Some(theme) = resolved_theme {
        builder = builder.theme(Some(theme));
    }

    builder = builder.background_color(TRANSPARENT_BACKGROUND_COLOR);

    match builder.build() {
        Ok(window) => {
            logging_error!(
                Type::Window,
                window.set_background_color(Some(TRANSPARENT_BACKGROUND_COLOR))
            );
            #[cfg(target_os = "windows")]
            {
                ensure_window_shell(&window, WINDOW_RADIUS_CSS);
                start_window_guard(window.clone(), WINDOW_RADIUS_CSS);
                refresh_window_shell(&window);
            }
            restore_default_size_if_needed(&window);
            // A new page supersedes any reload marker left by the old window.
            #[cfg(target_os = "macos")]
            take_webview_needs_reload();
            Ok(window)
        }
        Err(e) => Err(e.to_string()),
    }
}

/// Defers recovery of a terminated hidden main webview until its next activation.
#[cfg(target_os = "macos")]
static WEBVIEW_NEEDS_RELOAD: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);

#[cfg(target_os = "macos")]
pub fn take_webview_needs_reload() -> bool {
    WEBVIEW_NEEDS_RELOAD.swap(false, std::sync::atomic::Ordering::SeqCst)
}

///
/// macOS may kill hidden WebContent under memory pressure. Clean orphaned Mihomo subscriptions,
/// reload visible webviews immediately, and defer a hidden main-window reload until activation.
/// Registering this callback replaces Tauri's default automatic reload.
#[cfg(target_os = "macos")]
pub fn on_web_content_process_terminated(webview: &tauri::Webview) {
    if handle::Handle::global().is_exiting() {
        return;
    }

    logging!(
        warn,
        Type::Window,
        "WebView 渲染进程已被系统终止（label={}），开始恢复",
        webview.label()
    );

    let window = webview.window();
    let is_user_visible = window.is_visible().unwrap_or(false) && !window.is_minimized().unwrap_or(false);

    // Only the main window has a path that consumes the deferred marker.
    let is_main_window = webview.label() == "main";
    let reload_now = is_user_visible || !is_main_window;

    if !reload_now {
        WEBVIEW_NEEDS_RELOAD.store(true, std::sync::atomic::Ordering::SeqCst);
        logging!(info, Type::Window, "窗口不可见，页面将在下次打开窗口时重载");
    }

    // Clean before reload so cleanup cannot remove subscriptions created by the new page.
    let webview = webview.clone();
    crate::process::AsyncHandler::spawn(move || async move {
        if let Err(err) = handle::Handle::mihomo().clear_all_ws_connections() {
            logging!(warn, Type::Window, "清理 Mihomo WebSocket 连接失败: {err}");
        } else {
            logging!(info, Type::Window, "已清理全部 Mihomo WebSocket 连接");
        }
        if reload_now {
            logging_error!(Type::Window, webview.reload());
        }
    });
}

/// Consumes the shared marker for native unminimize paths that bypass `activate_window`.
#[cfg(target_os = "macos")]
pub fn reload_main_window_if_needed() {
    if !take_webview_needs_reload() {
        return;
    }
    let Some(window) = crate::utils::window_manager::WindowManager::get_main_window() else {
        return;
    };
    logging!(info, Type::Window, "渲染进程曾被系统终止，窗口聚焦后重载页面");
    if let Err(e) = window.reload() {
        logging!(warn, Type::Window, "重载页面失败: {e}");
    }
}
