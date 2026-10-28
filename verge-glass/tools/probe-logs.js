(() => {
  const rows = [...document.querySelectorAll(".the-content div")].filter((d) => {
    const t = d.textContent || "";
    return t.indexOf("[UDP]") >= 0 && d.children.length >= 2 && d.getBoundingClientRect().height > 10;
  });
  const pick = rows.slice(0, 3).map((d) => {
    const cs = getComputedStyle(d);
    const r = d.getBoundingClientRect();
    return {
      cls: (d.className || "").toString().slice(0, 80),
      h: Math.round(r.height),
      lh: cs.lineHeight,
      fs: cs.fontSize,
      ff: cs.fontFamily.slice(0, 40),
      pad: cs.padding,
      margin: cs.margin,
      display: cs.display,
      kids: [...d.children].map((c) => {
        const ccs = getComputedStyle(c);
        const cr = c.getBoundingClientRect();
        return { t: c.tagName, cls: (c.className || "").toString().slice(0, 50), y: Math.round(cr.top - r.top), h: Math.round(cr.height), lh: ccs.lineHeight, fs: ccs.fontSize, pos: ccs.position };
      }),
    };
  });
  // 查找时间戳元素
  const times = [...document.querySelectorAll(".the-content *")].filter((e) => e.children.length === 0 && /^\d\d-\d\d \d\d:\d\d:\d\d$/.test(e.textContent.trim())).slice(0, 2);
  const timeInfo = times.map((e) => {
    const cs = getComputedStyle(e);
    return { tag: e.tagName, cls: (e.className || "").toString().slice(0, 60), lh: cs.lineHeight, fs: cs.fontSize, pos: cs.position, y: Math.round(e.getBoundingClientRect().top) };
  });
  return JSON.stringify({ count: rows.length, rows: pick, timeInfo }, null, 1);
})()
