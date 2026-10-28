(() => {
  const btn = [...document.querySelectorAll("ul.the-menu .MuiListItemButton-root")]
    .find((b) => b.textContent.replace(/\s+/g, "").startsWith("首页"));
  if (!btn) return "not found";
  btn.click();
  return "home";
})()