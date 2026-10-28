(async () => {
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  if (!document.querySelector(".the-content .MuiSwitch-root")) {
    const menu = document.querySelector("ul.the-menu");
    menu.children[0].querySelector("[role=button]").click();
    await sleep(1000);
  }
  const info = (el) => {
    if (!el) return null;
    const cs = getComputedStyle(el);
    const r = el.getBoundingClientRect();
    return {
      tag: el.tagName.toLowerCase(),
      cls: (typeof el.className === "string" ? el.className : "").split(/\s+/).filter(Boolean).slice(0, 5).join("."),
      wh: [Math.round(r.width), Math.round(r.height)],
      bg: cs.backgroundColor,
      radius: cs.borderTopLeftRadius,
      border: cs.borderTopWidth + " " + cs.borderTopColor,
    };
  };
  const sw = document.querySelector(".the-content .MuiSwitch-root");
  const chain = [];
  let p = sw;
  for (let i = 0; i < 7 && p; i++) { chain.push(info(p)); p = p.parentElement; }
  const paper = [...document.querySelectorAll(".the-content .MuiPaper-root")].find((e) => e.textContent.trim() === "系统代理");
  const btn = [...document.querySelectorAll(".the-content .MuiButton-root")].find((e) => e.textContent.includes("虚拟网卡模式"));
  return JSON.stringify({
    chain,
    selectedTab: info(paper),
    unselectedBtn: info(btn),
    unselectedParent: btn ? info(btn.parentElement) : null,
    switchTrack: info(document.querySelector(".the-content .MuiSwitch-track")),
  }, null, 1);
})()
