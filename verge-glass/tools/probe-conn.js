(async () => {
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const menu = document.querySelector("ul.the-menu");
  menu.children[3].querySelector("[role=button]").click();
  await sleep(1000);
  const page = document.querySelector(".the-content .base-page");
  const text = (el, n) => (el ? el.outerHTML.replace(/\s+/g, " ").slice(0, n) : null);
  const findText = (t) => [...document.querySelectorAll(".the-content *")].find((e) => e.children.length === 0 && e.textContent.trim() === t);
  const active = findText("活跃");
  const closed = findText("已关闭");
  const out = {
    active: active ? { tag: active.tagName, cls: active.className.slice(0, 90), parent: text(active.parentElement, 420) } : null,
    closed: closed ? { tag: closed.tagName, cls: closed.className.slice(0, 90) } : null,
  };
  // 表格行
  const host = findText("主机");
  if (host) {
    let p = host;
    for (let i = 0; i < 6; i++) p = p.parentElement;
    out.tableBlock = text(p, 900);
  }
  return JSON.stringify(out, null, 1);
})()
