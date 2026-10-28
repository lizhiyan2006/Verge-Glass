(async () => {
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const out = {};
  const card = document.getElementById("vg-card");
  out.cards = document.querySelectorAll("#vg-card").length;
  const sw = card.querySelector(".vg-switch");
  // 1) 关闭插件
  sw.click();
  await sleep(700);
  out.afterOff = {
    switchOn: sw.getAttribute("data-on") === "1",
    cardStillThere: !!document.getElementById("vg-card"),
    stylePresent: !!document.getElementById("verge-glass"),
    toneAttr: document.documentElement.getAttribute("data-vg-tone"),
    status: document.querySelector("#vg-status") ? document.querySelector("#vg-status").textContent : "",
  };
  // 2) 再打开
  sw.click();
  await sleep(700);
  out.afterOn = {
    switchOn: sw.getAttribute("data-on") === "1",
    stylePresent: !!document.getElementById("verge-glass"),
    toneAttr: document.documentElement.getAttribute("data-vg-tone"),
  };
  return JSON.stringify(out);
})()
