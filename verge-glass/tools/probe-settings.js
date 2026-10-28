(async () => {
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const menu = document.querySelector("ul.the-menu");
  const btn = menu.children[7].querySelector('[role="button"]');
  btn.click();
  await sleep(900);
  const page = document.querySelector(".the-content .base-page");
  const walk = (el, d) => {
    if (!el || d > 6) return null;
    const cls = typeof el.className === "string" ? el.className.trim().split(/\s+/).slice(0, 3).join(".") : "";
    return {
      t: el.tagName.toLowerCase() + (cls ? "." + cls : ""),
      bg: getComputedStyle(el).backgroundColor,
      c: [...el.children].slice(0, 8).map((x) => walk(x, d + 1)),
    };
  };
  return JSON.stringify({
    path: location.pathname,
    html: page ? walk(page, 0) : null,
    grid: (() => {
      const g = document.querySelector(".the-content .MuiGrid-container");
      return g ? { n: g.children.length, cls: g.className, kids: [...g.children].map((x) => x.className + " | bg=" + getComputedStyle(x).backgroundColor) } : null;
    })(),
    toneVar: getComputedStyle(document.documentElement).getPropertyValue("--background-color").trim(),
  });
})()
