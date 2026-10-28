(() => {
  const times = [...document.querySelectorAll(".the-content .time")].slice(0, 6);
  const out = times.map((t) => {
    let row = t;
    for (let i = 0; i < 5 && row; i++) {
      if (getComputedStyle(row).position === "absolute") break;
      row = row.parentElement;
    }
    const rr = row ? row.getBoundingClientRect() : null;
    const tr = t.getBoundingClientRect();
    const kids = row ? [...row.querySelectorAll(":scope > div")].map((c) => {
      const cr = c.getBoundingClientRect();
      return { top: Math.round(cr.top - rr.top), h: Math.round(cr.height), txt: c.textContent.trim().slice(0, 30) };
    }) : null;
    return {
      rowTop: row ? Math.round(rr.top) : null,
      rowH: row ? Math.round(rr.height) : null,
      rowInline: row ? (row.getAttribute("style") || "").slice(0, 140) : null,
      timeTop: Math.round(tr.top - (rr ? rr.top : 0)),
      kids,
    };
  });
  return JSON.stringify(out, null, 1);
})()
