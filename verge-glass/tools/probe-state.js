(() => {
  const r = document.getElementById("root");
  return JSON.stringify({
    href: location.href,
    rootLen: r ? r.innerHTML.length : -1,
    rootKids: r ? [...r.children].map((c) => c.tagName + "." + (typeof c.className === "string" ? c.className.slice(0, 40) : "")) : null,
    menu: !!document.querySelector(".the-menu"),
    styleLen: (document.getElementById("verge-glass") || {}).textContent?.length || 0,
    vgReady: !!window.__VERGE_GLASS_READY__,
    vgObj: !!window.__VERGE_GLASS__,
    card: !!document.getElementById("vg-card"),
    bodyHTMLHead: document.body.innerHTML.slice(0, 200),
    htmlStyle: document.documentElement.getAttribute("style")?.slice(0, 120),
  });
})()
