/* ============================================================
 * Verge Glass — 半透明主题插件（in-page 运行）
 * 版本 v1.9.0
 * 运行方式：由 VergeGlass.ps1 通过 WebView2 调试协议注入
 * 依赖：window.__VG_HOST__ = { version, appVersion, css, wallpaper }
 * 可选：window.__VERGE_GLASS_HOST__ = { transparent: true }（带窗口 alpha 的分支版）
 * ============================================================ */
(function () {
  "use strict";

  var W = window;
  if (W.__VERGE_GLASS__) return;
  if (W.__VG_BOOT_SCHEDULED__) return;
  W.__VG_BOOT_SCHEDULED__ = true;

  var HOST = W.__VG_HOST__ || {};
  // Hosts patched with a real window alpha channel advertise themselves here;
  // transparency is then driven by CSS alone and window alpha stays disabled.
  var NATIVE = !!(W.__VERGE_GLASS_HOST__ && W.__VERGE_GLASS_HOST__.transparent);
  var API = W.__TAURI_INTERNALS__;
  var VERSION = HOST.version || "1.1.0";
  var APP_VERSION = HOST.appVersion || "";
  var STORE_KEY = "verge-glass:v2";

  var DEFAULT_CSS = HOST.css || W.__VG_CSS__ || "";
  var OWNER = "vg-" + Math.random().toString(36).slice(2);

  var DEFAULTS = {
    enabled: true,
    tone: "auto", // auto | dark | light
    alpha: 0.62, // 面板不透明度

    blur: 24, // 毛玻璃 px
    bg: "wallpaper", // wallpaper | custom | none
    customWall: "",
    wallOpacity: 0.85,
    wallBlur: 0,
    veil: 0.28, // 背景遮罩强度
    pierce: false, // 窗口透视（层叠窗口 alpha）
    pierceAlpha: 0.88, // 窗口不透明度
    contentAlpha: 1, // 内容不透明度（文字/图标/面板），与背景独立
    nativeMigrated: false, // 原生透明宿主的一次性迁移标记
    prevBg: "wallpaper"
  };

  /* ---------------- 设置 ---------------- */
  var settings = loadSettings();
  // 主题常开：不提供关闭入口，旧配置里的 enabled=false 一律忽略
  settings.enabled = true;

  // 原生透明宿主：背景默认不铺图（直接透出桌面），整窗 alpha 停用；
  // 旧版本在「窗口透视」下常把面板/遮罩拉到 0，这里把明显不可用的值抬回可读区间。
  if (NATIVE) {
    if (!settings.nativeMigrated) {
      settings.bg = "none";
      settings.pierce = false;
      settings.nativeMigrated = true;
      saveSettings();
    }
    var tuned = false;
    if (settings.alpha < 0.15) { settings.alpha = 0.62; tuned = true; }
    if (settings.veil < 0.15) { settings.veil = 0.32; tuned = true; }
    if (tuned) saveSettings();
  }

  function loadSettings() {
    var s = {};
    for (var k in DEFAULTS) s[k] = DEFAULTS[k];
    try {
      var raw = localStorage.getItem(STORE_KEY);
      if (raw) {
        var parsed = JSON.parse(raw);
        for (var k2 in parsed) if (k2 in s) s[k2] = parsed[k2];
        if (s.tone === "warmDark") s.tone = "dark";
        if (s.tone === "warmLight") s.tone = "light";
      }
    } catch (e) {
      /* ignore */
    }
    return s;
  }

  function saveSettings() {
    try {
      localStorage.setItem(STORE_KEY, JSON.stringify(settings));
    } catch (e) {
      toast("保存失败：localStorage 空间不足（图片太大？）");
    }
  }

  /* ---------------- 主题应用 ---------------- */
  var styleEl = null;

  function appTone() {
    var v = (document.documentElement.style.getPropertyValue("--background-color") || "").trim();
    if (!v) v = getComputedStyle(document.documentElement).getPropertyValue("--background-color").trim();
    if (v) {
      var hex = /^#([0-9a-f]{6})$/i.exec(v);
      if (hex) {
        var n = parseInt(hex[1], 16);
        var lum = (0.2126 * (n >> 16) + 0.7152 * ((n >> 8) & 255) + 0.0722 * (n & 255)) / 255;
        return lum > 0.5 ? "light" : "dark";
      }
      var rgb = /rgba?\((\d+)[,\s]+(\d+)[,\s]+(\d+)/.exec(v);
      if (rgb) {
        var l2 = (0.2126 * +rgb[1] + 0.7152 * +rgb[2] + 0.0722 * +rgb[3]) / 255;
        return l2 > 0.5 ? "light" : "dark";
      }
    }
    var bodyBg = getComputedStyle(document.body || document.documentElement).backgroundColor;
    var m = /rgba?\((\d+)[,\s]+(\d+)[,\s]+(\d+)/.exec(bodyBg || "");
    if (m) {
      var l3 = (0.2126 * +m[1] + 0.7152 * +m[2] + 0.0722 * +m[3]) / 255;
      return l3 > 0.5 ? "light" : "dark";
    }
    return "dark";
  }

  function resolveTone() {
    if (settings.tone === "dark" || settings.tone === "light") return settings.tone;
    return appTone();
  }

  function resolveWallpaper() {
    if (settings.bg === "none") return "none";
    if (settings.bg === "custom" && settings.customWall) return 'url("' + settings.customWall + '")';
    if (HOST.wallpaper) return 'url("' + HOST.wallpaper + '")';
    return "none";
  }

  function ensureStyle() {
    if (styleEl && styleEl.isConnected) return styleEl;
    styleEl = document.getElementById("verge-glass");
    if (!styleEl) {
      styleEl = document.createElement("style");
      styleEl.id = "verge-glass";
      document.head.appendChild(styleEl);
    }
    styleEl.textContent = DEFAULT_CSS;
    return styleEl;
  }

  function setVar(style, name, value) {
    if (style.getPropertyValue(name) !== value) style.setProperty(name, value);
  }

  function setAttr(el2, name, value) {
    if (el2.getAttribute(name) !== value) el2.setAttribute(name, value);
  }

  var applying = false;

  function apply() {
    var html = document.documentElement;
    if (applying) return;
    applying = true;
    try {
      applyInner(html);
    } finally {
      applying = false;
    }
  }

  function applyInner(html) {
    if (!DEFAULT_CSS) {
      toast("未加载到主题 CSS：请通过 VergeGlass.ps1 启动，或把 verge-glass.css 内容注入");
    }
    if (!ensureStyle()) return;
    setAttr(html, "data-vg-enabled", "1");
    setAttr(html, "data-vg-tone", resolveTone());
    setAttr(html, "data-vg-bg", settings.bg);
    setAttr(html, "data-vg-pierce", !NATIVE && settings.pierce ? "1" : "0");
    if (NATIVE) setAttr(html, "data-vg-native", "1");
    var s = html.style;
    setVar(s, "--vg-alpha", String(settings.alpha));
    setVar(s, "--vg-content-alpha", String(settings.contentAlpha));

    setVar(s, "--vg-blur", settings.blur + "px");
    setVar(s, "--vg-wallpaper", resolveWallpaper());
    setVar(s, "--vg-wall-opacity", String(settings.wallOpacity));
    setVar(s, "--vg-wall-blur", settings.wallBlur + "px");
    setVar(s, "--vg-veil", String(settings.veil));
    refreshDot();
    refreshRanges();
    scheduleNormalize();
  }

  /* ---------------- 小工具 ---------------- */
  var toastTimer = null;
  function toast(msg, ms) {
    var el2 = document.getElementById("vg-toast");
    if (!el2) {
      el2 = document.createElement("div");
      el2.id = "vg-toast";
      el2.className = "vg-toast";
      document.body.appendChild(el2);
    }
    el2.textContent = msg;
    el2.style.opacity = "1";
    clearTimeout(toastTimer);
    toastTimer = setTimeout(function () {
      el2.style.opacity = "0";
    }, ms || 2400);
  }

  function el(tag, cls, text) {
    var e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text != null) e.textContent = text;
    return e;
  }

  var ICONS = {
    power: '<svg viewBox="0 0 24 24"><path d="M12 4v8"/><path d="M7.4 7a7 7 0 1 0 9.2 0"/></svg>',
    tone: '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="8"/><path d="M12 4v16"/></svg>',
    opacity: '<svg viewBox="0 0 24 24"><rect x="4" y="4" width="11" height="11" rx="3"/><rect x="9" y="9" width="11" height="11" rx="3"/></svg>',
    blur: '<svg viewBox="0 0 24 24"><path d="M12 3c3.6 4.2 6 7.2 6 10.2a6 6 0 0 1-12 0C6 10.2 8.4 7.2 12 3z"/></svg>',
    image: '<svg viewBox="0 0 24 24"><rect x="3" y="5" width="18" height="14" rx="3"/><path d="M3 16l5-3.6 4 3.6 3-2.2 6 4.2"/></svg>',
    eye: '<svg viewBox="0 0 24 24"><path d="M2.2 12S5.8 6 12 6s9.8 6 9.8 6-3.6 6-9.8 6S2.2 12 2.2 12z"/><circle cx="12" cy="12" r="2.6"/></svg>',
    waves: '<svg viewBox="0 0 24 24"><path d="M3 9c2-2 4-2 6 0s4 2 6 0 4-2 6 0"/><path d="M3 15c2-2 4-2 6 0s4 2 6 0 4-2 6 0"/></svg>',
    layers: '<svg viewBox="0 0 24 24"><path d="M12 4l8 4-8 4-8-4 8-4z"/><path d="M4 12l8 4 8-4"/></svg>',
    window: '<svg viewBox="0 0 24 24"><rect x="3.5" y="5" width="17" height="14" rx="2.5"/><path d="M3.5 9.5h17"/></svg>'
  };

  var ICON_COLORS = {
    power: "#30d158",
    tone: "#0a84ff",
    opacity: "#bf5af2",
    blur: "#64d2ff",
    image: "#ff375f",
    eye: "#ff9f0a",
    waves: "#5ac8fa",
    layers: "#5e5ce6",
    window: "#64d2ff"
  };

  var HINTS = {
    none: "不铺背景图；配合下方「窗口透视」即可真正看到桌面",
    wallpaper: "自动读取当前桌面壁纸",
    custom: "使用导入的本地图片"
  };

  var HINTS_NATIVE = {
    none: "不铺任何图，桌面直接透出；窗口内仅面板玻璃可见",
    wallpaper: "桌面壁纸铺在内容下面（静态快照，不跟随桌面变化）",
    custom: "使用导入的本地图片作为背景"
  };

  function hintText() {
    return (NATIVE ? HINTS_NATIVE : HINTS)[settings.bg] || "";
  }

  function rgbaOf(hex, a) {
    var n = parseInt(hex.slice(1), 16);
    return "rgba(" + (n >> 16) + "," + ((n >> 8) & 255) + "," + (n & 255) + "," + a + ")";
  }

  function row(labelText, icon) {
    var r = el("div", "vg-row");
    if (icon && ICONS[icon]) {
      var ico = el("span", "vg-ico");
      ico.style.backgroundColor = rgbaOf(ICON_COLORS[icon], 0.18);
      ico.style.color = ICON_COLORS[icon];
      ico.style.borderColor = rgbaOf(ICON_COLORS[icon], 0.28);
      ico.innerHTML = ICONS[icon];
      r.appendChild(ico);
    }
    r.appendChild(el("label", null, labelText));
    var grow = el("div", "vg-grow");
    r.appendChild(grow);
    return r;
  }

  function fillTrack(input) {
    var min = parseFloat(input.min || 0);
    var max = parseFloat(input.max || 100);
    var v = parseFloat(input.value || 0);
    var pct = max > min ? ((v - min) / (max - min)) * 100 : 0;
    input.style.background =
      "linear-gradient(90deg, var(--primary-main, #0a84ff) 0%, var(--primary-main, #0a84ff) " +
      pct +
      "%, rgba(var(--vg-tint, 255,255,255), 0.16) " +
      pct +
      "%, rgba(var(--vg-tint, 255,255,255), 0.16) 100%)";
  }

  function refreshRanges() {
    var ranges = document.querySelectorAll("#vg-card .vg-range");
    for (var i = 0; i < ranges.length; i++) fillTrack(ranges[i]);
  }

  function slider(labelText, icon, min, max, step, value, fmt, onInput) {
    var r = row(labelText, icon);
    var input = el("input", "vg-range");
    input.type = "range";
    input.min = String(min);
    input.max = String(max);
    input.step = String(step);
    input.value = String(value);
    var val = el("span", "vg-val", fmt(value));
    input.addEventListener("input", function () {
      var v = parseFloat(input.value);
      val.textContent = fmt(v);
      fillTrack(input);
      onInput(v);
    });
    var grow = r.querySelector(".vg-grow");
    grow.appendChild(input);
    grow.appendChild(val);
    setTimeout(function () {
      fillTrack(input);
    }, 0);
    return r;
  }

  function segmented(options, active, onPick) {
    var box = el("div", "vg-seg");
    options.forEach(function (o) {
      var b = el("button", null, o.label);
      b.type = "button";
      if (o.value === active) b.setAttribute("data-active", "1");
      b.addEventListener("click", function () {
        Array.prototype.forEach.call(box.children, function (c) {
          c.removeAttribute("data-active");
        });
        b.setAttribute("data-active", "1");
        onPick(o.value);
      });
      box.appendChild(b);
    });
    return box;
  }

  function switchEl(checked, onChange) {
    var s = el("div", "vg-switch");
    s.setAttribute("role", "switch");
    s.setAttribute("aria-checked", checked ? "true" : "false");
    if (checked) s.setAttribute("data-on", "1");
    s.appendChild(el("i"));
    s.addEventListener("click", function () {
      var on = s.getAttribute("data-on") !== "1";
      if (on) s.setAttribute("data-on", "1");
      else s.removeAttribute("data-on");
      s.setAttribute("aria-checked", on ? "true" : "false");
      onChange(on);
    });
    return s;
  }

  /* ---------------- 状态点 ---------------- */
  function refreshDot() {
    var dot = document.getElementById("vg-dot");
    if (dot) dot.removeAttribute("data-off");
    var status = document.getElementById("vg-status");
    if (status) status.textContent = "已启用";
  }

  /* ---------------- 设置面板 ---------------- */
  var card = null;

  function buildCard() {
    var gridItem = el("div", "vg-grid-item");
    var c = el("div", "vg-card");
    c.id = "vg-card";

    /* 头部 */
    var hd = el("div", "vg-hd");
    hd.appendChild(el("span", "vg-logo", "◐"));
    hd.appendChild(el("h3", null, "半透明主题"));
    var dot = el("span", "vg-dot");
    dot.id = "vg-dot";
    hd.appendChild(dot);
    hd.appendChild(el("span", "vg-badge", "v" + VERSION));
    c.appendChild(hd);
    /* 第三方改版标识 + 构建信息：主题编译进程序，不再是"运行时注入、不改程序文件" */
    var subText = "Clash Verge Rev " + (APP_VERSION || "?") + " · Verge Glass 第三方改版（非官方）";
    if (HOST.build) subText += " · 构建 " + HOST.build;
    c.appendChild(el("div", "vg-sub", subText));

    /* 外观 */
    var sec1 = el("div", "vg-sec");
    sec1.appendChild(el("div", "vg-sec-t", "外观"));
    var g1 = el("div", "vg-group");


    var r1 = row("基调", "tone");
    r1.querySelector(".vg-grow").appendChild(
      segmented(
        [
          { label: "跟随应用", value: "auto" },
          { label: "深色", value: "dark" },
          { label: "浅色", value: "light" }
        ],
        settings.tone,
        function (v) {
          settings.tone = v;
          if (v !== "auto") patchAppTheme(v);
          saveSettings();
          apply();
        }
      )
    );
    g1.appendChild(r1);

    g1.appendChild(
      slider("不透明度", "opacity", 0, 100, 1, Math.round(settings.alpha * 100), function (v) { return v + "%"; }, function (v) {
        settings.alpha = v / 100;
        saveSettings();
        apply();
      })
    );

    sec1.appendChild(g1);
    c.appendChild(sec1);

    /* 背景 */
    var sec2 = el("div", "vg-sec");
    sec2.appendChild(el("div", "vg-sec-t", "背景"));
    var g2 = el("div", "vg-group");

    var r2 = row("背景", "image");
    var grow2 = r2.querySelector(".vg-grow");
    grow2.appendChild(
      segmented(
        [
          { label: "全透明", value: "none" },
          { label: "桌面壁纸", value: "wallpaper" },
          { label: "自选图片", value: "custom" }
        ],
        settings.bg,
        function (v) {
          settings.bg = v;
          saveSettings();
          apply();
          updateHint();
          if (v === "custom") pickImage();
        }
      )
    );
    var pick = el("button", "vg-btn", "选择…");
    pick.type = "button";
    pick.addEventListener("click", pickImage);
    grow2.appendChild(pick);
    g2.appendChild(r2);

    g2.appendChild(
      slider("背景可见度", "eye", 0, 100, 1, Math.round(settings.wallOpacity * 100), function (v) { return v + "%"; }, function (v) {
        settings.wallOpacity = v / 100;
        saveSettings();
        apply();
      })
    );

    g2.appendChild(
      slider("图片模糊", "waves", 0, 40, 1, settings.wallBlur, function (v) { return v + "px"; }, function (v) {
        settings.wallBlur = v;
        saveSettings();
        apply();
      })
    );

    g2.appendChild(
      slider("背景遮罩", "layers", 0, 100, 1, Math.round(settings.veil * 100), function (v) { return v + "%"; }, function (v) {
        settings.veil = v / 100;
        saveSettings();
        apply();
      })
    );
    sec2.appendChild(g2);
    var hint = el("div", "vg-hint");
    hint.id = "vg-hint";
    hint.textContent = hintText();
    sec2.appendChild(hint);
    c.appendChild(sec2);

    /* 窗口 */
    var sec3 = el("div", "vg-sec");
    if (NATIVE) {
      /* 原生透明宿主：整窗自带 alpha，面板与背景各自独立，只留内容不透明度 */
      sec3.appendChild(el("div", "vg-sec-t", "内容"));
      var g3n = el("div", "vg-group");
      g3n.appendChild(
        slider("内容不透明度", "window", 20, 100, 1, Math.round(settings.contentAlpha * 100), function (v) { return v + "%"; }, function (v) {
          settings.contentAlpha = v / 100;
          saveSettings();
          apply();
        })
      );
      sec3.appendChild(g3n);
      var hintN = el("div", "vg-hint");
      hintN.id = "vg-hint-win";
      hintN.textContent = "原生透明窗口：文字与图标默认 100% 不透明，背景（面板玻璃 + 桌面透出）由上面的「不透明度 / 背景」独立控制";
      sec3.appendChild(hintN);
    } else {
      sec3.appendChild(el("div", "vg-sec-t", "窗口"));
      var g3 = el("div", "vg-group");

      var r3 = row("窗口透视", "window");
      r3.querySelector(".vg-grow").appendChild(
        switchEl(settings.pierce, function (v) {
          settings.pierce = v;
          if (v) {
            if (settings.bg !== "none") {
              settings.prevBg = settings.bg;
              settings.bg = "none";
            }
          } else if (settings.prevBg && settings.bg === "none") {
            settings.bg = settings.prevBg;
          }
          saveSettings();
          apply();
          rebuildCard();
          updateHint();
        })
      );
      g3.appendChild(r3);

      g3.appendChild(
        slider("窗口不透明度", null, 5, 100, 1, Math.round(settings.pierceAlpha * 100), function (v) { return v + "%"; }, function (v) {
          settings.pierceAlpha = v / 100;
          saveSettings();
          apply();
        })
      );
      sec3.appendChild(g3);
      var hint2 = el("div", "vg-hint");
      hint2.id = "vg-hint-win";
      hint2.textContent = "开启后整个窗口（含标题栏）按该不透明度透视桌面；建议背景选「全透明」";
      sec3.appendChild(hint2);
    }
    c.appendChild(sec3);

    /* 底部 */
    var foot = el("div", "vg-foot");

    var reset = el("button", "vg-btn", "恢复默认");
    reset.type = "button";
    reset.addEventListener("click", function () {
      settings = loadSettingsFrom(DEFAULTS);
      saveSettings();
      apply();
      rebuildCard();
      toast("已恢复默认");
    });
    foot.appendChild(reset);

    var write = el("button", "vg-btn", "写入应用设置");
    write.type = "button";
    write.title = "把当前主题写进 Clash Verge 的 CSS 注入，不启动插件也会生效";
    write.addEventListener("click", writeToApp);
    foot.appendChild(write);

    var reload = el("button", "vg-btn", "重载");
    reload.type = "button";
    reload.addEventListener("click", function () {
      apply();
      toast("主题已重载");
    });
    foot.appendChild(reload);

    var status = el("span", "vg-status", "已启用");
    status.id = "vg-status";
    foot.appendChild(status);
    c.appendChild(foot);

    gridItem.appendChild(c);
    card = gridItem;
    updateHint();
    return gridItem;
  }

  function loadSettingsFrom(base) {
    var s = {};
    for (var k in base) s[k] = base[k];
    return s;
  }

  function rebuildCard() {
    var old = document.getElementById("vg-card");
    if (old && old.parentNode) old.parentNode.removeChild(old);
    card = null;
    mountPanel(true);
  }

  function patchAppTheme(mode) {
    if (!API) return;
    try {
      API.invoke("patch_verge_config", { payload: { theme_mode: mode } }).catch(function () {});
    } catch (e) {
      /* ignore */
    }
  }

  function pickImage() {
    var input = document.createElement("input");
    input.type = "file";
    input.accept = "image/*";
    input.addEventListener("change", function () {
      var file = input.files && input.files[0];
      if (!file) return;
      var reader = new FileReader();
      reader.onload = function () {
        var img = new Image();
        img.onload = function () {
          var maxW = 2560;
          var scale = Math.min(1, maxW / img.width);
          var cv = document.createElement("canvas");
          cv.width = Math.round(img.width * scale);
          cv.height = Math.round(img.height * scale);
          cv.getContext("2d").drawImage(img, 0, 0, cv.width, cv.height);
          try {
            settings.customWall = cv.toDataURL("image/jpeg", 0.82);
            settings.bg = "custom";
            saveSettings();
            apply();
            toast("背景图已应用");
          } catch (e) {
            toast("图片处理失败");
          }
        };
        img.src = reader.result;
      };
      reader.readAsDataURL(file);
    });
    input.click();
  }

  function varBlock() {
    return (
      "html:root{" +
      "--vg-alpha:" + settings.alpha + ";" +
      "--vg-content-alpha:" + settings.contentAlpha + ";" +

      "--vg-blur:" + settings.blur + "px;" +
      "--vg-wallpaper:" + resolveWallpaper() + ";" +
      "--vg-wall-opacity:" + settings.wallOpacity + ";" +
      "--vg-wall-blur:" + settings.wallBlur + "px;" +
      "--vg-veil:" + settings.veil + ";" +
      "}"
    );
  }

  function writeToApp() {
    if (!API) {
      toast("当前环境不支持写入（缺少 Tauri IPC）");
      return;
    }
    var cssText = DEFAULT_CSS + "\n" + varBlock();
    API.invoke("get_verge_config")
      .then(function (cfg) {
        var theme = (cfg && cfg.theme_setting) || {};
        theme.css_injection = cssText;
        return API.invoke("patch_verge_config", { payload: { theme_setting: theme } });
      })
      .then(function () {
        toast("已写入「设置 → Verge 设置 → 主题 → CSS 注入」，重启后仍生效");
      })
      .catch(function (e) {
        toast("写入失败：" + String(e).slice(0, 80));
      });
  }

  function updateHint() {
    var h = document.getElementById("vg-hint");
    if (h) h.textContent = hintText();
  }

  function movePillTo(sel) {
    if (!sel) return;
    var ul = document.querySelector("ul.the-menu");
    var pill = ul ? ul.querySelector(".vg-nav-pill") : null;
    if (!ul || !pill) return;
    var r = sel.getBoundingClientRect();
    var ur = ul.getBoundingClientRect();
    if (r.height < 8) return;
    pill.style.top = r.top - ur.top + "px";
    pill.style.left = r.left - ur.left + "px";
    pill.style.right = "auto";
    pill.style.width = r.width + "px";
    pill.style.height = r.height + "px";
    pill.style.opacity = "1";
  }

  var navPending = null;
  var navPendingAt = 0;

  function ensureNavPill() {
    var ul = document.querySelector("ul.the-menu");
    if (!ul) return;
    if (!ul.__vgNavBound) bindNav();
    if (!ul.classList.contains("vg-nav-host")) ul.classList.add("vg-nav-host");
    var pill = ul.querySelector(".vg-nav-pill");
    if (!pill) {
      pill = el("span", "vg-nav-pill");
      ul.appendChild(pill);
    }
    var sel = ul.querySelector(".MuiListItemButton-root.Mui-selected");
    if (navPending && Date.now() - navPendingAt < 900) {
      movePillTo(navPending);
      return;
    }
    navPending = null;
    if (!sel) {
      pill.style.opacity = "0";
      return;
    }
    movePillTo(sel);
  }

  var normalizeTimer = null;

  function scheduleNormalize() {
    if (normalizeTimer) return;
    normalizeTimer = setTimeout(function () {
      normalizeTimer = null;
      normalizeSurfaces();
    }, 420);
  }

  /* 把 App 内联/emotion 写死的不透明底色（卡片、说明条等）换成玻璃面 */
  var lastNormalize = 0;
  var lastMicro = 0;

  /* 隐藏图表底部小字：数据点 / 压缩后 / 帧率 与「平滑」（纯文本扫描，便宜） */
  function markChartMicroText() {
    var now = Date.now();
    if (now - lastMicro < 1200) return;
    lastMicro = now;
    var root2 = document.querySelector(".the-content");
    if (!root2) return;
    var leaves = root2.querySelectorAll("div, span");
    for (var k = 0; k < leaves.length; k++) {
      var lf = leaves[k];
      if (lf.children.length !== 0 || lf.classList.contains("vg-hide")) continue;
      var lt = (lf.textContent || "").trim();
      if (!lt || lt.length > 40) continue;
      if (/^\u6570\u636e\u70b9[\s:：]/.test(lt) || lt === "\u5e73\u6ed1") lf.classList.add("vg-hide");
    }
  }

  function normalizeSurfaces() {
    var now = Date.now();
    if (now - lastNormalize < 2000) return;
    lastNormalize = now;
    var root = document.querySelector(".the-content");
    if (!root) return;
    var nodes = root.querySelectorAll("div, section, header, li, article");
    var limit = nodes.length > 2500 ? 2500 : nodes.length;
    for (var i = 0; i < limit; i++) {
      var n = nodes[i];
      if (n.closest("#vg-card")) continue;
      var nrect = n.getBoundingClientRect();
      if (nrect.width < 14 || nrect.height < 14) continue;
      if (n.classList.contains("vg-surface")) continue;
      var bg = getComputedStyle(n).backgroundColor;
      var m = /^rgb\((\d+), (\d+), (\d+)\)$/.exec(bg);
      if (!m) continue;
      var r = +m[1], g = +m[2], b = +m[3];
      // #2E303D (46,48,61) sits at g-b = 13, so the window has to stay loose here.
      var neutral = Math.abs(r - g) < 7 && Math.abs(g - b) < 16;
      var dark = neutral && r >= 22 && r <= 62;
      var light = r >= 238 && g >= 238 && b >= 238;
      if (dark || light) n.classList.add("vg-surface");
    }

    markChartMicroText();

    // 选项卡右上角状态点：8x8 圆点，标记出来以便 CSS 只在选中态显示
    var dots = root.querySelectorAll(".MuiPaper-root > div.MuiBox-root");
    for (var j = 0; j < dots.length; j++) {
      var d = dots[j];
      var dr = d.getBoundingClientRect();
      if (dr.width < 5 || dr.width > 13 || dr.height < 5 || dr.height > 13) continue;
      d.classList.remove("vg-surface");
      var dcs = getComputedStyle(d);
      if (dcs.borderTopLeftRadius.indexOf("50%") >= 0 && !d.classList.contains("vg-ind")) {
        d.classList.add("vg-ind");
      }
    }
  }

  function bindNav() {
    var ul = document.querySelector("ul.the-menu");
    if (!ul || ul.__vgNavBound) return;
    ul.__vgNavBound = true;
    ul.setAttribute("data-vg-nav", "1");
    var kick = function () {
      requestAnimationFrame(ensureNavPill);
      setTimeout(ensureNavPill, 60);
      setTimeout(ensureNavPill, 160);
      setTimeout(ensureNavPill, 400);
    };
    // 按下就把胶囊移过去（乐观更新），不必等 React 切换 selected
    ul.addEventListener(
      "pointerdown",
      function (e) {
        var item = e.target && e.target.closest ? e.target.closest(".MuiListItemButton-root") : null;
        if (item) {
          navPending = item;
          navPendingAt = Date.now();
          movePillTo(item);
        }
        kick();
      },
      true
    );
    ul.addEventListener("click", kick, true);
    new MutationObserver(function () {
      ensureNavPill();
    }).observe(ul, { attributes: true, subtree: true, attributeFilter: ["class"] });
  }

  function dropDuplicateCards() {
    Array.prototype.forEach.call(document.querySelectorAll(".vg-grid-item"), function (n) {
      if (n !== card) n.remove();
    });
  }

  /* ---------------- 面板挂载 ---------------- */
  function mountPanel(force) {
    try {
      // 同一文档里只允许最新注入的实例挂载面板
      if (W.__VERGE_GLASS_OWNER__ !== OWNER) {
        if (card && card.parentNode) card.parentNode.removeChild(card);
        return;
      }
      if (location.pathname !== "/settings") {
        if (card && card.parentNode) card.parentNode.removeChild(card);
        return;
      }
      if (card && card.isConnected) {
        dropDuplicateCards();
        return;
      }
      var grid =
        document.querySelector(".the-content .base-content .MuiGrid-container") ||
        document.querySelector(".the-content .MuiGrid-container");
      if (!grid) return;
      scheduleNormalize();
      if (!card) card = buildCard();
      grid.appendChild(card);
      dropDuplicateCards();
      refreshDot();
      refreshRanges();
    } catch (e) {
      /* ignore */
    }
  }

  /* ---------------- 启动 ---------------- */
  // 把当前路由标在 <html> 上，CSS 才能按页面做取舍（比如首页隐藏右上角快捷入口）
  function markPage() {
    var p = (location.pathname || "/").replace(/^\/+/, "").replace(/\/+$/, "");
    if (!p) p = "home";
    var el = document.documentElement;
    if (el.getAttribute("data-vg-page") !== p) el.setAttribute("data-vg-page", p);
  }

  // 三个窗口按钮的原生顺序是 最小化/最大化/关闭，给它们加上悬停标签
  var WIN_LABELS = ["最小化", "最大化", "关闭"];
  function labelWindowControls() {
    if (!NATIVE) return;
    var box = document.querySelector(".the_titlebar > div:not(.the_titlebar-drag-region)");
    if (!box) return;
    var btns = box.querySelectorAll("button");
    for (var i = 0; i < btns.length && i < WIN_LABELS.length; i++) {
      if (btns[i].getAttribute("data-vg-label") !== WIN_LABELS[i]) {
        btns[i].setAttribute("data-vg-label", WIN_LABELS[i]);
      }
    }
  }

  function boot() {
    W.__VG_BOOT_SCHEDULED__ = false;
    if (W.__VERGE_GLASS__) return;
    if (!document.body) {
      setTimeout(boot, 50);
      return;
    }
    W.__VERGE_GLASS_OWNER__ = OWNER;
    markPage();
    labelWindowControls();
    apply();
    mountPanel(true);
    ensureNavPill();
    bindNav();

    var lastPath = location.pathname;
    setInterval(function () {
      if (location.pathname !== lastPath) {
        lastPath = location.pathname;
        markPage();
        mountPanel(true);
      } else {
        mountPanel(false);
      }
      ensureNavPill();
      labelWindowControls();
      markChartMicroText();
    }, 500);

    if (document.documentElement) {
      new MutationObserver(function () {
        if (location.pathname === "/settings" && (!card || !card.isConnected)) mountPanel(true);
        scheduleNormalize();
      }).observe(document.documentElement, { childList: true, subtree: true });
      new MutationObserver(function () {
        if (applying) return;
        apply();
      }).observe(document.documentElement, { attributes: true, attributeFilter: ["style"] });
    }

    var tries = 0;
    var timer = setInterval(function () {
      tries++;
      mountPanel(true);
      if (tries > 20) clearInterval(timer);
    }, 500);

    W.__VERGE_GLASS__ = {
      version: VERSION,
      get settings() {
        return settings;
      },
      get windowAlpha() {
        // Native hosts expose a real alpha channel, so the window itself must stay
        // fully opaque; the daemon then leaves WS_EX_LAYERED alone.
        if (NATIVE) return 1;
        return settings.pierce ? settings.pierceAlpha : 1;
      },
      apply: apply,
      mount: mountPanel
    };
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", boot, { once: true });
  } else {
    setTimeout(boot, 0);
  }
})();
