(() => {
  const walk = (el, d, out) => {
    if (!el || d > 7) return;
    const r = el.getBoundingClientRect();
    if (r.width < 4 || r.height < 4) return;
    const cls = (typeof el.className === "string" ? el.className : "").split(/\s+/).filter((c) => c && !c.startsWith("css-")).slice(0, 5).join(".");
    out.push({
      d,
      t: el.tagName.toLowerCase() + (cls ? "." + cls : ""),
      wh: [Math.round(r.width), Math.round(r.height)],
      bg: getComputedStyle(el).backgroundColor,
      br: getComputedStyle(el).borderRadius,
    });
    [...el.children].forEach((c) => walk(c, d + 1, out));
  };
  const all = [...document.querySelectorAll(".the-content *")];
  const title = all.find((e) => e.textContent.trim() === "流量统计" && e.children.length === 0);
  let card = title;
  for (let i = 0; i < 6 && card; i++) card = card.parentElement;
  const out = [];
  if (card) walk(card, 0, out);
  const svgs = [...document.querySelectorAll(".the-content svg")].map((s) => {
    const r = s.getBoundingClientRect();
    return { w: Math.round(r.width), h: Math.round(r.height), cls: (typeof s.className === "string" ? s.className : "").slice(0, 60) };
  }).filter((s) => s.w > 50);
  return JSON.stringify({ titleFound: !!title, tree: out.slice(0, 40), bigSvgs: svgs.slice(0, 10) }, null, 1);
})()
