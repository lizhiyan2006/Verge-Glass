(() => {
  const s = document.getElementById("vg-preview");
  const root = document.querySelector(".MuiPaper-root.windows.layout");
  const before = getComputedStyle(document.body, "::before");
  const left = document.querySelector(".layout-content__left");
  return JSON.stringify({
    styleExists: !!s,
    styleLen: s ? s.textContent.length : 0,
    tone: document.documentElement.getAttribute("data-vg-tone"),
    varAlpha: getComputedStyle(document.documentElement).getPropertyValue("--vg-alpha"),
    varWall: getComputedStyle(document.documentElement).getPropertyValue("--vg-wallpaper").slice(0, 60),
    rootBg: root ? getComputedStyle(root).backgroundColor : null,
    bodyBg: getComputedStyle(document.body).backgroundColor,
    beforeBgImg: before.backgroundImage.slice(0, 90),
    beforeOpacity: before.opacity,
    leftBg: left ? getComputedStyle(left).backgroundColor : null,
  });
})()
