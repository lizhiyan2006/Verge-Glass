(async () => {
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const menu = document.querySelector("ul.the-menu");
  if (menu) menu.children[0].querySelector("[role=button]").click();
  await sleep(900);
  const pick = (el, max) => {
    if (!el) return null;
    return el.outerHTML.replace(/\s+/g, " ").slice(0, max);
  };
  const traffic = document.querySelector(".the-traffic");
  const content = document.querySelector(".the-content");
  const canvases = [...document.querySelectorAll("canvas")].map((c) => ({
    cls: c.className,
    w: c.width,
    h: c.height,
    rect: [Math.round(c.getBoundingClientRect().width), Math.round(c.getBoundingClientRect().height)],
    parent: c.parentElement ? c.parentElement.className : "",
  }));
  const svgs = [...document.querySelectorAll(".the-content svg")].length;
  // find elements whose text looks like a number with unit
  const nums = [...document.querySelectorAll(".the-content *")]
    .filter((e) => e.children.length === 0 && /^[\d.,]+\s?(B\/s|KB\/s|MB\/s|GB|%|ms)?$/.test(e.textContent.trim()) && e.textContent.trim())
    .slice(0, 12)
    .map((e) => ({ t: e.textContent.trim(), cls: (typeof e.className === "string" ? e.className : "").slice(0, 70) }));
  return JSON.stringify({
    trafficHtml: pick(traffic, 1200),
    contentFirst: pick(content.children[0], 400),
    canvases,
    svgCount: svgs,
    nums,
  }, null, 1);
})()
