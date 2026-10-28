(async () => {
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const b = [...document.querySelectorAll("ul.the-menu .MuiListItemButton-root")]
    .find((x) => x.textContent.replace(/\s+/g, "").startsWith("首页"));
  if (b) b.click();
  await sleep(1200);
  const tabs = [...document.querySelectorAll(".the-content .MuiPaper-root")]
    .filter((e) => e.textContent.trim() === "系统代理" || e.textContent.trim() === "虚拟网卡模式");
  const out = tabs.map((t) => {
    const cs = getComputedStyle(t);
    return {
      text: t.textContent.trim(),
      html: t.outerHTML.replace(/\s+/g, " ").slice(0, 900),
      border: cs.borderTopWidth + " " + cs.borderTopColor,
      radius: cs.borderTopLeftRadius,
      bg: cs.backgroundColor,
      pos: cs.position,
    };
  });
  return JSON.stringify(out, null, 1);
})()
