(() => {
  const menu = document.querySelector("ul.the-menu");
  const items = [...(menu ? menu.children : [])].map((li) => ({
    tag: li.tagName,
    html: li.outerHTML.slice(0, 260).replace(/\s+/g, " "),
  }));
  const bar = document.querySelector(".the-bar");
  const content = document.querySelector(".the-content");
  return JSON.stringify({
    items,
    barHtml: bar ? bar.innerHTML.slice(0, 700) : null,
    contentFirstChildren: content ? [...content.children].map((c) => c.tagName + "." + (typeof c.className === "string" ? c.className : "")) : null,
  });
})()
