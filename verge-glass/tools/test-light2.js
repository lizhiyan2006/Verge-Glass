(async () => {
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const segs = [...document.querySelectorAll("#vg-card .vg-seg button")];
  const light = segs.find((b) => b.textContent === "浅色");
  if (light) light.click();
  await sleep(1200);
  const ranges = [...document.querySelectorAll("#vg-card .vg-range")];
  const setVal = (input, v) => {
    const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value").set;
    setter.call(input, String(v));
    input.dispatchEvent(new Event("input", { bubbles: true }));
  };
  // 顺序：不透明度 / 毛玻璃 / 背景可见度 / 背景模糊 / 背景遮罩
  if (ranges[0]) setVal(ranges[0], 55);
  if (ranges[4]) setVal(ranges[4], 12);
  await sleep(500);
  return JSON.stringify({
    tone: document.documentElement.getAttribute("data-vg-tone"),
    bg: document.documentElement.getAttribute("data-vg-bg"),
    settings: window.__VERGE_GLASS__.settings,
  });
})()
