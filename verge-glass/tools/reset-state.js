(async () => {
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  // clear the css_injection we wrote during the test, then reset plugin defaults
  await window.__TAURI_INTERNALS__.invoke("patch_verge_config", { payload: { theme_setting: {} } });
  await sleep(800);
  localStorage.removeItem("verge-glass:v1");
  // pick "跟随应用" and reset sliders through the real UI when possible
  const segs = [...document.querySelectorAll("#vg-card .vg-seg button")];
  const auto = segs.find((b) => b.textContent === "跟随应用");
  if (auto) auto.click();
  await sleep(500);
  const cfg = await window.__TAURI_INTERNALS__.invoke("get_verge_config");
  const css = (cfg.theme_setting && cfg.theme_setting.css_injection) || "";
  return JSON.stringify({
    cssLen: css.length,
    tone: document.documentElement.getAttribute("data-vg-tone"),
    settings: window.__VERGE_GLASS__.settings,
  });
})()
