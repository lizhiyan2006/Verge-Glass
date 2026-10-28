(() => {
  const kind = (el) => el ? el.tagName.toLowerCase() + (el.id ? "#" + el.id : "") + (el.className && typeof el.className === "string" ? "." + el.className.trim().split(/\s+/).slice(0, 4).join(".") : "") : null;
  const outline = (el, depth) => {
    if (!el || depth > 4) return null;
    return { k: kind(el), n: el.children.length, c: [...el.children].slice(0, 14).map((x) => outline(x, depth + 1)).filter(Boolean) };
  };
  const res = {
    bodyChildren: [...document.body.children].map((c) => outline(c, 0)),
    htmlAttrs: [...document.documentElement.attributes].map((a) => a.name + "=" + a.value),
    bodyAttrs: [...document.body.attributes].map((a) => a.name + "=" + a.value),
    styleTags: [...document.querySelectorAll("style")].map((s) => s.id || "(anon:" + s.textContent.length + ")"),
    navTexts: [...document.querySelectorAll("nav a, nav button, .MuiTab-root")].slice(0, 20).map((e) => e.textContent.trim()),
  };
  return JSON.stringify(res);
})()
