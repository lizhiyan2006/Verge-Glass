// List every element that could paint an opaque sheet over the window.
// Run: powershell -File tools\cdp-eval.ps1 -ScriptFile tools\probe-layers.js
(() => {
  const out = { tone: document.documentElement.getAttribute('data-vg-tone'), layers: [] };
  const W = innerWidth * innerHeight;
  const name = (e) => {
    if (!e) return 'null';
    let s = e.tagName.toLowerCase();
    if (e.id) s += '#' + e.id;
    const cls = (e.className && typeof e.className === 'string' ? e.className : '').trim().split(/\s+/).filter(Boolean).slice(0, 4);
    if (cls.length) s += '.' + cls.join('.');
    return s;
  };
  const walk = (el, depth) => {
    for (const c of el.children) {
      if (c.id === 'vg-ui' || c.closest('#vg-ui')) { continue; }
      const cs = getComputedStyle(c);
      const r = c.getBoundingClientRect();
      const area = r.width * r.height;
      const bg = cs.backgroundColor;
      const m = /rgba?\(([\d.]+),\s*([\d.]+),\s*([\d.]+)(?:,\s*([\d.]+))?\)/.exec(bg);
      const a = m ? (m[4] === undefined ? 1 : parseFloat(m[4])) : 0;
      const isSheet = area > W * 0.25 && (a > 0.02 || cs.backgroundImage !== 'none');
      if (isSheet) {
        out.layers.push({
          el: name(c), d: depth, area: Math.round(area / W * 100) + '%',
          bg: bg, img: cs.backgroundImage === 'none' ? '-' : cs.backgroundImage.slice(0, 40),
          op: cs.opacity, bf: cs.backdropFilter, radius: cs.borderTopLeftRadius, ov: cs.overflow
        });
      }
      if (depth < 7) walk(c, depth + 1);
    }
  };
  const html = document.documentElement, body = document.body;
  out.html = { bg: getComputedStyle(html).backgroundColor, img: getComputedStyle(html).backgroundImage.slice(0, 30) };
  out.body = { bg: getComputedStyle(body).backgroundColor, img: getComputedStyle(body).backgroundImage.slice(0, 30) };
  const b4 = getComputedStyle(body, '::before'), af = getComputedStyle(body, '::after');
  out.before = { bg: b4.backgroundColor, img: b4.backgroundImage.slice(0, 60), op: b4.opacity, blur: b4.filter, radius: b4.borderTopLeftRadius, z: b4.zIndex };
  out.after = { bg: af.backgroundColor, op: af.opacity, radius: af.borderTopLeftRadius, z: af.zIndex };
  out.vars = {
    alpha: getComputedStyle(html).getPropertyValue('--vg-alpha'),
    contentAlpha: getComputedStyle(html).getPropertyValue('--vg-content-alpha'),
    base: getComputedStyle(html).getPropertyValue('--vg-base'),
    veil: getComputedStyle(html).getPropertyValue('--vg-veil'),
    wall: getComputedStyle(html).getPropertyValue('--vg-wallpaper').slice(0, 40)
  };
  walk(body, 1);
  return JSON.stringify(out, null, 1);
})()
