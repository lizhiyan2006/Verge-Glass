(async () => {
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const out = {};
  const btns = [...document.querySelectorAll("#vg-card .vg-btn")];
  out.buttons = btns.map((b) => b.textContent);
  const write = btns.find((b) => b.textContent === "写入应用设置");
  if (!write) return JSON.stringify({ error: "write button missing" });
  write.click();
  await sleep(2000);
  const cfg = await window.__TAURI_INTERNALS__.invoke("get_verge_config");
  const css = (cfg.theme_setting && cfg.theme_setting.css_injection) || "";
  out.cssLen = css.length;
  out.hasVars = css.indexOf("--vg-alpha") >= 0;
  out.themeKeys = cfg.theme_setting ? Object.keys(cfg.theme_setting) : null;
  out.toast = (document.getElementById("vg-toast") || {}).textContent || "";
  return JSON.stringify(out);
})()
