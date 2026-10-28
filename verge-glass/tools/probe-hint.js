(async () => {
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const b = [...document.querySelectorAll("ul.the-menu .MuiListItemButton-root")]
    .find((x) => x.textContent.replace(/\s+/g, "").startsWith("首页"));
  if (b) b.click();
  await sleep(1000);
  const hint = [...document.querySelectorAll(".the-content *")]
    .find((e) => e.children.length === 0 && e.textContent.trim().startsWith("基于预设规则智能判断"));
  if (!hint) return "no hint";
  const chain = [];
  let p = hint;
  for (let i = 0; i < 7 && p; i++) {
    const cs = getComputedStyle(p);
    chain.push({
      i,
      tag: p.tagName,
      cls: (p.className || "").toString().slice(0, 70),
      bg: cs.backgroundColor,
      border: cs.borderTopWidth + " " + cs.borderTopColor,
      radius: cs.borderTopLeftRadius,
      w: Math.round(p.getBoundingClientRect().width),
    });
    p = p.parentElement;
  }
  return JSON.stringify(chain, null, 1);
})()
