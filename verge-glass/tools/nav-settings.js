(() => {
  const btn = [...document.querySelectorAll("ul.the-menu .MuiListItemButton-root")]
    .find((b) => b.textContent.replace(/\s+/g, "").startsWith("设置"));
  if (!btn) return "not found";
  btn.click();
  return "settings";
})()