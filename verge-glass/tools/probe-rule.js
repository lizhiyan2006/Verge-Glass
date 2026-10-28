(() => {
  const el = document.querySelector('.the-content .MuiBox-root.css-q2msz6');
  const out = {
    bg: el ? getComputedStyle(el).backgroundColor : null,
    alphaVar: getComputedStyle(document.documentElement).getPropertyValue('--vg-alpha'),
    baseVar: getComputedStyle(document.documentElement).getPropertyValue('--vg-base'),
    hasRule: false,
    ruleText: null,
  };
  const sheet = document.querySelector('style#verge-glass');
  if (sheet) {
    const txt = sheet.textContent;
    out.hasRule = txt.indexOf('.MuiGrid-root > .MuiBox-root') >= 0;
    const i = txt.indexOf('.MuiGrid-root > .MuiBox-root');
    out.ruleText = txt.slice(Math.max(0, i - 200), i + 300);
  }
  return JSON.stringify(out, null, 1);
})()
