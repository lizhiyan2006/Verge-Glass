(() => {
  const q = (sel) => document.querySelectorAll(sel).length;
  const recharts = q('[class*="recharts"]');
  const svgInTrafficCard = (() => {
    const title = [...document.querySelectorAll(".the-content *")].find((e) => e.textContent.trim() === "流量统计" && e.children.length === 0);
    let card = title;
    for (let i = 0; i < 6 && card; i++) card = card.parentElement;
    if (!card) return null;
    const svgs = [...card.querySelectorAll("svg")];
    return {
      cardH: Math.round(card.getBoundingClientRect().height),
      svgCount: svgs.length,
      svgInfo: svgs.slice(0, 4).map((s) => {
        const r = s.getBoundingClientRect();
        return { w: Math.round(r.width), h: Math.round(r.height), outer: s.outerHTML.slice(0, 160).replace(/\s+/g, " ") };
      }),
      divs: [...card.querySelectorAll("div")].filter((d) => {
        const cs = getComputedStyle(d);
        return cs.backgroundImage !== "none" || d.children.length > 10;
      }).slice(0, 5).map((d) => ({ cls: d.className.slice(0, 50), kids: d.children.length, bg: getComputedStyle(d).backgroundImage.slice(0, 60) })),
    };
  })();
  return JSON.stringify({ rechartsCount: recharts, trafficCard: svgInTrafficCard }, null, 1);
})()
