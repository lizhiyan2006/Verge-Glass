(async () => {
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const menu = document.querySelector("ul.the-menu");
  const go = (name) => {
    const b = [...document.querySelectorAll("ul.the-menu .MuiListItemButton-root")]
      .find((x) => x.textContent.replace(/\s+/g, "").startsWith(name));
    if (b) b.click();
  };
  const out = {};

  // 代理模式解释框（首页）
  go("首页");
  await sleep(1000);
  const hint = [...document.querySelectorAll(".the-content *")]
    .find((e) => e.children.length === 0 && e.textContent.trim().startsWith("基于预设规则智能判断"));
  if (hint) {
    let p = hint;
    for (let i = 0; i < 3 && p; i++) p = p.parentElement;
    const cs = getComputedStyle(p);
    out.proxyHint = { tag: p.tagName, cls: p.className.slice(0, 80), bg: cs.backgroundColor, border: cs.borderTopWidth + " " + cs.borderTopColor, radius: cs.borderTopLeftRadius };
  }

  // 订阅页
  go("订阅");
  await sleep(1200);
  const opaque = [];
  const seen = new Set();
  for (const el of document.querySelectorAll(".the-content *")) {
    const cs = getComputedStyle(el);
    const bg = cs.backgroundColor;
    if (!bg || bg === "rgba(0, 0, 0, 0)") continue;
    const m = /^rgb\((\d+), (\d+), (\d+)\)$/.exec(bg);
    if (!m) continue;
    const r = el.getBoundingClientRect();
    if (r.width < 40 || r.height < 20) continue;
    const key = el.tagName + "|" + bg + "|" + (el.className || "").toString().slice(0, 40);
    if (seen.has(key)) continue;
    seen.add(key);
    opaque.push({ tag: el.tagName, cls: (el.className || "").toString().slice(0, 70), bg, w: Math.round(r.width), h: Math.round(r.height), inline: (el.getAttribute("style") || "").slice(0, 60) });
  }
  out.opaqueCount = opaque.length;
  out.opaque = opaque.slice(0, 14);
  return JSON.stringify(out, null, 1);
})()
