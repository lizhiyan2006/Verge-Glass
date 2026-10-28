(() => {
  const info = (el) => {
    if (!el) return null;
    const cs = getComputedStyle(el);
    return {
      tag: el.tagName.toLowerCase(),
      cls: (typeof el.className === "string" ? el.className : "").slice(0, 120),
      bg: cs.backgroundColor,
      bgImg: cs.backgroundImage.slice(0, 40),
      radius: cs.borderTopLeftRadius + " / " + cs.borderBottomRightRadius,
      border: cs.borderTopWidth + " " + cs.borderTopColor,
      padding: cs.padding,
      opacity: cs.opacity,
    };
  };
  const byText = (t, tag) => {
    const all = [...document.querySelectorAll(tag || "*")];
    return all.find((e) => e.children.length === 0 && e.textContent.trim() === t);
  };
  const out = {};
  // 首页状态卡里的选项卡
  const sysProxy = byText("系统代理", "button") || byText("系统代理");
  out.sysProxyBtn = info(sysProxy);
  out.sysProxyBtnParent = sysProxy ? info(sysProxy.parentElement) : null;
  out.sysProxyBtnGrand = sysProxy ? info(sysProxy.parentElement.parentElement) : null;
  const vnic = byText("虚拟网卡模式", "button") || byText("虚拟网卡模式");
  out.vnicBtn = info(vnic);
  const rule = byText("规则", "button") || byText("规则");
  out.ruleBtn = info(rule);
  out.ruleBtnParent = rule ? info(rule.parentElement) : null;
  out.ruleBtnGrand = rule ? info(rule.parentElement.parentElement) : null;
  // 延迟 chip
  const chips = [...document.querySelectorAll(".MuiChip-root")].slice(0, 4);
  out.chips = chips.map(info);
  out.chipStyleAttr = chips[0] ? (chips[0].getAttribute("style") || "").slice(0, 160) : "";
  // 系统代理那一行
  const rowSwitch = document.querySelector('.the-content .MuiSwitch-root');
  out.switchRoot = info(rowSwitch);
  if (rowSwitch) {
    out.switchRow = info(rowSwitch.closest("li") || rowSwitch.parentElement.parentElement);
    out.switchTrack = info(document.querySelector('.the-content .MuiSwitch-track'));
  }
  return JSON.stringify(out, null, 1);
})()
