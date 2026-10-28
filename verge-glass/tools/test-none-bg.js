(async () => {
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const menu = document.querySelector("ul.the-menu");
  menu.children[7].querySelector("[role=button]").click();
  await sleep(900);
  const segs = [...document.querySelectorAll("#vg-card .vg-seg button")];
  const dark = segs.find((b) => b.textContent === "深色");
  if (dark) dark.click();
  await sleep(1200);
  const ranges = [...document.querySelectorAll("#vg-card .vg-range")];
  const setVal = (input, v) => {
    const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value").set;
    setter.call(input, String(v));
    input.dispatchEvent(new Event("input", { bubbles: true }));
  };
  // 背景: 全透明 / 桌面壁纸 / 自选图片
  const none = segs.find((b) => b.textContent === "全透明");
  if (none) none.click();
  await sleep(800);
  if (ranges[0]) setVal(ranges[0], 50);
  if (ranges[4]) setVal(ranges[4], 40);
  await sleep(400);
  const state1 = { tone: document.documentElement.getAttribute("data-vg-tone"), bg: document.documentElement.getAttribute("data-vg-bg") };
  return JSON.stringify({ state1, settings: window.__VERGE_GLASS__.settings });
})()
