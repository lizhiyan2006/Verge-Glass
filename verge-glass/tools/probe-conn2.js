(() => {
  const rows = [...document.querySelectorAll(".the-content div")].filter((d) => d.style && d.style.backgroundColor && d.getBoundingClientRect().height > 20 && d.getBoundingClientRect().height < 60);
  const colors = rows.slice(0, 12).map((d) => ({ bg: d.style.backgroundColor, h: Math.round(d.getBoundingClientRect().height), kids: d.children.length }));
  // 活跃/已关闭 两个卡
  const chips = [...document.querySelectorAll(".the-content .MuiChip-root")].slice(0, 4).map((c) => {
    const cs = getComputedStyle(c);
    return { text: c.textContent.trim(), cls: c.className.slice(0, 70), bg: cs.backgroundColor, margin: cs.margin, gap: cs.gap };
  });
  const chipParent = document.querySelector(".the-content .MuiChip-root") ? document.querySelector(".the-content .MuiChip-root").parentElement : null;
  const pc = chipParent ? getComputedStyle(chipParent) : null;
  return JSON.stringify({
    rowColors: colors,
    chips,
    chipParent: chipParent ? { cls: chipParent.className.slice(0, 80), display: pc.display, gap: pc.gap, columnGap: pc.columnGap } : null,
  }, null, 1);
})()
