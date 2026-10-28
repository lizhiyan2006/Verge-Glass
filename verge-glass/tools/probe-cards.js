(() => {
  const grid = document.querySelector(".the-content .base-content .MuiGrid-container");
  if (!grid) return "no grid";
  const out = [];
  const walk = (el, d) => {
    if (!el || d > 3) return;
    const r = el.getBoundingClientRect();
    const cls = (typeof el.className === "string" ? el.className : "").split(/\s+/).filter((c) => c && !c.startsWith("css-")).slice(0, 5).join(".");
    const cs = getComputedStyle(el);
    out.push({ d, t: el.tagName.toLowerCase() + (cls ? "." + cls : ""), w: Math.round(r.width), h: Math.round(r.height), bg: cs.backgroundColor, border: cs.borderTopWidth + " " + cs.borderTopColor, radius: cs.borderTopLeftRadius });
    [...el.children].forEach((c) => walk(c, d + 1));
  };
  walk(grid, 0);
  return JSON.stringify(out.slice(0, 26), null, 1);
})()
