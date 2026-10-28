(async () => {
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const out = {};
  const card = document.getElementById("vg-card");
  out.card = !!card;
  const segs = [...document.querySelectorAll("#vg-card .vg-seg button")];
  out.segs = segs.map((b) => b.textContent);
  const light = segs.find((b) => b.textContent === "浅色");
  if (light) light.click();
  await sleep(1500);
  out.toneAfterLight = document.documentElement.getAttribute("data-vg-tone");
  out.appBgVar = getComputedStyle(document.documentElement).getPropertyValue("--background-color").trim();
  // set opacity slider to 32
  const ranges = [...document.querySelectorAll("#vg-card input[type=range]")];
  out.rangeCount = ranges.length;
  const setVal = (input, v) => {
    const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value").set;
    setter.call(input, String(v));
    input.dispatchEvent(new Event("input", { bubbles: true }));
  };
  if (ranges[0]) setVal(ranges[0], 32);
  await sleep(600);
  out.alphaVar = getComputedStyle(document.documentElement).getPropertyValue("--vg-alpha").trim();
  out.settings = JSON.parse(JSON.stringify(window.__VERGE_GLASS__.settings));
  return JSON.stringify(out);
})()
