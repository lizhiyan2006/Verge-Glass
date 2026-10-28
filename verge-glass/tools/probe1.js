(async () => {
  const out = {};
  out.hasConvert = typeof window.__TAURI_INTERNALS__?.convertFileSrc;
  const p = "C:\\Users\\394\\AppData\\Roaming\\Microsoft\\Windows\\Themes\\TranscodedWallpaper";
  let url = null;
  try { url = window.__TAURI_INTERNALS__.convertFileSrc(p); } catch (e) { out.convErr = String(e); }
  out.url = url;
  if (url) {
    out.img = await new Promise((res) => {
      const img = new Image();
      img.onload = () => res("ok " + img.naturalWidth + "x" + img.naturalHeight);
      img.onerror = () => res("error");
      setTimeout(() => res("timeout"), 5000);
      img.src = url;
    });
  }
  try {
    const cfg = await window.__TAURI_INTERNALS__.invoke("get_verge_config");
    out.cfgKeys = cfg && typeof cfg === "object" ? Object.keys(cfg).slice(0, 8) : String(cfg);
    out.theme = cfg?.theme_setting ?? cfg?.verge?.theme_setting ?? null;
  } catch (e) { out.cfgErr = String(e); }
  return JSON.stringify(out);
})()
