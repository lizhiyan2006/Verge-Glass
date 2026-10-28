(() => {
  const card = document.getElementById("vg-card");
  const item = card ? card.parentElement : null;
  const grid = item ? item.parentElement : null;
  const cs = grid ? getComputedStyle(grid) : null;
  return JSON.stringify({
    itemClass: item ? item.className : null,
    gridClass: grid ? grid.className.slice(0, 80) : null,
    display: cs ? cs.display : null,
    gridTemplate: cs ? cs.gridTemplateColumns : null,
    gridKids: grid ? grid.children.length : 0,
    itemRect: item ? [item.getBoundingClientRect().width, item.getBoundingClientRect().height] : null,
    gridRect: grid ? [grid.getBoundingClientRect().width, grid.getBoundingClientRect().height] : null,
    itemStyle: item ? item.getAttribute("style") : null,
    vw: innerWidth,
    vh: innerHeight,
    dpr: devicePixelRatio,
  });
})()
