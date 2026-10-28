(() => {
  const menu = document.querySelector("ul.the-menu");
  menu.children[0].querySelector("[role=button]").click();
  const info = (el) => {
    if (!el) return null;
    const cs = getComputedStyle(el);
    const r = el.getBoundingClientRect();
    return {
      tag: el.tagName.toLowerCase(),
      cls: (typeof el.className === "string" ? el.className : "").split(/\s+/).filter(Boolean).slice(0, 4).join("."),
      rect: [Math.round(r.x), Math.round(r.y), Math.round(r.width), Math.round(r.height)],
      bg: cs.backgroundColor,
      borderBottom: cs.borderBottomWidth + " " + cs.borderBottomColor,
      borderTop: cs.borderTopWidth + " " + cs.borderTopColor,
      radius: cs.borderTopLeftRadius,
    };
  };
  const bar = document.querySelector(".the-bar");
  const header = document.querySelector(".the-content .base-page > header");
  // 系统代理那一行的祖先链
  const sw = document.querySelector(".the-content .MuiSwitch-root");
  const chain = [];
  let p = sw;
  for (let i = 0; i < 6 && p; i++) { chain.push(info(p)); p = p.parentElement; }
  // 网络设置选项卡按钮
  const tab = [...document.querySelectorAll(".the-content .MuiPaper-root")].find((e) => e.textContent.trim() === "系统代理");
  const tabUn = [...document.querySelectorAll(".the-content .MuiButton-root")].find((e) => e.textContent.trim().includes("虚拟网卡模式"));
  return JSON.stringify({
    bar: info(bar),
    barKids: bar ? [...bar.children].map(info) : null,
    header: info(header),
    headerStyle: header ? (header.getAttribute("style") || "").slice(0, 120) : null,
    chain: chain,
    tab: info(tab),
    tabUn: info(tabUn),
    tabUnParent: tabUn ? info(tabUn.parentElement) : null,
  }, null, 1);
})()
