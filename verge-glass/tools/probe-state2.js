(() => {
  return JSON.stringify({
    href: location.href,
    ready: !!window.__VERGE_GLASS_READY__,
    obj: !!window.__VERGE_GLASS__,
    host: window.__VG_HOST__ ? window.__VG_HOST__.version : null,
    styleLen: (document.getElementById("verge-glass") || {}).textContent?.length || 0,
    card: !!document.getElementById("vg-card"),
    tone: document.documentElement.getAttribute("data-vg-tone"),
    alpha: getComputedStyle(document.documentElement).getPropertyValue("--vg-alpha"),
    ls: localStorage.getItem("verge-glass:v1"),
    bodyKids: document.body.children.length,
  });
})()
