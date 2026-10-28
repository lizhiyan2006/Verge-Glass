(async () => {
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const menu = document.querySelector("ul.the-menu");
  const routes = ["/", "/proxies", "/profile", "/connections", "/rules", "/logs", "/unlock", "/settings"];
  const census = {};
  for (let i = 0; i < routes.length; i++) {
    menu.children[i].querySelector('[role="button"]').click();
    await sleep(700);
    const seen = new Set();
    for (const el of document.querySelectorAll("body *")) {
      const cs = getComputedStyle(el);
      const bg = cs.backgroundColor;
      if (!bg || bg === "rgba(0, 0, 0, 0)" || bg === "transparent") continue;
      if (!/^rgb\(/.test(bg) && !/^rgba\([^)]*, 1\)$/.test(bg)) continue;
      const r = el.getBoundingClientRect();
      if (r.width < 60 || r.height < 24) continue;
      const cls = (typeof el.className === "string" ? el.className : "")
        .split(/\s+/)
        .filter((c) => c && !c.startsWith("css-") && !/^(MuiGrid|MuiStack)/.test(c))
        .slice(0, 6)
        .join(".");
      const key = el.tagName.toLowerCase() + (cls ? "." + cls : "") + "|" + bg;
      if (seen.has(key)) continue;
      seen.add(key);
      census[key] = census[key] || { routes: new Set(), n: 0, sample: el.className.toString().slice(0, 90) };
      census[key].routes.add(routes[i]);
      census[key].n++;
    }
  }
  const out = Object.entries(census)
    .map(([k, v]) => ({ k, routes: [...v.routes].join(","), n: v.n, cls: v.sample }))
    .sort((a, b) => b.n - a.n)
    .slice(0, 40);
  return JSON.stringify(out, null, 1);
})()
