(() => {
  const cs = [...document.querySelectorAll("canvas")].map((c) => {
    const r = c.getBoundingClientRect();
    return { w: Math.round(r.width), h: Math.round(r.height), cls: c.className, parent: c.parentElement ? c.parentElement.className : "", style: c.getAttribute("style") };
  });
  const all = [...document.querySelectorAll("*")];
  const maybe = all.filter((e) => e.tagName.toLowerCase() === "canvas" || e.getAttribute("data-testid") === "traffic-graph");
  return JSON.stringify({ canvasCount: cs.length, cs, total: all.length, maybe: maybe.length }, null, 1);
})()
