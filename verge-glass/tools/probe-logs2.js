(() => {
  const items = [...document.querySelectorAll(".the-content div")].filter((d) => {
    const st = d.getAttribute("style") || "";
    return st.indexOf("position: absolute") >= 0 && d.children.length === 2 && d.querySelector(".time");
  });
  const rows = items.slice(0, 5).map((d) => {
    const r = d.getBoundingClientRect();
    const kids = [...d.children].map((c) => {
      const cr = c.getBoundingClientRect();
      return { top: Math.round(cr.top - r.top), h: Math.round(cr.height), text: c.textContent.trim().slice(0, 24) };
    });
    return {
      topStyle: d.style.top,
      h: Math.round(r.height),
      y: Math.round(r.top),
      kids,
      inline: (d.getAttribute("style") || "").slice(0, 120),
    };
  });
  return JSON.stringify({ n: items.length, rows }, null, 1);
})()
