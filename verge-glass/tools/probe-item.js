(() => {
  const card = document.getElementById("vg-card");
  const item = card.parentElement;
  const grid = item.parentElement;
  const ci = getComputedStyle(item);
  const cc = getComputedStyle(card);
  const cg = getComputedStyle(grid);
  return JSON.stringify({
    itemTag: item.tagName + "." + item.className,
    itemFlex: ci.flex,
    itemWidth: ci.width,
    itemRect: item.getBoundingClientRect().width,
    cardWidth: cc.width,
    cardDisplay: cc.display,
    cardPosition: cc.position,
    gridDisplay: cg.display,
    gridFlexWrap: cg.flexWrap,
    gridKids: [...grid.children].map((k) => k.className.slice(0, 40)),
    gridRect: grid.getBoundingClientRect().width,
    vw: innerWidth,
  });
})()
