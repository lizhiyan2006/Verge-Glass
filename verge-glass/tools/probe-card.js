(() => {
  const grids = [...document.querySelectorAll(".the-content .MuiGrid-container")].map((g) => ({
    cls: g.className.slice(0, 60),
    kids: g.children.length,
    hasCard: !!g.querySelector("#vg-card"),
  }));
  const card = document.getElementById("vg-card");
  return JSON.stringify({
    card: !!card,
    connected: card ? card.isConnected : null,
    parent: card && card.parentElement ? card.parentElement.className.slice(0, 60) : null,
    grids,
    path: location.pathname,
    enabled: !!window.__VERGE_GLASS__,
    settings: window.__VERGE_GLASS__ ? window.__VERGE_GLASS__.settings : null,
    baseContent: !!document.querySelector(".the-content .base-content"),
  });
})()
