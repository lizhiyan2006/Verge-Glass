(async () => {
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const menu = document.querySelector("ul.the-menu");
  const out = {};
  const info = (el) => {
    if (!el) return null;
    const cs = getComputedStyle(el);
    return {
      tag: el.tagName.toLowerCase(),
      cls: (typeof el.className === "string" ? el.className : "").slice(0, 110),
      bg: cs.backgroundColor,
      radius: cs.borderTopLeftRadius,
      border: cs.borderTopWidth + " " + cs.borderTopColor,
      text: el.textContent.trim().slice(0, 20),
    };
  };

  // ---- 连接页 ----
  menu.children[3].querySelector("[role=button]").click();
  await sleep(900);
  const tabs = [...document.querySelectorAll(".the-content .MuiTab-root, .the-content [role=tab]")];
  out.tabs = tabs.map((t) => ({ t: t.textContent.trim(), cls: t.className.slice(0, 60), gap: getComputedStyle(t.parentElement).gap }));
  const rows = [...document.querySelectorAll(".the-content .MuiListItemButton-root, .the-content li")].slice(0, 6);
  out.connRows = rows.map(info);
  const hostLabel = [...document.querySelectorAll(".the-content *")].find((e) => e.children.length === 0 && e.textContent.trim() === "主机");
  out.hostLabel = info(hostLabel);
  if (hostLabel) {
    let p = hostLabel;
    for (let i = 0; i < 4 && p; i++) p = p.parentElement;
    out.hostBlock = info(p);
    out.hostBlockKids = p ? [...p.children].slice(0, 6).map(info) : null;
  }

  // ---- 解锁页 ----
  menu.children[6].querySelector("[role=button]").click();
  await sleep(1000);
  const chips = [...document.querySelectorAll(".the-content .MuiChip-root")].slice(0, 8);
  out.unlockChips = chips.map((c) => {
    const label = c.querySelector(".MuiChip-label");
    return {
      cls: c.className.slice(0, 90),
      text: c.textContent.trim(),
      bg: getComputedStyle(c).backgroundColor,
      color: getComputedStyle(label || c).color,
      radius: getComputedStyle(c).borderTopLeftRadius,
      border: getComputedStyle(c).borderTopWidth + " " + getComputedStyle(c).borderTopColor,
    };
  });
  return JSON.stringify(out, null, 1);
})()
