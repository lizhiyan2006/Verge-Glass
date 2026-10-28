// Regression guard for the fork's window chrome:
//   * window must be frameless (no native frame)
//   * the window-control strip must be merged into the page header (not its own row)
//   * the chrome must not swallow header clicks and must not overlap page actions
//   * window corners stay rounded, background layers share the same radius
// Run: powershell -File tools\cdp-eval.ps1 -ScriptFile tools\probe-chrome.js
(async () => {
  const out = { ok: true, problems: [] };
  const fail = (m) => { out.ok = false; out.problems.push(m); };
  const html = document.documentElement;
  const rectOf = (e) => e.getBoundingClientRect();

  try {
    out.decorated = await window.__TAURI_INTERNALS__.invoke('plugin:window|is_decorated', { label: 'main' });
  } catch (e) { out.decorated = 'unknown'; }
  if (out.decorated === true) fail('window still has the native frame (decorated=true)');

  const tb = document.querySelector('.the_titlebar');
  if (!tb) fail('no .the_titlebar (frameless mode not active)');
  else {
    const cs = getComputedStyle(tb);
    out.titlebar = { height: cs.height, marginBottom: cs.marginBottom, bg: cs.backgroundColor, pointerEvents: cs.pointerEvents };
    if (cs.backgroundColor !== 'rgba(0, 0, 0, 0)') fail('title bar paints its own band instead of merging into the header');
    if (cs.pointerEvents !== 'none') fail('title bar overlay would swallow header clicks');
    if (parseFloat(cs.marginBottom) !== -parseFloat(cs.height)) fail('title bar still occupies a row of its own');
  }

  const header = document.querySelector('.the-content .base-page > header');
  if (!header) fail('no page header');
  else {
    const cs = getComputedStyle(header);
    out.header = { y: Math.round(rectOf(header).y), h: Math.round(rectOf(header).height), bg: cs.backgroundColor, padRight: cs.paddingRight };
    if (cs.backgroundColor === 'rgba(0, 0, 0, 0)') fail('page header does not paint the chrome glass');
    if (Math.round(rectOf(header).y) > 1) fail('page header does not start at the window top');
  }

  // window controls must sit to the right of the page action group
  if (tb && header && header.lastElementChild) {
    const ctrl = tb.lastElementChild;
    const group = header.lastElementChild;
    if (ctrl && group && rectOf(ctrl).width && rectOf(group).width) {
      const gap = Math.round(rectOf(ctrl).left - rectOf(group).right);
      out.controlsGap = gap;
      if (gap < 0) fail('window controls overlap the page action group by ' + (-gap) + 'px');
    }
  }

  // Windows-style controls: icon buttons, transparent until hovered, tooltip label
  if (tb) {
    const box = tb.querySelector('div:not(.the_titlebar-drag-region)');
    const btns = box ? [...box.querySelectorAll('button')] : [];
    if (btns.length !== 3) fail('expected 3 window buttons, found ' + btns.length);
    else {
      const cells = btns.map(b => {
        const cs = getComputedStyle(b);
        const svg = b.querySelector('svg');
        return { bg: cs.backgroundColor, w: cs.width, h: cs.height, svg: svg ? getComputedStyle(svg).display : 'none', label: b.getAttribute('data-vg-label') || '' };
      });
      out.buttons = cells;
      if (cells.some(c => c.svg === 'none')) fail('window button icons are hidden (Windows style keeps them visible)');
      if (cells.some(c => c.label === '')) fail('window buttons lost their hover labels');
      if (cells.some(c => parseFloat(c.w) < 30 || parseFloat(c.h) < 24)) fail('window buttons are too small for Windows style');
      if (box && getComputedStyle(box).backgroundColor !== 'rgba(0, 0, 0, 0)') fail('window buttons still sit in a visible frame');
    }
  }

  const layout = document.querySelector('.MuiPaper-root.layout');
  if (!layout) fail('no .layout');
  else {
    const cs = getComputedStyle(layout);
    const veil = getComputedStyle(document.body, '::after');
    const skin = getComputedStyle(document.body, '::before');
    out.layout = {
      radius: cs.borderTopLeftRadius,
      border: cs.borderTopWidth + ' ' + cs.borderTopStyle,
      veilRadius: veil.borderTopLeftRadius,
      skinRadius: skin.borderTopLeftRadius
    };
    if (parseFloat(cs.borderTopLeftRadius) < 20) fail('window corners are too small: ' + cs.borderTopLeftRadius);

    if (veil.borderTopLeftRadius !== cs.borderTopLeftRadius) fail('veil radius differs from window radius');
    if (skin.borderTopLeftRadius !== cs.borderTopLeftRadius) fail('background skin radius differs from window radius');
  }

  // 根元素必须按窗口圆角裁一刀：壁纸层带 transform:scale(1.025)（藏模糊软边用），
  // 它自己的圆角会被推到窗口外，四角就露出方形的一块壁纸（选「自选图片」时最明显）。
  const clip = getComputedStyle(html).clipPath;
  out.clip = clip;
  if (!clip || clip === 'none') fail('root has no clip-path: the wallpaper layer squares off the window corners');

  // 浅色模式：原生透明宿主不能再压一层近乎不透明的白纱，否则半透明在浅色下等于失效
  const prevTone = html.getAttribute('data-vg-tone');
  html.setAttribute('data-vg-tone', 'light');
  // body::after has a 0.25s background transition, so read it after it settles
  await new Promise((r) => setTimeout(r, 400));
  const veilLight = getComputedStyle(document.body, '::after').backgroundColor;
  if (prevTone) html.setAttribute('data-vg-tone', prevTone);
  const vm = /rgba?\(([\d.]+),\s*([\d.]+),\s*([\d.]+)(?:,\s*([\d.]+))?\)/.exec(veilLight);
  const vAlpha = vm ? (vm[4] === undefined ? 1 : parseFloat(vm[4])) : 1;
  out.veilLight = veilLight;
  if (vAlpha > 0.55) fail('light tone veil is nearly opaque (alpha ' + vAlpha + '): no translucency in light mode');

  if (html.getAttribute('data-vg-native') !== '1') fail('native mode attribute missing');
  return JSON.stringify(out);
})()
