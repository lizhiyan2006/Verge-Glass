(() => {
  const all = [...document.querySelectorAll(".the-content *")];
  const hits = all.filter((e) => e.textContent.trim().startsWith("活跃") || e.textContent.trim().startsWith("已关闭"));
  const info = (el) => {
    if (!el) return null;
    const cs = getComputedStyle(el);
    const r = el.getBoundingClientRect();
    return {
      tag: el.tagName.toLowerCase(),
      cls: (typeof el.className === "string" ? el.className : "").slice(0, 100),
      bg: cs.backgroundColor,
      radius: cs.borderTopLeftRadius,
      margin: cs.margin,
      w: Math.round(r.width),
      h: Math.round(r.height),
      text: el.textContent.trim().slice(0, 12),
    };
  };
  const out = hits.slice(-6).map((e) => ({ self: info(e), parent: info(e.parentElement) }));
  // 表格容器是否有底色
  const table = document.querySelector('.the-content div[style*="overscroll-behavior"]');
  const rowDivs = [...document.querySelectorAll('.the-content div[style*="display: flex"]')]
    .filter((d) => d.getBoundingClientRect().height > 25 && d.getBoundingClientRect().height < 45)
    .slice(0, 3)
    .map((d) => ({ bg: d.style.backgroundColor || "(inline none)", computed: getComputedStyle(d).backgroundColor, h: Math.round(d.getBoundingClientRect().height) }));
  return JSON.stringify({ tabs: out, tableBg: table ? getComputedStyle(table).backgroundColor : null, rows: rowDivs }, null, 1);
})()
