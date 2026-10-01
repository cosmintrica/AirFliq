/* AirFliq — film v6. Every pixel is code: vector UI, SVG icons, canvas FX.
 * FILM.renderAt(t) seeks one paused GSAP timeline and redraws the procedural
 * layers from t alone, so every frame is deterministic. */
'use strict';
const W = 1920, H = 1080, FPS = 60, DUR = 62.0;
const $ = (s, r = document) => r.querySelector(s);
const stage = $('#stage');
const ZOOM = parseFloat(new URLSearchParams(location.search).get('zoom') || '1');
if (ZOOM !== 1) stage.style.zoom = String(ZOOM);

// ---------------------------------------------------------------- helpers
const el = (html) => { const t = document.createElement('template'); t.innerHTML = html.trim(); return t.content.firstElementChild; };
const add = (parent, html) => { const e = el(html); parent.appendChild(e); return e; };
const clamp = (v, a = 0, b = 1) => Math.min(b, Math.max(a, v));
const lerp = (a, b, t) => a + (b - a) * t;
const E = {
  outExpo: (t) => (t >= 1 ? 1 : 1 - Math.pow(2, -10 * t)),
  outCubic: (t) => 1 - Math.pow(1 - t, 3),
  inCubic: (t) => t * t * t,
  inOutCubic: (t) => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2),
  inOutSine: (t) => -(Math.cos(Math.PI * t) - 1) / 2,
  outBack: (t, s = 1.70158) => 1 + (s + 1) * Math.pow(t - 1, 3) + s * Math.pow(t - 1, 2),
};
const seg = (t, a, b) => clamp((t - a) / (b - a));
const rnd = (i) => { const x = Math.sin(i * 12.9898 + 78.233) * 43758.5453; return x - Math.floor(x); };
const bez = (p0, p1, p2, p3, u) => {
  const a = 1 - u;
  return [a * a * a * p0[0] + 3 * a * a * u * p1[0] + 3 * a * u * u * p2[0] + u * u * u * p3[0],
          a * a * a * p0[1] + 3 * a * a * u * p1[1] + 3 * a * u * u * p2[1] + u * u * u * p3[1]];
};

// ---------------------------------------------------------------- icons (SVG, 24 grid)
const S = 'fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"';
const ICON = {
  airdrop: `<circle cx="12" cy="13" r="2" fill="currentColor"/><path ${S} d="M8.2 16.8a5.4 5.4 0 1 1 7.6 0"/><path ${S} d="M5.4 19.6a9.4 9.4 0 1 1 13.2 0"/>`,
  clock: `<circle ${S} cx="12" cy="12" r="9"/><path ${S} d="M12 7v5l3 2"/>`,
  apps: `<rect ${S} x="4" y="4" width="6.5" height="6.5" rx="1.8"/><rect ${S} x="13.5" y="4" width="6.5" height="6.5" rx="1.8"/><rect ${S} x="4" y="13.5" width="6.5" height="6.5" rx="1.8"/><rect ${S} x="13.5" y="13.5" width="6.5" height="6.5" rx="1.8"/>`,
  desktop: `<rect ${S} x="3" y="4" width="18" height="12.5" rx="2"/><path ${S} d="M9 20h6M12 16.5V20"/>`,
  doc: `<path ${S} d="M7 3h7l4 4v14H7z"/><path ${S} d="M14 3v4h4"/>`,
  download: `<circle ${S} cx="12" cy="12" r="9"/><path ${S} d="M12 7.5v8M8.5 12.5 12 16l3.5-3.5"/>`,
  cloud: `<path ${S} d="M7.5 18.5h9.5a4 4 0 0 0 .4-8 6 6 0 0 0-11.5 1.4A3.4 3.4 0 0 0 7.5 18.5z"/>`,
  search: `<circle ${S} cx="10.5" cy="10.5" r="6"/><path ${S} d="m15 15 5 5"/>`,
  chevL: `<path ${S} d="m14.5 5.5-6.5 6.5 6.5 6.5"/>`,
  chevR: `<path ${S} d="m9.5 5.5 6.5 6.5-6.5 6.5"/>`,
  wifi: `<path ${S} d="M3.5 9.5a12 12 0 0 1 17 0"/><path ${S} d="M6.6 12.7a7.6 7.6 0 0 1 10.8 0"/><path ${S} d="M9.7 15.8a3.3 3.3 0 0 1 4.6 0"/><circle cx="12" cy="18.6" r="1.4" fill="currentColor"/>`,
  battery: `<rect ${S} x="2.5" y="7" width="17" height="10" rx="2.8"/><rect x="4.6" y="9.1" width="12.8" height="5.8" rx="1.2" fill="currentColor"/><path ${S} d="M22 10.5v3"/>`,
  gear: `<circle ${S} cx="12" cy="12" r="3.2"/><path ${S} d="M12 2.8v2.6M12 18.6v2.6M21.2 12h-2.6M5.4 12H2.8M18.5 5.5l-1.8 1.8M7.3 16.7l-1.8 1.8M18.5 18.5l-1.8-1.8M7.3 7.3 5.5 5.5"/>`,
  info: `<circle ${S} cx="12" cy="12" r="9"/><path ${S} d="M12 11v6"/><circle cx="12" cy="7.6" r="1.3" fill="currentColor"/>`,
  power: `<path ${S} d="M12 3v8"/><path ${S} d="M6.7 6.6a8 8 0 1 0 10.6 0"/>`,
  keyboard: `<rect ${S} x="2.5" y="6" width="19" height="12" rx="2.5"/><path ${S} d="M6.5 10h.01M10 10h.01M14 10h.01M17.5 10h.01M8 14h8"/>`,
  dragcursor: `<path fill="currentColor" d="M5 3.5l11.5 8.2-5.4.9-2.3 5.2z"/><path ${S} d="M14 16h6M16 19.5h5M15 12.5h5"/>`,
  infinity: `<path ${S} d="M12 12c-2.2-3-4-4.5-6-4.5a4.5 4.5 0 0 0 0 9c2 0 3.8-1.5 6-4.5zm0 0c2.2 3 4 4.5 6 4.5a4.5 4.5 0 0 0 0-9c-2 0-3.8 1.5-6 4.5z"/>`,
  sparkles: `<path fill="currentColor" d="M10 2.5l1.7 5.1 5.1 1.7-5.1 1.7L10 16.1 8.3 11 3.2 9.3 8.3 7.6z"/><path fill="currentColor" d="M18 13l.9 2.6 2.6.9-2.6.9-.9 2.6-.9-2.6-2.6-.9 2.6-.9z"/>`,
  check: `<path fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round" d="m5 12.5 4.5 4.5L19 7.5"/>`,
  cloudslash: `<path ${S} d="M7.5 18.5h9.5a4 4 0 0 0 .4-8 6 6 0 0 0-11.5 1.4A3.4 3.4 0 0 0 7.5 18.5z"/><path ${S} d="M3.5 3.5l17 17"/>`,
  personx: `<circle ${S} cx="10" cy="8" r="3.6"/><path ${S} d="M3.5 19.5c.8-3.3 3.4-5.2 6.5-5.2 1.3 0 2.5.3 3.5.9"/><path ${S} d="m16 15 4.5 4.5M20.5 15 16 19.5"/>`,
  lock: `<rect ${S} x="5" y="10.5" width="14" height="10" rx="2.5"/><path ${S} d="M8 10.5V8a4 4 0 0 1 8 0v2.5"/>`,
  seal: `<path ${S} d="M12 2.8l2.4 1.7 2.9-.1.9 2.8 2.3 1.8-.9 2.8.9 2.8-2.3 1.8-.9 2.8-2.9-.1L12 21.2l-2.4-1.7-2.9.1-.9-2.8-2.3-1.8.9-2.8-.9-2.8 2.3-1.8.9-2.8 2.9.1z"/><path ${S} d="m8.6 12.2 2.3 2.3 4.6-4.8"/>`,
  iphone: `<rect ${S} x="7" y="2.8" width="10" height="18.4" rx="2.6"/><path ${S} d="M10.6 5.2h2.8"/>`,
  ipad: `<rect ${S} x="4.5" y="3" width="15" height="18" rx="2.4"/><circle cx="12" cy="18.4" r=".9" fill="currentColor"/>`,
  laptop: `<rect ${S} x="4.5" y="5" width="15" height="10.5" rx="1.6"/><path ${S} d="M2.5 18.5h19"/>`,
  arrowR: `<path ${S} d="M4 12h15M13.5 6.5 19 12l-5.5 5.5"/>`,
  plane: `<path fill="currentColor" d="M2.6 11.1 20.6 3.3c.62-.27 1.26.37.99.99L13.8 22.4c-.3.66-1.25.62-1.5-.06l-2.3-6.3-6.3-2.3c-.68-.25-.72-1.2-.06-1.5Z"/>`,
  trash: `<path ${S} d="M4.5 6.5h15M9.5 6.5V4.5h5v2M6.5 6.5l.9 13h9.2l.9-13"/>`,
  share: `<path ${S} d="M12 3v11M8 6.8 12 3l4 3.8"/><path ${S} d="M7.5 10.5H6v10h12v-10h-1.5"/>`,
  gift: `<rect ${S} x="3.5" y="8.5" width="17" height="12" rx="2"/><path ${S} d="M12 8.5v12M3.5 12.5h17M12 8.5c-1.5-4-6-4.5-6-2s3 2 6 2zm0 0c1.5-4 6-4.5 6-2s-3 2-6 2z"/>`,
};
const icon = (name, size = 24, extra = '') => `<svg width="${size}" height="${size}" viewBox="0 0 24 24" ${extra}>${ICON[name]}</svg>`;

// macOS arrow cursor
const CURSOR = `<svg width="30" height="40" viewBox="0 0 15 21" style="filter:drop-shadow(0 2px 3px rgba(0,0,0,.45))"><path d="M1 1v15.6l3.9-3.7 2.8 6.4 2.7-1.2-2.8-6.3h5.4z" fill="#000" stroke="#fff" stroke-width="1.15" stroke-linejoin="round"/></svg>`;

// AirFliq's app icon, ported 1:1 from AirDropIcon.drawAppIcon.
let iconSerial = 0;
function appIcon(size) {
  const id = 'ai' + iconSerial++;
  return `<svg width="${size}" height="${size}" viewBox="0 0 100 100">
  <defs>
    <clipPath id="${id}c"><rect width="100" height="100" rx="23"/></clipPath>
    <linearGradient id="${id}g" x1="10" y1="0" x2="90" y2="100" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#6FD6FF"/><stop offset=".52" stop-color="#2B6BFF"/><stop offset="1" stop-color="#6A21D6"/></linearGradient>
    <linearGradient id="${id}s" x1="50" y1="0" x2="50" y2="100" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#fff" stop-opacity=".26"/><stop offset=".38" stop-color="#fff" stop-opacity=".03"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></linearGradient>
    <linearGradient id="${id}v" x1="50" y1="0" x2="50" y2="100" gradientUnits="userSpaceOnUse"><stop offset=".5" stop-color="#000" stop-opacity="0"/><stop offset="1" stop-color="#000" stop-opacity=".26"/></linearGradient>
    <filter id="${id}f" x="-30%" y="-30%" width="160%" height="160%"><feDropShadow dx="-1.5" dy="3.5" stdDeviation="3.2" flood-color="#050a33" flood-opacity=".45"/></filter>
  </defs>
  <g clip-path="url(#${id}c)">
    <rect width="100" height="100" fill="url(#${id}g)"/><rect width="100" height="100" fill="url(#${id}s)"/><rect width="100" height="100" fill="url(#${id}v)"/>
    <g transform="rotate(17 54 50)">
      <rect x="16.2" y="42.2" width="33.6" height="41.6" rx="6.4" fill="#fff" fill-opacity=".15"/>
      <rect x="26.1" y="32.6" width="37.8" height="46.8" rx="7.2" fill="#fff" fill-opacity=".32"/>
      <rect x="37" y="23" width="42" height="52" rx="8" fill="#fff" filter="url(#${id}f)"/>
      <rect x="44" y="31" width="28" height="18" rx="4" fill="#2F6BFF" fill-opacity=".5"/>
      <rect x="44" y="54" width="28" height="4.5" rx="2.25" fill="#2F6BFF" fill-opacity=".28"/>
      <rect x="44" y="62" width="17" height="4.5" rx="2.25" fill="#2F6BFF" fill-opacity=".28"/>
    </g>
  </g></svg>`;
}
// The menu bar glyph, ported from AirDropIcon.drawGlyph.
const GLYPH = `<svg width="24" height="24" viewBox="0 0 100 100"><rect x="4" y="40" width="20" height="8" rx="4" fill="currentColor"/><rect x="11" y="59" width="17" height="8" rx="4" fill="currentColor"/><rect x="40" y="22" width="44" height="56" rx="9" fill="none" stroke="currentColor" stroke-width="8" transform="rotate(17 60 50)"/></svg>`;

// Paper plane: a dart pointing right, 124 × 76.
let planeSerial = 0;
function planeSVG() {
  const id = 'pl' + planeSerial++;
  return `<svg width="124" height="76" viewBox="0 0 124 76">
  <defs>
    <linearGradient id="${id}u" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#FFFFFF"/><stop offset="1" stop-color="#C9EEFF"/></linearGradient>
    <linearGradient id="${id}l" x1="0" y1="1" x2="1" y2="0"><stop offset="0" stop-color="#7D47FF"/><stop offset=".5" stop-color="#1A7AFF"/><stop offset="1" stop-color="#2ED1FF"/></linearGradient>
  </defs>
  <polygon points="0,2 124,38 30,38" fill="url(#${id}u)"/>
  <polygon points="30,38 124,38 0,74" fill="url(#${id}l)"/>
  <polygon points="30,38 124,38 44,46" fill="#000" fill-opacity=".18"/>
  <line x1="30" y1="38" x2="124" y2="38" stroke="#fff" stroke-width="1.6" stroke-opacity=".95"/>
</svg>`;
}

// Document icons drawn in CSS: page, folded corner, lines and a type tag.
function docIcon(tag, color, scale = 1) {
  return `<div class="doc" style="transform:scale(${scale});transform-origin:50% 50%">
    <div class="pg"></div><div class="fold"></div>
    <div class="ln" style="top:30%;width:60%"></div><div class="ln" style="top:40%;width:72%"></div><div class="ln" style="top:50%;width:52%"></div>
    <div class="tag" style="background:${color}">${tag}</div></div>`;
}
// A list-size document icon: page, folded corner and a colored type band.
function miniDoc(color, w = 24) {
  return `<svg width="${w}" height="${Math.round(w * 1.3)}" viewBox="0 0 24 31" style="display:block;flex:none">
    <path d="M3 1h13l7 7v20a2 2 0 0 1-2 2H3a2 2 0 0 1-2-2V3a2 2 0 0 1 2-2z" fill="#F5F7FB"/>
    <path d="M16 1v5.2A1.8 1.8 0 0 0 17.8 8H23z" fill="#C3C9D6"/>
    <rect x="5" y="11" width="12" height="1.6" rx=".8" fill="#CDD3DE"/><rect x="5" y="14.4" width="9" height="1.6" rx=".8" fill="#CDD3DE"/>
    <rect x="4" y="20.5" width="16" height="6" rx="1.6" fill="${color}"/></svg>`;
}
const folderIcon = () => `<div class="folder"><div class="tab"></div><div class="back"></div><div class="front"></div></div>`;
const thumbIcon = (bg, inner = '') => `<div class="thumb" style="background:${bg}">${inner}</div>`;

// ---------------------------------------------------------------- stage skeleton
const bg = add(stage, `<div class="full" id="bg"></div>`);
const auroras = [
  add(bg, `<div class="aurora" style="width:1500px;height:1500px;background:radial-gradient(closest-side, rgba(26,122,255,.30), rgba(26,122,255,.08) 55%, rgba(26,122,255,0))"></div>`),
  add(bg, `<div class="aurora" style="width:1600px;height:1600px;background:radial-gradient(closest-side, rgba(125,71,255,.26), rgba(125,71,255,.07) 55%, rgba(125,71,255,0))"></div>`),
  add(bg, `<div class="aurora" style="width:1100px;height:1100px;background:radial-gradient(closest-side, rgba(46,209,255,.16), rgba(46,209,255,0))"></div>`),
];
const bgfx = add(stage, `<canvas class="fx" id="bgfx"></canvas>`);
const scenesRoot = add(stage, `<div class="full" id="scenes"></div>`);
const fx = add(stage, `<canvas class="fx" id="fx"></canvas>`);
const flash = add(stage, `<div class="full" id="flash"></div>`);
add(stage, `<div class="full" id="vignette"></div>`);

const RES = ZOOM * 1.0;
for (const c of [bgfx, fx]) { c.width = Math.round(W * RES); c.height = Math.round(H * RES); }
const g = fx.getContext('2d');
const gb = bgfx.getContext('2d');

const tl = gsap.timeline({ paused: true, defaults: { ease: 'expo.out' } });
const scene = (name) => add(scenesRoot, `<div class="full scene" id="${name}"><div class="full cam"></div><div class="full hud"></div></div>`);
const SCENES = [];
const show = (node, from, to) => {
  tl.set(node, { visibility: 'visible' }, from);
  tl.set(node, { visibility: 'hidden' }, to);
  SCENES.push({ cam: node.querySelector('.cam'), from, to });
};
// Canvas FX follow the active scene's camera, so trails stay glued to planes.
function applyCamera(t) {
  let cam = null;
  for (const sc of SCENES) if (t >= sc.from && t <= sc.to) cam = sc.cam;
  const s = cam ? gsap.getProperty(cam, 'scale') : 1;
  const tx = cam ? gsap.getProperty(cam, 'x') : 0;
  const ty = cam ? gsap.getProperty(cam, 'y') : 0;
  g.setTransform(s, 0, 0, s, RES * (960 * (1 - s) + tx), RES * (540 * (1 - s) + ty));
}

// Headline words that rise out of a mask, sharpening as they land.
function words(parent, x, y, text, cls, extra = '') {
  const line = add(parent, `<div class="abs ${cls}" style="left:${x}px;top:${y}px;${extra}"></div>`);
  const parts = text.split(' ').map((w) => {
    const m = w.match(/^\[(.*)\]$/);
    const word = m ? m[1] : w;
    const g2 = m ? ' grad' : '';
    const outer = add(line, `<span class="w"><span class="wi${g2}">${word}</span></span>`);
    line.appendChild(document.createTextNode(' '));
    return outer.firstElementChild;
  });
  return { line, parts };
}
function rise(parts, at, stagger = 0.07, dur = 0.9) {
  parts.forEach((p, i) => {
    tl.fromTo(p, { yPercent: 115, filter: 'blur(10px)', opacity: 0 },
      { yPercent: 0, filter: 'blur(0px)', opacity: 1, duration: dur, ease: 'expo.out' }, at + i * stagger);
  });
}
function sink(parts, at, dur = 0.45) {
  tl.to(parts, { yPercent: -110, opacity: 0, filter: 'blur(8px)', duration: dur, ease: 'power3.in', stagger: 0.03 }, at);
}

// ---------------------------------------------------------------- procedural flights
// Each flight: a plane element plus a route; drawn per frame from t.
const flights = [];
function flight(opt) {
  const node = add(opt.parent || scenesRoot, `<div class="abs" style="left:0;top:0;width:124px;height:76px;visibility:hidden;filter:drop-shadow(0 0 16px rgba(46,209,255,.85)) drop-shadow(0 0 4px rgba(255,255,255,.5))">${planeSVG()}</div>`);
  const f = Object.assign({ node, scale0: 1, scale1: 1, trail: true, sparks: true, ease: E.inOutCubic }, opt);
  flights.push(f);
  return f;
}
function flightPoint(f, u) {
  if (f.loop) {
    const { cx, cy, r, a0, a1 } = f.loop;
    // Spiral in: the radius closes on the last quarter so it dives to center.
    const k = clamp((u - 0.72) / 0.28);
    const rr = r * (1 - E.inCubic(k));
    const a = lerp(a0, a1, u);
    return [cx + Math.cos(a) * rr, cy + Math.sin(a) * rr * 0.62];
  }
  return bez(f.p[0], f.p[1], f.p[2], f.p[3], u);
}
function drawFlights(t) {
  for (const f of flights) {
    const visible = t >= f.t0 && t <= f.t1 + (f.hold || 0);
    const st = f.node.style;
    if (!visible) { st.visibility = 'hidden'; continue; }
    const u = f.ease(seg(t, f.t0, f.t1));
    const [x, y] = flightPoint(f, u);
    const [x2, y2] = flightPoint(f, Math.min(1, u + 0.004));
    const ang = Math.atan2(y2 - y, x2 - x);
    const sc = lerp(f.scale0, f.scale1, u) * (f.pop ? 1 + 0.18 * Math.sin(seg(t, f.t0, f.t0 + 0.35) * Math.PI) : 1);
    const fade = f.fadeOut ? 1 - seg(u, 0.86, 1) : 1;
    st.visibility = 'visible';
    st.opacity = String(fade * (f.fadeIn ? seg(t, f.t0, f.t0 + 0.08) : 1));
    st.transform = `translate(${x - 62}px, ${y - 38}px) rotate(${ang}rad) scale(${sc})`;
    if (f.trail) drawTrail(f, u, t);
    if (f.sparks) drawSparkTrail(f, t);
  }
}
function drawTrail(f, u, t) {
  const tail = Math.max(0, u - (f.trailLen || 0.28));
  if (u - tail < 0.002) return;
  const steps = 40;
  g.save();
  g.lineCap = 'round';
  for (let i = 0; i < steps; i++) {
    const a = tail + (u - tail) * (i / steps), b = tail + (u - tail) * ((i + 1) / steps);
    const [x1, y1] = flightPoint(f, a), [x2, y2] = flightPoint(f, b);
    const k = i / steps;
    if (i % 2 === 1) continue; // dashed
    g.strokeStyle = `rgba(${Math.round(lerp(125, 46, k))}, ${Math.round(lerp(71, 209, k))}, 255, ${0.9 * k})`;
    g.lineWidth = (1 + 3.2 * k) * RES;
    g.shadowColor = 'rgba(46,209,255,.9)';
    g.shadowBlur = 10 * RES;
    g.beginPath(); g.moveTo(x1 * RES, y1 * RES); g.lineTo(x2 * RES, y2 * RES); g.stroke();
  }
  g.restore();
}
function drawSparkTrail(f, t) {
  const n = 46;
  for (let i = 0; i < n; i++) {
    const u = i / n;
    // Time the plane passed u (inverse of the ease, sampled).
    let born = f.t0;
    for (let s = 0; s <= 40; s++) { const tt = f.t0 + (f.t1 - f.t0) * s / 40; if (f.ease(seg(tt, f.t0, f.t1)) >= u) { born = tt; break; } }
    const age = t - born;
    if (age < 0 || age > 0.65) continue;
    const p = age / 0.65;
    const [x, y] = flightPoint(f, u);
    const r = rnd(i + f.t0 * 100);
    const ang = r * Math.PI * 2;
    const d = 46 * E.outCubic(p) * (0.4 + r);
    const size = (3.2 * (1 - p) + 0.6) * RES;
    g.fillStyle = ['rgba(46,209,255,', 'rgba(255,255,255,', 'rgba(125,71,255,', 'rgba(26,122,255,'][i % 4] + (Math.pow(1 - p, 1.4)).toFixed(3) + ')';
    g.beginPath(); g.arc((x + Math.cos(ang) * d) * RES, (y + Math.sin(ang) * d + 14 * p * p) * RES, size, 0, Math.PI * 2); g.fill();
  }
}

// Bursts and shockwaves, also pure functions of t.
const bursts = [];
const burst = (t0, x, y, opt = {}) => bursts.push(Object.assign({ t0, x, y, n: 40, speed: 360, life: 0.9, ring: 1, hue: 'brand' }, opt));
function drawBursts(t) {
  for (const b of bursts) {
    const age = t - b.t0;
    if (age < 0 || age > Math.max(b.life, 0.8)) continue;
    // Shockwave rings
    for (let k = 0; k < b.ring; k++) {
      const a = age - k * 0.06;
      if (a < 0 || a > 0.7) continue;
      const p = a / 0.7;
      const r = (30 + E.outExpo(p) * (b.radius || 300) * (1 - k * 0.22)) * RES;
      g.strokeStyle = k === 0 ? `rgba(130,230,255,${0.95 * (1 - p)})` : `rgba(141,91,255,${0.8 * (1 - p)})`;
      g.lineWidth = (3.5 * (1 - p) + 0.6) * RES;
      g.beginPath(); g.arc(b.x * RES, b.y * RES, r, 0, Math.PI * 2); g.stroke();
    }
    if (age > b.life) continue;
    const p = age / b.life;
    for (let i = 0; i < b.n; i++) {
      const r = rnd(i * 7.3 + b.t0 * 13);
      const ang = (i / b.n) * Math.PI * 2 + r * 0.6;
      const d = E.outExpo(p) * b.speed * (0.35 + r * 0.9);
      const x = b.x + Math.cos(ang) * d, y = b.y + Math.sin(ang) * d * 0.86 + 40 * p * p;
      const size = (2 + r * 3.2) * (1 - p * 0.7) * RES;
      const col = b.hue === 'green' ? ['rgba(52,226,122,', 'rgba(170,255,200,', 'rgba(255,255,255,'][i % 3]
        : ['rgba(46,209,255,', 'rgba(255,255,255,', 'rgba(125,71,255,', 'rgba(26,122,255,'][i % 4];
      g.fillStyle = col + (1 - p).toFixed(3) + ')';
      g.shadowColor = col + '1)'; g.shadowBlur = 8 * RES;
      g.beginPath(); g.arc(x * RES, y * RES, size, 0, Math.PI * 2); g.fill();
    }
    g.shadowBlur = 0;
  }
}
const flashes = [];
const flashAt = (t0, strength = 0.8, len = 0.35) => flashes.push({ t0, strength, len });

// Background: drifting aurora and a slow star field.
function drawBackground(t) {
  const pos = [
    [420 + Math.sin(t * 0.21) * 160, 260 + Math.cos(t * 0.17) * 110],
    [1500 + Math.cos(t * 0.19) * 170, 820 + Math.sin(t * 0.15) * 120],
    [980 + Math.sin(t * 0.13 + 1) * 260, 540 + Math.cos(t * 0.11 + 2) * 160],
  ];
  auroras.forEach((a, i) => {
    const s = parseFloat(a.style.width);
    a.style.transform = `translate(${pos[i][0] - s / 2}px, ${pos[i][1] - s / 2}px)`;
  });
  gb.clearRect(0, 0, bgfx.width, bgfx.height);
  for (let i = 0; i < 140; i++) {
    const r1 = rnd(i), r2 = rnd(i + 500), r3 = rnd(i + 900);
    const x = ((r1 * W + t * (6 + r3 * 18)) % W);
    const y = r2 * H;
    const tw = 0.25 + 0.75 * (0.5 + 0.5 * Math.sin(t * (0.6 + r3) + i));
    gb.fillStyle = `rgba(${r3 > 0.6 ? '160,220,255' : '255,255,255'},${(0.06 + r3 * 0.22) * tw})`;
    gb.beginPath(); gb.arc(x * RES, y * RES, (0.6 + r3 * 1.3) * RES, 0, Math.PI * 2); gb.fill();
  }
}

// Cursor helper: a path of [t, x, y] keyframes, eased between them.
function cursorTrack(parent, keys, clicks = []) {
  const node = add(parent, `<div class="abs" style="left:0;top:0;visibility:hidden;z-index:50">${CURSOR}</div>`);
  const c = { node, keys, clicks };
  cursors.push(c);
  return c;
}
const cursors = [];
function drawCursors(t) {
  for (const c of cursors) {
    const k = c.keys;
    const st = c.node.style;
    if (t < k[0][0] || t > k[k.length - 1][0]) { st.visibility = 'hidden'; continue; }
    let i = 0; while (i < k.length - 2 && t > k[i + 1][0]) i++;
    const u = E.inOutCubic(seg(t, k[i][0], k[i + 1][0]));
    const x = lerp(k[i][1], k[i + 1][1], u), y = lerp(k[i][2], k[i + 1][2], u);
    // Hand-moved: a slight arc.
    const lift = Math.sin(u * Math.PI) * Math.min(40, Math.hypot(k[i + 1][1] - k[i][1], k[i + 1][2] - k[i][2]) * 0.08);
    let press = 1;
    for (const ct of c.clicks) { const a = t - ct; if (a >= 0 && a < 0.22) press = 1 - 0.14 * Math.sin(a / 0.22 * Math.PI); }
    st.visibility = 'visible';
    st.opacity = String(seg(t, k[0][0], k[0][0] + 0.15) * (1 - seg(t, k[k.length - 1][0] - 0.15, k[k.length - 1][0])));
    st.transform = `translate(${x - 3}px, ${y - lift - 3}px) scale(${press})`;
    // Click ripple
    for (const ct of c.clicks) {
      const a = t - ct; if (a < 0 || a > 0.45) continue;
      const p = a / 0.45;
      g.strokeStyle = `rgba(120,220,255,${0.9 * (1 - p)})`; g.lineWidth = 2.4 * RES;
      g.beginPath(); g.arc((x + 2) * RES, (y - lift + 2) * RES, (8 + 34 * E.outExpo(p)) * RES, 0, Math.PI * 2); g.stroke();
    }
  }
}

// ================================================================ S1  cold open (0–6)
const s1 = scene('s1'), c1 = $('.cam', s1);
show(s1, 0, 6.05);
const heroDoc = add(c1, `<div class="abs" style="left:912px;top:450px;width:96px;height:96px">${docIcon('PDF', '#E8473B')}</div>`);
const heroLabel = add(c1, `<div class="abs" style="left:760px;top:600px;width:400px;text-align:center;font:600 22px/1 'SFD';color:rgba(240,240,248,.9)">Launch Deck.pdf</div>`);
tl.fromTo(heroDoc, { scale: 1.6, opacity: 0 }, { scale: 2.2, opacity: 1, duration: 0.9 }, 0.05);
tl.fromTo(heroLabel, { opacity: 0, y: 14 }, { opacity: 1, y: 0, duration: 0.8 }, 0.25);
const e1 = add(c1, `<div class="abs eyebrow" style="left:120px;top:110px;color:rgba(232,238,255,.55)">Sending one file. The old way.</div>`);
tl.fromTo(e1, { opacity: 0, x: -16 }, { opacity: 1, x: 0, duration: 0.9 }, 0.2);

const chores = [
  { t: 1.0, x: 230, y: 200, r: -5, html: `<div class="menu" style="position:relative;width:250px"><div class="it">Copy</div><div class="it" style="background:var(--sys-blue);color:#fff">${icon('share', 18)} Share…</div><div class="it">Quick Look</div></div>` },
  { t: 1.5, x: 1290, y: 170, r: 4, html: `<div class="menu" style="position:relative;width:250px"><div class="it">Mail</div><div class="it">Messages</div><div class="it" style="background:var(--sys-blue);color:#fff">${icon('airdrop', 18)} AirDrop</div><div class="it">Notes</div></div>` },
  { t: 2.0, x: 1210, y: 640, r: -3, html: `<div class="menu" style="position:relative;width:330px;padding:18px"><div style="font:700 17px/1 'SFD'">AirDrop</div><div style="margin-top:14px;display:flex;gap:12px;align-items:center;color:rgba(235,235,245,.6);font:500 15px/1 'SFD'"><div class="spin"></div>Looking for devices…</div></div>` },
  { t: 2.5, x: 200, y: 650, r: 3, html: `<div class="menu" style="position:relative;width:300px;padding:16px"><div style="font:700 16px/1 'SFD'">Choose a device</div><div style="margin-top:14px;display:flex;gap:16px">${[0, 1, 2].map(() => '<div style="width:52px;height:52px;border-radius:50%;background:rgba(255,255,255,.1)"></div>').join('')}</div></div>` },
  { t: 3.0, x: 700, y: 90, r: -2, html: `<div class="menu" style="position:relative;width:320px;padding:16px"><div style="font:700 16px/1 'SFD'">Waiting…</div><div style="margin-top:12px;height:6px;border-radius:3px;background:rgba(255,255,255,.1)"><div style="width:30%;height:6px;border-radius:3px;background:rgba(255,255,255,.35)"></div></div></div>` },
  { t: 3.5, x: 1000, y: 830, r: 6, html: `<div style="position:relative;display:flex;align-items:center;gap:12px;font:800 44px/1 'SFD';color:rgba(255,255,255,.85)">${CURSOR}<span style="margin-left:6px">?</span></div>` },
];
const choreNodes = chores.map((c, i) => {
  const n = add(c1, `<div class="abs" style="left:${c.x}px;top:${c.y}px;transform-origin:0 0"><div style="transform:scale(1.45);transform-origin:0 0">${c.html}</div><div class="abs" style="left:-16px;top:-16px;width:36px;height:36px;border-radius:50%;background:linear-gradient(140deg,#2ED1FF,#7D47FF);display:flex;align-items:center;justify-content:center;font:800 17px/1 'SFD';color:#fff;box-shadow:0 6px 18px rgba(26,122,255,.5)">${i + 1}</div></div>`);
  tl.fromTo(n, { scale: 0.55, opacity: 0, rotation: c.r * 2.4, filter: 'blur(8px)' },
    { scale: 1, opacity: 1, rotation: c.r, filter: 'blur(0px)', duration: 0.42, ease: 'back.out(2.2)' }, c.t);
  return n;
});
// A spinner inside chore 3, drawn by CSS rotation.
document.querySelectorAll('.spin').forEach((s) => { s.style.cssText = 'width:18px;height:18px;border-radius:50%;border:2.5px solid rgba(255,255,255,.18);border-top-color:#fff'; tl.to(s, { rotation: 1080, duration: 3, ease: 'none' }, 2.0); });
// Camera nudges on every chore: the mess crowds in.
chores.forEach((c, i) => tl.fromTo(c1, { x: (i % 2 ? -7 : 7), y: (i % 3 ? 5 : -5) }, { x: 0, y: 0, duration: 0.35, ease: 'power2.out' }, c.t));
// Slam: "Too many clicks."
const slam = words(c1, 0, 470, 'Too many clicks.', 'mega', 'width:1920px;text-align:center');
tl.to([...choreNodes, heroDoc, heroLabel, e1], { opacity: 0.18, filter: 'blur(3px)', duration: 0.25, ease: 'power2.out' }, 3.98);
tl.fromTo(slam.line, { scale: 1.35, opacity: 0, filter: 'blur(18px)' }, { scale: 1, opacity: 1, filter: 'blur(0px)', duration: 0.32, ease: 'power4.out' }, 4.0);
flashAt(4.0, 0.35, 0.3);
// Shatter at 5.2: everything flies apart; the document stays for the fold.
choreNodes.forEach((n, i) => {
  const ang = Math.atan2(chores[i].y - 520, chores[i].x - 960);
  tl.to(n, { x: Math.cos(ang) * 900, y: Math.sin(ang) * 700, rotation: (i % 2 ? 1 : -1) * 50, opacity: 0, filter: 'blur(14px)', duration: 0.7, ease: 'power3.in' }, 5.2);
});
tl.to(slam.line, { scale: 1.5, opacity: 0, filter: 'blur(20px)', duration: 0.6, ease: 'power3.in' }, 5.2);
tl.to([heroDoc, heroLabel], { opacity: 1, filter: 'blur(0px)', duration: 0.4, ease: 'power2.out' }, 5.3);
tl.to(heroLabel, { opacity: 0, duration: 0.3 }, 5.75);
tl.to(e1, { opacity: 0, duration: 0.3 }, 5.2);

// ================================================================ S2  logo (6–12)
const s2 = scene('s2'), c2 = $('.cam', s2);
show(s2, 5.95, 12.05);
const doc2 = add(c2, `<div class="abs" style="left:912px;top:450px;width:96px;height:96px;transform-style:preserve-3d">${docIcon('PDF', '#E8473B')}</div>`);
tl.set(doc2, { scale: 2.2 }, 5.95);
tl.to(heroDoc, { opacity: 0, duration: 0.01 }, 6.0);
// Fold: the page flips edge-on and a paper plane flips out of it.
tl.to(doc2, { rotationY: 90, scale: 1.7, transformPerspective: 700, duration: 0.14, ease: 'power2.in' }, 6.18);
tl.set(doc2, { opacity: 0 }, 6.32);
flashAt(6.3, 0.18, 0.2);
const logoFlight = flight({ parent: c2, t0: 6.32, t1: 8.0, loop: { cx: 960, cy: 430, r: 330, a0: Math.PI * 0.0, a1: Math.PI * 2 * 1.35 }, scale0: 1.45, scale1: 0.5, trailLen: 0.22, pop: true, ease: E.inOutSine });
const logo = add(c2, `<div class="abs" style="left:830px;top:300px;width:260px;height:260px;filter:drop-shadow(0 30px 60px rgba(26,122,255,.45))">${appIcon(260)}</div>`);
const orbit = add(c2, `<svg class="abs" style="left:660px;top:130px" width="600" height="600" viewBox="0 0 600 600"><circle cx="300" cy="300" r="250" fill="none" stroke="rgba(46,209,255,.45)" stroke-width="2" stroke-dasharray="3 12"/><circle cx="300" cy="300" r="290" fill="none" stroke="rgba(125,71,255,.35)" stroke-width="1.6" stroke-dasharray="2 10"/></svg>`);
tl.fromTo(logo, { scale: 0.2, opacity: 0, rotation: -24 }, { scale: 1, opacity: 1, rotation: 0, duration: 0.9, ease: 'back.out(1.9)' }, 8.0);
tl.fromTo(orbit, { scale: 0.6, opacity: 0, rotation: 0 }, { scale: 1, opacity: 1, rotation: 40, duration: 1.4, ease: 'expo.out' }, 8.0);
tl.to(orbit, { rotation: 140, duration: 4, ease: 'none' }, 9.4);
burst(8.0, 960, 430, { n: 70, speed: 520, life: 1.1, ring: 2, radius: 420 });
flashAt(8.0, 0.75, 0.45);
const wordmark = words(c2, 0, 610, 'AirFliq', 'mega', 'width:1920px;text-align:center;font-size:150px');
rise(wordmark.parts, 8.25, 0, 1.0);
const tagline = words(c2, 0, 790, 'AirDrop [in] [one] [move.]', 'h2', 'width:1920px;text-align:center;font-size:58px;font-weight:700;color:rgba(240,244,255,.92)');
rise(tagline.parts, 9.0, 0.09);
tl.fromTo(c2, { scale: 1 }, { scale: 1.05, duration: 3, ease: 'none' }, 8.6);
tl.to([logo, orbit, wordmark.line, tagline.line], { opacity: 0, scale: 0.92, filter: 'blur(14px)', duration: 0.45, ease: 'power3.in' }, 11.55);

// ================================================================ S3  right-click (12–22)
const s3 = scene('s3'), c3 = $('.cam', s3), hud3 = $('.hud', s3);
show(s3, 11.95, 22.05);
const persp3 = add(c3, `<div class="full" style="perspective:2200px;perspective-origin:1200px 400px"></div>`);
const finder = add(persp3, `<div class="win" style="left:760px;top:190px;width:1040px;height:690px;transform-origin:50% 100%">
  <div class="side">
    <div class="lights"><i></i><i></i><i></i></div>
    <div class="sec" style="top:70px">Favorites</div>
    <div class="row" style="top:90px">${icon('airdrop', 18)} AirDrop</div>
    <div class="row" style="top:124px">${icon('clock', 18)} Recents</div>
    <div class="row" style="top:158px">${icon('apps', 18)} Applications</div>
    <div class="row" style="top:192px">${icon('desktop', 18)} Desktop</div>
    <div class="row on" style="top:226px">${icon('doc', 18)} Documents</div>
    <div class="row" style="top:260px">${icon('download', 18)} Downloads</div>
    <div class="sec" style="top:314px">Locations</div>
    <div class="row" style="top:334px">${icon('cloud', 18)} iCloud Drive</div>
  </div>
  <div class="tbar"><div class="nav">${icon('chevL', 16)}${icon('chevR', 16)}</div>Shipaton<div style="margin-left:auto;margin-right:22px;color:rgba(235,235,245,.5)">${icon('search', 18)}</div></div>
</div>`);
const grid = [
  { name: 'Launch Deck.pdf', html: docIcon('PDF', '#E8473B') },
  { name: 'Hero Shot.png', html: thumbIcon('linear-gradient(150deg,#FFB86B,#FF5F8F 45%,#7D47FF)', '<div style="position:absolute;left:18px;top:30px;width:30px;height:30px;border-radius:50%;background:rgba(255,255,255,.85)"></div>') },
  { name: 'Budget 2026.xlsx', html: docIcon('XLS', '#1F9D55') },
  { name: 'Cut 03.mov', html: thumbIcon('linear-gradient(160deg,#1B2440,#0B0F1E)', '<div style="position:absolute;left:34px;top:22px;width:0;height:0;border-left:24px solid rgba(255,255,255,.9);border-top:14px solid transparent;border-bottom:14px solid transparent"></div>') },
  { name: 'Notes.txt', html: docIcon('TXT', '#7A8091') },
  { name: 'Assets', html: folderIcon() },
];
const fileNodes = grid.map((f, i) => add(finder, `<div class="file" style="left:${274 + (i % 3) * 230}px;top:${110 + Math.floor(i / 3) * 230}px"><div class="ico">${f.html}</div><div class="nm">${f.name}</div></div>`));
const sel = add(finder, `<div class="abs" style="left:${274 + 18 - 8}px;top:${110 - 8}px;width:112px;height:112px;border-radius:14px;background:rgba(255,255,255,.12);opacity:0"></div>`);
const selName = add(finder, `<div class="abs" style="left:${274}px;top:${110 + 104}px;width:132px;text-align:center;opacity:0"><span style="display:inline-block;padding:3px 8px;border-radius:6px;background:var(--sys-blue);font:500 14.5px/1.15 'SFD';color:#fff">Launch Deck.pdf</span></div>`);
finder.insertBefore(sel, finder.querySelector('.file'));
tl.fromTo(finder, { y: 140, rotationX: 16, opacity: 0, scale: 0.94 }, { y: 0, rotationX: 0, opacity: 1, scale: 1, duration: 1.0, ease: 'expo.out' }, 12.0);
tl.to([sel, selName], { opacity: 1, duration: 0.12, ease: 'none' }, 13.25);
// File origin in stage coordinates (finder left 760 + item left + icon centre).
const docAt = [760 + 274 + 66, 190 + 110 + 48];
// Context menu at the cursor.
const menuX = 760 + 274 + 74, menuY = 190 + 110 + 52;
const rows = [
  ['Open'], ['Open With', '›'], '-', ['Move to Bin'], '-', ['Get Info'], ['Rename'], ['Compress “Launch Deck.pdf”'], ['Duplicate'], ['Make Alias'], ['Quick Look'], ['Copy'], '-',
  ['Share…'], '-', 'tags', ['Tags…'], '-', ['Quick Actions', '›'], ['fliq'],
];
let menuHTML = '<div class="hl"></div>';
const rowTop = {}; let yy = 6;
rows.forEach((r) => {
  if (r === '-') { menuHTML += '<div class="sp"></div>'; yy += 11; return; }
  if (r === 'tags') { menuHTML += `<div class="tags">${['#FF5F57', '#FF9F0A', '#FFD60A', '#30D158', '#0A84FF', '#BF5AF2', 'transparent'].map((c) => `<i style="background:${c};${c === 'transparent' ? 'box-shadow:inset 0 0 0 1.5px rgba(255,255,255,.5)' : ''}"></i>`).join('')}</div>`; yy += 30; return; }
  rowTop[r[0]] = yy;
  if (r[0] === 'fliq') menuHTML += `<div class="it fliq"><span style="display:inline-flex;width:20px;height:20px">${appIcon(20)}</span>Send with AirFliq</div>`;
  else menuHTML += `<div class="it">${r[0]}${r[1] ? `<span class="kb">${r[1]}</span>` : ''}</div>`;
  yy += 30;
});
const menu = add(c3, `<div class="menu" style="left:${menuX}px;top:${menuY}px">${menuHTML}</div>`);
const hl = $('.hl', menu);
tl.fromTo(menu, { opacity: 0, scale: 0.94 }, { opacity: 1, scale: 1, duration: 0.16, ease: 'power2.out' }, 13.5);
const hover = [[13.9, 'Copy'], [14.2, 'Share…'], [14.5, 'Quick Actions'], [14.72, 'fliq']];
hover.forEach(([t, name], i) => {
  tl.set(hl, { top: rowTop[name], opacity: 1 }, t);
});
tl.set(hl, { background: 'linear-gradient(90deg,#1A7AFF,#7D47FF)', boxShadow: '0 0 24px rgba(46,209,255,.55)' }, 14.72);
tl.to(hl, { opacity: 0.55, duration: 0.06, yoyo: true, repeat: 1, ease: 'none' }, 15.0);
tl.to(menu, { opacity: 0, duration: 0.18, ease: 'power2.in' }, 15.1);
cursorTrack(c3, [[12.4, 1720, 1010], [13.25, docAt[0] + 6, docAt[1] + 6], [13.5, docAt[0] + 8, docAt[1] + 4],
  [13.88, menuX + 60, menuY + rowTop['Copy'] + 15], [14.18, menuX + 70, menuY + rowTop['Share…'] + 15],
  [14.48, menuX + 80, menuY + rowTop['Quick Actions'] + 15], [14.7, menuX + 92, menuY + rowTop['fliq'] + 15],
  [15.05, menuX + 92, menuY + rowTop['fliq'] + 15], [15.35, menuX + 140, menuY + rowTop['fliq'] + 70]], [13.5, 15.0]);
// The file lifts out of Finder and folds into a plane.
const lift = add(c3, `<div class="abs" style="left:${docAt[0] - 48}px;top:${docAt[1] - 48}px;width:96px;height:96px;opacity:0;filter:drop-shadow(0 18px 30px rgba(0,0,0,.5))">${docIcon('PDF', '#E8473B')}</div>`);
tl.set(lift, { opacity: 1 }, 15.12);
tl.set(fileNodes[0], { opacity: 0.25 }, 15.12);
tl.to(lift, { scale: 1.45, y: -26, duration: 0.24, ease: 'back.out(2)' }, 15.12);
tl.to(lift, { rotationY: 90, scale: 1.1, transformPerspective: 700, duration: 0.13, ease: 'power2.in' }, 15.42);
tl.set(lift, { opacity: 0 }, 15.56);
burst(15.56, docAt[0], docAt[1] - 26, { n: 22, speed: 160, life: 0.55, ring: 1, radius: 120 });
// AirDrop sheet with real names, all vector.
const sheetX = 1090, sheetY = 300;
const peers = [
  { name: "Cosmin's iPhone", ic: 'iphone', ini: '' },
  { name: "Cosmin's iPad", ic: 'ipad', ini: '' },
  { name: 'MacBook Pro', ic: 'laptop', ini: '' },
];
const sheet = add(c3, `<div class="drop" style="left:${sheetX}px;top:${sheetY}px">
  <div class="hd"><div style="position:relative;width:78px;height:78px"><div style="position:absolute;left:-9px;top:-9px;transform:scale(.86);transform-origin:0 0">${docIcon('PDF', '#E8473B')}</div></div>
    <div><div class="t1">AirDrop</div><div class="t2">Launch Deck.pdf · 4.2 MB</div></div></div>
  <div class="div"></div>
  ${peers.map((p, i) => `<div class="peer" style="left:${44 + i * 190}px"><div class="av">${'<span>' + icon(p.ic, 44, 'style="color:#fff"') + '</span>'}</div><div class="nm">${p.name}</div><div class="st" id="st${i}">${i === 0 ? 'Nearby' : 'Nearby'}</div></div>`).join('')}
  <div class="ft"><div class="btn gray" style="right:28px;top:18px">Cancel</div></div>
</div>`);
const ring = add($('.peer .av', sheet), `<svg class="ring" viewBox="0 0 114 114"><circle cx="57" cy="57" r="53" fill="none" stroke="rgba(255,255,255,.12)" stroke-width="5"/><circle id="ringfg" cx="57" cy="57" r="53" fill="none" stroke="#2ED1FF" stroke-width="5" stroke-linecap="round" stroke-dasharray="333" stroke-dashoffset="333" transform="rotate(-90 57 57)" style="filter:drop-shadow(0 0 6px rgba(46,209,255,.9))"/></svg>`);
const badge = add($('.peer .av', sheet), `<div class="abs" style="right:-8px;bottom:-6px;width:40px;height:40px;border-radius:50%;background:linear-gradient(140deg,#7CF2A5,#22C55E);box-shadow:0 0 0 4px #2b2c33,0 6px 18px rgba(52,226,122,.6);display:flex;align-items:center;justify-content:center;color:#fff;opacity:0">${icon('check', 24)}</div>`);
const ringFg = $('#ringfg', ring);
tl.fromTo(finder, { scale: 1, opacity: 1, filter: 'blur(0px)' }, { scale: 0.9, opacity: 0.35, filter: 'blur(5px)', x: -260, duration: 0.9, ease: 'expo.inOut' }, 15.7);
tl.fromTo(sheet, { opacity: 0, scale: 0.86, y: 30 }, { opacity: 1, scale: 1, y: 0, duration: 0.7, ease: 'back.out(1.6)' }, 16.45);
flight({ parent: c3, t0: 15.56, t1: 16.55, p: [[docAt[0], docAt[1] - 26], [docAt[0] + 260, docAt[1] - 260], [sheetX - 120, sheetY - 120], [sheetX + 66, sheetY + 64]], scale0: 1.1, scale1: 0.35, trailLen: 0.3, ease: E.inOutCubic, fadeOut: true });
burst(16.5, sheetX + 66, sheetY + 64, { n: 26, speed: 140, life: 0.6, ring: 1, radius: 110 });
cursorTrack(c3, [[17.2, 1560, 900], [17.9, sheetX + 44 + 75, sheetY + 152 + 48], [18.4, sheetX + 44 + 75, sheetY + 152 + 48], [18.9, sheetX + 300, sheetY + 330]], [18.0]);
tl.to($('.peer .av', sheet), { scale: 0.93, duration: 0.08, yoyo: true, repeat: 1, ease: 'power2.inOut' }, 18.0);
tl.set('#st0', { textContent: 'Waiting…' }, 18.0);
tl.set('#st0', { textContent: 'Sending…' }, 18.6);
tl.to(ringFg, { strokeDashoffset: 0, duration: 1.42, ease: 'power1.inOut' }, 18.05);
tl.set(ringFg, { stroke: '#34E27A', filter: 'drop-shadow(0 0 8px rgba(52,226,122,.9))' }, 19.47);
tl.fromTo(badge, { scale: 0, opacity: 0 }, { scale: 1, opacity: 1, duration: 0.5, ease: 'back.out(3)' }, 19.5);
tl.set('#st0', { textContent: 'Sent', color: '#34E27A' }, 19.5);
burst(19.5, sheetX + 44 + 75, sheetY + 152 + 48, { n: 34, speed: 210, life: 0.8, ring: 1, radius: 160, hue: 'green' });
// Headline column.
const e3 = add(hud3, `<div class="abs eyebrow" style="left:130px;top:250px">Route 01 · Finder</div>`);
tl.fromTo(e3, { opacity: 0, x: -14 }, { opacity: 1, x: 0, duration: 0.8 }, 12.5);
const h3a = words(hud3, 124, 300, 'Right-click.', 'h1');
const h3b = words(hud3, 124, 420, '[Fliq.]', 'h1');
const h3c = words(hud3, 124, 540, 'Sent.', 'h1');
h3c.parts.forEach((p) => p.classList.add('gradg'));
rise(h3a.parts, 13.45, 0.08);
rise(h3b.parts, 14.98, 0.08);
rise(h3c.parts, 19.45, 0.08);
const sub3 = add(hud3, `<div class="abs lead" style="left:130px;top:690px;width:560px">The native AirDrop panel opens straight from Finder's menu.</div>`);
tl.fromTo(sub3, { opacity: 0, y: 16 }, { opacity: 1, y: 0, duration: 0.9 }, 16.6);
const camTo = (cam, at, dur, scale, fx, fy, ease = 'power3.inOut') => {
  // Keep focus point (fx, fy) under the same screen point while scaling.
  tl.to(cam, { scale, x: (960 - fx) * (scale - 1) * 1, y: (540 - fy) * (scale - 1) * 1, duration: dur, ease }, at);
};
tl.to(c3, { scale: 1.25, x: 70, y: -67, duration: 1.2, ease: 'power3.inOut' }, 13.45);
camTo(c3, 15.25, 0.9, 1.0, 960, 540);
camTo(c3, 16.9, 1.6, 1.22, sheetX + 320, sheetY + 200);
tl.to(c3, { scale: 1.34, filter: 'blur(12px)', opacity: 0, duration: 0.55, ease: 'power3.in' }, 21.45);
tl.to(hud3, { x: -60, filter: 'blur(10px)', opacity: 0, duration: 0.5, ease: 'power3.in' }, 21.45);

// ================================================================ shared components
// AirFliq's success toast, as in Toast.swift.
function toast(parent, x, y, title, subtitle) {
  return add(parent, `<div class="abs" style="left:${x}px;top:${y}px;width:560px;height:132px;border-radius:32px;opacity:0;
    background:linear-gradient(180deg,rgba(40,44,62,.96),rgba(26,28,42,.96));box-shadow:0 0 0 1.4px rgba(255,255,255,.14),0 30px 80px rgba(0,0,0,.55);
    display:flex;align-items:center;gap:24px;padding:0 30px">
    <div style="position:relative;width:70px;height:70px;flex:none">
      <svg width="70" height="70" viewBox="0 0 70 70"><circle cx="35" cy="35" r="32" fill="none" stroke="rgba(52,226,122,.22)" stroke-width="3"/>
      <circle class="tring" cx="35" cy="35" r="32" fill="none" stroke="#34E27A" stroke-width="3.4" stroke-linecap="round" stroke-dasharray="201" stroke-dashoffset="201" transform="rotate(-90 35 35)" style="filter:drop-shadow(0 0 5px rgba(52,226,122,.8))"/></svg>
      <div class="tchk" style="position:absolute;inset:0;display:flex;align-items:center;justify-content:center;color:#fff">${icon('check', 30)}</div>
    </div>
    <div><div style="font:750 27px/1.1 'SFR';letter-spacing:-.01em">${title}</div><div style="margin-top:8px;font:500 19px/1.2 'SFD';color:rgba(235,238,250,.62)">${subtitle}</div></div>
  </div>`);
}
function playToast(node, at) {
  tl.fromTo(node, { opacity: 0, x: 40, scale: 0.9 }, { opacity: 1, x: 0, scale: 1, duration: 0.6, ease: 'back.out(1.7)' }, at);
  tl.to($('.tring', node), { strokeDashoffset: 0, duration: 0.8, ease: 'power2.out' }, at + 0.1);
  tl.fromTo($('.tchk', node), { scale: 0.3, opacity: 0 }, { scale: 1, opacity: 1, duration: 0.5, ease: 'back.out(3)' }, at + 0.32);
}
// Compact AirDrop sheet used after the first route.
function miniSheet(parent, x, y) {
  const n = add(parent, `<div class="drop" style="left:${x}px;top:${y}px;width:470px;height:300px;opacity:0">
    <div class="hd" style="height:62px;top:22px"><div style="position:relative;width:62px;height:62px"><div style="position:absolute;left:-12px;top:-14px;transform:scale(.7);transform-origin:0 0">${docIcon('PDF', '#E8473B')}</div></div>
      <div><div class="t1" style="font-size:23px">AirDrop</div><div class="t2">Launch Deck.pdf</div></div></div>
    <div class="div" style="top:100px"></div>
    <div class="peer" style="left:40px;top:122px"><div class="av"><span>${icon('iphone', 44, 'style="color:#fff"')}</span>
      <svg class="ring" viewBox="0 0 114 114"><circle class="mring" cx="57" cy="57" r="53" fill="none" stroke="#2ED1FF" stroke-width="5" stroke-linecap="round" stroke-dasharray="333" stroke-dashoffset="333" transform="rotate(-90 57 57)"/></svg>
      <div class="mbadge abs" style="right:-8px;bottom:-6px;width:38px;height:38px;border-radius:50%;background:linear-gradient(140deg,#7CF2A5,#22C55E);box-shadow:0 0 0 4px #2b2c33;display:flex;align-items:center;justify-content:center;color:#fff;opacity:0">${icon('check', 22)}</div></div>
      <div class="nm">Cosmin's iPhone</div><div class="st mst">Nearby</div></div>
    <div class="peer" style="left:240px;top:122px"><div class="av"><span>${icon('ipad', 44, 'style="color:#fff"')}</span></div><div class="nm">Cosmin's iPad</div><div class="st">Nearby</div></div>
  </div>`);
  return n;
}
function playMiniSheet(n, at, clickAt) {
  tl.fromTo(n, { opacity: 0, scale: 0.86, y: 24 }, { opacity: 1, scale: 1, y: 0, duration: 0.55, ease: 'back.out(1.6)' }, at);
  tl.to($('.peer .av', n), { scale: 0.93, duration: 0.08, yoyo: true, repeat: 1 }, clickAt);
  tl.set($('.mst', n), { textContent: 'Sending…' }, clickAt);
  tl.to($('.mring', n), { strokeDashoffset: 0, duration: 0.85, ease: 'power1.inOut' }, clickAt + 0.05);
  tl.set($('.mring', n), { stroke: '#34E27A' }, clickAt + 0.9);
  tl.fromTo($('.mbadge', n), { scale: 0, opacity: 0 }, { scale: 1, opacity: 1, duration: 0.45, ease: 'back.out(3)' }, clickAt + 0.9);
  tl.set($('.mst', n), { textContent: 'Sent', color: '#34E27A' }, clickAt + 0.9);
}

// Card → paper plane morph: both outlines are eight cubic segments.
function morphPath(m, w, h, pw, ph) {
  const r = 30, k = r * 0.5523;
  const card = [
    [[0, r], [0, r - k], [r - k, 0], [r, 0]],
    [[r, 0], [r + (w - 2 * r) / 3, 0], [w - r - (w - 2 * r) / 3, 0], [w - r, 0]],
    [[w - r, 0], [w - r + k, 0], [w, r - k], [w, r]],
    [[w, r], [w, r + (h - 2 * r) / 3], [w, h - r - (h - 2 * r) / 3], [w, h - r]],
    [[w, h - r], [w, h - r + k], [w - r + k, h], [w - r, h]],
    [[w - r, h], [w - r - (w - 2 * r) / 3, h], [r + (w - 2 * r) / 3, h], [r, h]],
    [[r, h], [r - k, h], [0, h - r + k], [0, h - r]],
    [[0, h - r], [0, h - r - (h - 2 * r) / 3], [0, r + (h - 2 * r) / 3], [0, r]],
  ];
  const ox = (w - pw) / 2, oy = (h - ph) / 2;
  const P = (u, v) => [ox + u * pw, oy + v * ph];
  const L = (a, b) => [a, [a[0] + (b[0] - a[0]) / 3, a[1] + (b[1] - a[1]) / 3], [a[0] + 2 * (b[0] - a[0]) / 3, a[1] + 2 * (b[1] - a[1]) / 3], b];
  const tipT = P(0, 0.03), c0 = P(0.1, 0.18), up = P(0.7, 0.38), nose = P(1, 0.5), low = P(0.7, 0.62), tipB = P(0, 0.97), c7 = P(0.1, 0.82);
  const dart = [L(c0, tipT), L(tipT, up), L(up, nose), L(nose, nose), L(nose, low), L(low, tipB), L(tipB, c7), [c7, P(0.27, 0.56), P(0.27, 0.44), c0]];
  const mix = (a, b) => [lerp(a[0], b[0], m), lerp(a[1], b[1], m)];
  let d = '';
  for (let i = 0; i < 8; i++) {
    const s0 = card[i].map((pt, j) => mix(pt, dart[i][j]));
    if (i === 0) d += `M${s0[0][0].toFixed(2)} ${s0[0][1].toFixed(2)}`;
    d += `C${s0[1][0].toFixed(2)} ${s0[1][1].toFixed(2)} ${s0[2][0].toFixed(2)} ${s0[2][1].toFixed(2)} ${s0[3][0].toFixed(2)} ${s0[3][1].toFixed(2)}`;
  }
  return d + 'Z';
}
const morphs = [];

// ================================================================ S4  drag target (22–30)
const s4 = scene('s4'), c4 = $('.cam', s4), hud4 = $('.hud', s4);
show(s4, 21.95, 30.05);
const deskFiles = [
  { n: 'Launch Deck.pdf', h: docIcon('PDF', '#E8473B'), y: 180 },
  { n: 'Hero Shot.png', h: thumbIcon('linear-gradient(150deg,#FFB86B,#FF5F8F 45%,#7D47FF)'), y: 400 },
  { n: 'Notes.txt', h: docIcon('TXT', '#7A8091'), y: 620 },
];
const deskNodes = deskFiles.map((f) => add(c4, `<div class="file" style="left:1690px;top:${f.y}px"><div class="ico">${f.h}</div><div class="nm" style="text-shadow:0 1px 3px rgba(0,0,0,.6)">${f.n}</div></div>`));
deskNodes.forEach((n, i) => tl.fromTo(n, { opacity: 0, x: 40 }, { opacity: 1, x: 0, duration: 0.7 }, 22.05 + i * 0.07));
const pick = [1756, 228];
const ghost = add(c4, `<div class="abs" style="left:0;top:0;width:96px;height:96px;opacity:0;z-index:40;filter:drop-shadow(0 22px 30px rgba(0,0,0,.55))">${docIcon('PDF', '#E8473B')}</div>`);
const card4 = add(c4, `<div class="glass" style="left:700px;top:410px;width:500px;height:240px;opacity:0">
  <div class="conic" style="--a:0deg"></div>
  <canvas class="well" width="1000" height="480" style="position:absolute;left:0;top:0;width:500px;height:240px;border-radius:30px"></canvas>
  <div class="abs dockdoc" style="left:46px;top:62px;width:96px;height:96px;opacity:0">${docIcon('PDF', '#E8473B', 0.82)}</div>
  <div class="abs" style="left:58px;top:58px;width:124px;height:124px">${appIcon(124)}</div>
  <div class="abs t4a" style="left:212px;top:72px;font:780 40px/1.05 'SFR';letter-spacing:-.02em">Bring it here</div>
  <div class="abs t4b" style="left:212px;top:72px;font:780 40px/1.05 'SFR';letter-spacing:-.02em;opacity:0">Release to Fliq</div>
  <div class="abs t4c" style="left:214px;top:132px;font:500 22px/1.2 'SFD';color:rgba(235,238,250,.62)">AirFliq is following your drag</div>
  <div class="abs t4d" style="left:214px;top:132px;font:500 22px/1.2 'SFD';color:rgba(235,238,250,.62);opacity:0">Launch Deck.pdf</div>
</div>`);
const conic4 = $('.conic', card4);
const morph4 = add(c4, `<svg class="abs" style="left:700px;top:410px;overflow:visible;opacity:0" width="500" height="240" viewBox="0 0 500 240">
  <defs><linearGradient id="m4" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#FFFFFF"/><stop offset=".49" stop-color="#D2F1FF"/><stop offset=".51" stop-color="#2ED1FF"/><stop offset=".8" stop-color="#1A7AFF"/><stop offset="1" stop-color="#7D47FF"/></linearGradient></defs>
  <path class="mp" d="" fill="url(#m4)" stroke="#9BE7FF" stroke-width="2" style="filter:drop-shadow(0 0 18px rgba(46,209,255,.85))"/>
</svg>`);
morphs.push({ node: $('.mp', morph4), svg: morph4, t0: 25.52, t1: 25.8, w: 500, h: 240, pw: 248, ph: 152 });
// Timeline: pick up, drag, the target appears, attraction, release.
tl.set(ghost, { x: pick[0] - 48, y: pick[1] - 48 }, 22.4);
tl.to(ghost, { opacity: 0.92, scale: 1.08, duration: 0.15 }, 22.5);
tl.set(deskNodes[0], { opacity: 0.35 }, 22.5);
tl.to(ghost, { x: 1236 - 48, y: 600 - 48, duration: 1.5, ease: 'power2.inOut' }, 22.5);
tl.fromTo(card4, { opacity: 0, x: 60, scale: 0.8 }, { opacity: 1, x: 0, scale: 1, duration: 0.7, ease: 'back.out(1.6)' }, 23.0);
tl.to(ghost, { x: 700 + 46, y: 410 + 62, scale: 0.82, rotation: -12, opacity: 0, duration: 0.45, ease: 'power3.inOut' }, 24.0);
tl.to($('.dockdoc', card4), { opacity: 1, x: -14, rotation: -12, duration: 0.45, ease: 'back.out(1.8)' }, 24.15);
tl.to(card4, { scale: 1.045, duration: 0.4, ease: 'back.out(2)' }, 24.0);
tl.to(conic4, { opacity: 1, duration: 0.3 }, 24.0);
tl.fromTo(conic4, { '--a': '0deg' }, { '--a': '540deg', duration: 1.5, ease: 'none' }, 24.0);
tl.to($('.t4a', card4), { opacity: 0, y: -10, duration: 0.2 }, 24.0);
tl.fromTo($('.t4b', card4), { opacity: 0, y: 10 }, { opacity: 1, y: 0, duration: 0.3 }, 24.05);
tl.to($('.t4c', card4), { opacity: 0, duration: 0.2 }, 24.0);
tl.to($('.t4d', card4), { opacity: 1, duration: 0.3 }, 24.05);
cursorTrack(c4, [[22.2, 1600, 560], [22.5, pick[0] + 4, pick[1] + 6], [24.0, 1236, 600], [24.5, 1150, 590], [25.4, 1120, 585], [25.6, 1118, 586]], [22.5]);
// Release: squash, fold, boom.
tl.to(card4, { scale: 0.94, duration: 0.1, ease: 'power2.out' }, 25.5);
tl.to(card4, { opacity: 0, duration: 0.14, ease: 'power1.in' }, 25.56);
tl.set(morph4, { opacity: 1 }, 25.52);
tl.set(morph4, { opacity: 0 }, 25.81);
flashAt(25.8, 0.6, 0.4);
burst(25.8, 950, 530, { n: 60, speed: 480, life: 1.0, ring: 2, radius: 380 });
const f4 = flight({ parent: c4, t0: 25.8, t1: 26.5, p: [[950, 530], [1160, 470], [1500, 240], [2250, 40]], scale0: 2.0, scale1: 0.7, trailLen: 0.35, ease: (u) => 1 - Math.pow(1 - u, 2.2) });
const sheet4 = miniSheet(c4, 1180, 560);
playMiniSheet(sheet4, 26.55, 27.35);
cursorTrack(c4, [[26.9, 1500, 1000], [27.3, 1180 + 40 + 75, 560 + 122 + 48], [27.8, 1180 + 40 + 75, 560 + 122 + 48], [28.2, 1560, 980]], [27.35]);
const toast4 = toast(c4, 1300, 120, 'Sent with AirFliq', "Launch Deck.pdf → Cosmin's iPhone");
playToast(toast4, 28.35);
const e4 = add(hud4, `<div class="abs eyebrow" style="left:130px;top:250px">Route 02 · Drag target</div>`);
tl.fromTo(e4, { opacity: 0, x: -14 }, { opacity: 1, x: 0, duration: 0.8 }, 22.3);
const h4a = words(hud4, 124, 300, 'Drag.', 'h1');
const h4b = words(hud4, 124, 420, 'Drop.', 'h1');
const h4c = words(hud4, 124, 540, '[Gone.]', 'h1');
rise(h4a.parts, 22.95); rise(h4b.parts, 24.0); rise(h4c.parts, 25.8);
const sub4 = add(hud4, `<div class="abs lead" style="left:130px;top:690px;width:520px">AirFliq meets your file beside the cursor. Let go, and it folds into a flight.</div>`);
tl.fromTo(sub4, { opacity: 0, y: 16 }, { opacity: 1, y: 0, duration: 0.9 }, 23.4);
tl.to(c4, { scale: 1.1, filter: 'blur(12px)', opacity: 0, duration: 0.5, ease: 'power3.in' }, 29.5);
tl.to(hud4, { x: -60, filter: 'blur(10px)', opacity: 0, duration: 0.5, ease: 'power3.in' }, 29.5);
// Gravity well inside the card while the file is held over it.
const well = $('.well', card4).getContext('2d');
function drawWell(t) {
  well.clearRect(0, 0, 1000, 480);
  const on = t >= 24.0 && t <= 25.6;
  if (!on) return;
  const k = Math.min(1, (t - 24.0) / 0.3) * (1 - seg(t, 25.45, 25.6));
  const cx = 120 * 2, cy = 120 * 2;
  for (let i = 0; i < 18; i++) {
    const ang = (i / 18) * Math.PI * 2 + 0.3;
    const cyc = ((t * 1.3 + i * 0.37) % 1);
    const d = (1 - cyc) * 330 + 40;
    const hx = cx + Math.cos(ang) * d, hy = cy + Math.sin(ang) * d * 0.6;
    const tx = cx + Math.cos(ang) * (d + 34), ty = cy + Math.sin(ang) * (d + 34) * 0.6;
    well.strokeStyle = `rgba(46,209,255,${(0.55 * Math.sqrt(cyc) * k).toFixed(3)})`;
    well.lineWidth = 3; well.lineCap = 'round';
    well.beginPath(); well.moveTo(tx, ty); well.lineTo(hx, hy); well.stroke();
  }
}

// ================================================================ S5  shortcut (30–38)
const s5 = scene('s5'), c5 = $('.cam', s5), hud5 = $('.hud', s5);
show(s5, 29.95, 38.05);
const keys = [['⌃', 'control', 860], ['⌥', 'option', 1130], ['A', '', 1400]].map(([g1, label, x]) =>
  add(c5, `<div class="key" style="left:${x}px;top:400px;scale:1.32"><div class="glowring"></div><div class="base"></div><div class="cap"><b>${g1}</b>${label ? `<s>${label}</s>` : ''}</div></div>`));
keys.forEach((k, i) => tl.fromTo(k, { opacity: 0, y: 80, rotationX: 40, transformPerspective: 900 }, { opacity: 1, y: 0, rotationX: 0, duration: 0.8, ease: 'expo.out' }, 30.0 + i * 0.07));
[30.5, 31.0, 31.5].forEach((t, i) => {
  tl.to($('.cap', keys[i]), { y: 12, duration: 0.08, ease: 'power2.in' }, t);
  tl.to($('.glowring', keys[i]), { opacity: 1, duration: 0.1 }, t);
  if (i < 2) tl.to($('.cap', keys[i]), { y: 6, duration: 0.2 }, 31.6);
});
burst(31.55, 1310, 490, { n: 44, speed: 460, life: 0.9, ring: 2, radius: 420 });
tl.to(keys, { y: 220, opacity: 0, scale: 0.8, duration: 0.45, ease: 'power3.in', stagger: 0.04 }, 32.0);
const picker = add(c5, `<div class="win" style="left:780px;top:220px;width:960px;height:600px;opacity:0">
  <div class="side" style="width:200px"><div class="lights"><i></i><i></i><i></i></div>
    <div class="sec" style="top:70px">Favorites</div>
    <div class="row" style="top:90px">${icon('clock', 18)} Recents</div>
    <div class="row" style="top:124px">${icon('desktop', 18)} Desktop</div>
    <div class="row on" style="top:158px">${icon('doc', 18)} Documents</div>
    <div class="row" style="top:192px">${icon('download', 18)} Downloads</div></div>
  <div class="abs" style="left:224px;top:24px;font:700 17px/1 'SFD';color:rgba(245,245,250,.92)">Choose files or folders to share with AirDrop.</div>
  <div class="abs" style="left:200px;right:0;top:66px;height:1px;background:rgba(255,255,255,.07)"></div>
  <div class="abs" style="left:212px;right:14px;top:78px;height:26px;display:grid;grid-template-columns:40px 290px 110px 150px 1fr;align-items:center;padding-left:12px;font:600 13px/1 'SFD';color:rgba(235,235,245,.42)"><span></span><span>Name</span><span>Size</span><span>Kind</span><span>Date Added</span></div>
  ${[['Launch Deck.pdf', '4.2 MB', 'PDF document', '#E8473B'], ['Hero Shot.png', '2.1 MB', 'PNG image', '#7D47FF'], ['Budget 2026.xlsx', '88 KB', 'Spreadsheet', '#1F9D55'], ['Notes.txt', '3 KB', 'Plain text', '#7A8091']].map((r, i) => `
  <div class="abs prow" style="left:212px;right:14px;top:${110 + i * 46}px;height:42px;border-radius:9px;display:grid;grid-template-columns:40px 290px 110px 150px 1fr;align-items:center;padding-left:12px;font:500 15px/1 'SFD';color:rgba(245,245,250,.92)">
    <span style="display:flex;align-items:center">${miniDoc(r[3], 22)}</span><span>${r[0]}</span><span style="color:rgba(235,235,245,.55)">${r[1]}</span><span style="color:rgba(235,235,245,.55)">${r[2]}</span><span style="color:rgba(235,235,245,.55)">Today at 09:41</span></div>`).join('')}
  <div class="abs" style="left:200px;right:0;bottom:74px;height:1px;background:rgba(255,255,255,.07)"></div>
  <div class="btn gray" style="right:230px;bottom:18px">Cancel</div>
  <div class="btn blue pbtn" style="right:26px;bottom:18px">Send with AirDrop</div>
</div>`);
const prow0 = picker.querySelector('.prow');
tl.fromTo(picker, { opacity: 0, y: 60, scale: 0.92, rotationX: 10, transformPerspective: 1600 }, { opacity: 1, y: 0, scale: 1, rotationX: 0, duration: 0.8, ease: 'expo.out' }, 32.05);
tl.set(prow0, { background: 'var(--sys-blue)' }, 33.5);
tl.set(prow0.querySelectorAll('span'), { color: '#fff' }, 33.5);
tl.to($('.pbtn', picker), { scale: 0.94, duration: 0.08, yoyo: true, repeat: 1 }, 34.5);
cursorTrack(c5, [[32.9, 1500, 980], [33.45, 1080, 220 + 110 + 22], [33.6, 1084, 220 + 110 + 24], [34.45, 780 + 960 - 100, 220 + 600 - 38], [34.8, 780 + 960 - 96, 220 + 600 - 30]], [33.5, 34.5]);
tl.to(picker, { opacity: 0, scale: 0.9, filter: 'blur(8px)', duration: 0.35, ease: 'power3.in' }, 34.6);
burst(34.62, 1010, 352, { n: 26, speed: 200, life: 0.6, ring: 1, radius: 140 });
flight({ parent: c5, t0: 34.62, t1: 35.35, p: [[1010, 352], [1150, 260], [1500, 220], [1640, 250]], scale0: 1.0, scale1: 0.4, trailLen: 0.32, ease: (u) => 1 - Math.pow(1 - u, 2), fadeOut: true });
const toast5 = toast(c5, 1260, 180, 'Sent with AirFliq', "Launch Deck.pdf → Cosmin's iPhone");
playToast(toast5, 35.3);
const e5 = add(hud5, `<div class="abs eyebrow" style="left:130px;top:250px">Route 03 · Global shortcut</div>`);
tl.fromTo(e5, { opacity: 0, x: -14 }, { opacity: 1, x: 0, duration: 0.8 }, 30.2);
const h5a = words(hud5, 124, 300, 'One', 'h1');
const h5b = words(hud5, 124, 420, '[shortcut.]', 'h1');
const h5c = words(hud5, 124, 540, 'Anywhere.', 'h1');
rise(h5a.parts, 30.5); rise(h5b.parts, 31.0); rise(h5c.parts, 31.5);
const sub5 = add(hud5, `<div class="abs lead" style="left:130px;top:690px;width:520px">Press ⌃⌥A in any app, pick a file, and it's on its way.</div>`);
tl.fromTo(sub5, { opacity: 0, y: 16 }, { opacity: 1, y: 0, duration: 0.9 }, 32.2);
tl.to(c5, { scale: 1.08, filter: 'blur(12px)', opacity: 0, duration: 0.5, ease: 'power3.in' }, 37.5);
tl.to(hud5, { x: -60, filter: 'blur(10px)', opacity: 0, duration: 0.5, ease: 'power3.in' }, 37.5);

// ================================================================ S6  menu bar (38–44)
const s6 = scene('s6'), c6 = $('.cam', s6), hud6 = $('.hud', s6);
show(s6, 37.95, 44.05);
const mbar = add(c6, `<div class="mbar"><div class="l"><b>Finder</b><span>File</span><span>Edit</span><span>View</span><span>Go</span><span>Window</span><span>Help</span></div>
  <div class="r"><span class="gly" style="position:relative;display:inline-flex;padding:4px 8px;border-radius:7px;color:#fff">${GLYPH}</span>${icon('wifi', 22)}${icon('battery', 26)}<span>Thu 1 Oct&nbsp;&nbsp;9:41</span></div></div>`);
tl.fromTo(mbar, { y: -50 }, { y: 0, duration: 0.6, ease: 'expo.out' }, 38.0);
const gly = $('.gly', mbar);
tl.to(gly, { background: 'rgba(255,255,255,.18)', duration: 0.1 }, 39.0);
// Positions measured from the layout: the glyph sits left of wifi/battery/clock.
let glyX = 1540; const glyY = 20;
tl.fromTo(gly, { filter: 'drop-shadow(0 0 0 rgba(46,209,255,0))' }, { filter: 'drop-shadow(0 0 10px rgba(46,209,255,1))', duration: 0.3, yoyo: true, repeat: 1 }, 38.45);
const panel = add(c6, `<div class="abs" style="left:1210px;top:56px;width:540px;padding:22px;border-radius:34px;opacity:0;transform-origin:93% 0;
  background:linear-gradient(180deg,rgba(28,31,48,.97),rgba(16,18,30,.97));box-shadow:0 0 0 1.4px rgba(255,255,255,.14),0 40px 100px rgba(0,0,0,.6)">
  <div class="mrow" style="display:flex;align-items:center;gap:16px">${appIcon(56)}<div><div style="font:800 19px/1 'SFR';letter-spacing:.14em">AIRFLIQ</div><div style="margin-top:7px;font:500 16px/1 'SFD';color:rgba(235,238,250,.62)">5 of 5 free sends left today</div></div><div style="margin-left:auto;font:500 14px/1 'SFM';color:rgba(235,238,250,.35)">v1.0.1</div></div>
  <div class="mrow mbtn" style="margin-top:18px;height:84px;border-radius:20px;display:flex;align-items:center;gap:18px;padding:0 24px;background:linear-gradient(90deg,#1A7AFF,#5B6CFF 60%,#7D47FF);box-shadow:0 10px 30px rgba(26,122,255,.45);position:relative;overflow:hidden">
    ${icon('plane', 26, 'style="color:#fff"')}<div><div style="font:750 21px/1 'SFD'">Choose files to send…</div><div style="margin-top:7px;font:500 16px/1 'SFD';opacity:.8">Choose files, then open AirDrop</div></div><div style="margin-left:auto">${icon('arrowR', 24, 'style="color:#fff"')}</div>
    <div class="sheen" style="position:absolute;top:-20px;left:-120px;width:90px;height:140px;background:linear-gradient(90deg,transparent,rgba(255,255,255,.45),transparent);transform:rotate(18deg)"></div></div>
  <div class="mrow" style="margin-top:14px;height:76px;border-radius:20px;display:flex;align-items:center;gap:18px;padding:0 22px;background:rgba(125,71,255,.12);box-shadow:inset 0 0 0 1.2px rgba(125,71,255,.3)">
    <span style="color:#8D5BFF">${icon('infinity', 30)}</span><div><div style="font:750 19px/1 'SFD'">Lifetime Pro</div><div style="margin-top:7px;font:500 15px/1 'SFD';color:rgba(235,238,250,.6)">Unlimited forever, one purchase</div></div>
    <div style="margin-left:auto;display:flex;gap:6px">${'<i style="width:9px;height:9px;border-radius:50%;background:#2ED1FF;box-shadow:0 0 6px #2ED1FF;display:block"></i>'.repeat(5)}</div></div>
  ${[['dragcursor', 'Drag target', 'Meet every file beside your cursor', true], ['power', 'Launch at login', 'Keep AirFliq ready', false]].map(([ic, a, b, on]) => `
  <div class="mrow" style="margin-top:10px;height:70px;border-radius:18px;display:flex;align-items:center;gap:18px;padding:0 20px;background:rgba(255,255,255,.05);box-shadow:inset 0 0 0 1px rgba(255,255,255,.06)">
    <span style="color:${on ? '#2ED1FF' : 'rgba(235,238,250,.5)'}">${icon(ic, 24)}</span><div><div style="font:650 18px/1 'SFD'">${a}</div><div style="margin-top:6px;font:500 14.5px/1 'SFD';color:rgba(235,238,250,.55)">${b}</div></div>
    <div style="margin-left:auto;width:54px;height:30px;border-radius:15px;background:${on ? '#1A7AFF' : 'rgba(255,255,255,.14)'};position:relative"><i style="position:absolute;top:3px;${on ? 'right:3px' : 'left:3px'};width:24px;height:24px;border-radius:50%;background:#fff;display:block"></i></div></div>`).join('')}
  <div class="mrow" style="margin-top:10px;height:70px;border-radius:18px;display:flex;align-items:center;gap:18px;padding:0 20px;background:rgba(255,255,255,.05);box-shadow:inset 0 0 0 1px rgba(255,255,255,.06)">
    <span style="color:#2ED1FF">${icon('keyboard', 26)}</span><div><div style="font:650 18px/1 'SFD'">Global shortcut</div><div style="margin-top:6px;font:500 14.5px/1 'SFD';color:rgba(235,238,250,.55)">Presets or any custom combination</div></div>
    <div style="margin-left:auto;padding:8px 14px;border-radius:14px;background:rgba(26,122,255,.25);font:700 17px/1 'SFM'">⌃⌥A</div></div>
  <div class="mrow" style="margin-top:14px;display:flex;gap:10px">${[['gear', 'Setup'], ['info', 'About'], ['power', 'Quit']].map(([ic, a]) => `<div style="flex:1;height:52px;border-radius:26px;display:flex;align-items:center;justify-content:center;gap:10px;background:rgba(255,255,255,.05);box-shadow:inset 0 0 0 1px rgba(255,255,255,.06);font:650 17px/1 'SFD'">${icon(ic, 20)}${a}</div>`).join('')}</div>
</div>`);
tl.fromTo(panel, { opacity: 0, scale: 0.9, y: -16 }, { opacity: 1, scale: 1, y: 0, duration: 0.55, ease: 'back.out(1.5)' }, 39.0);
panel.querySelectorAll('.mrow').forEach((r, i) => tl.fromTo(r, { opacity: 0, y: -10 }, { opacity: 1, y: 0, duration: 0.45, ease: 'expo.out' }, 39.08 + i * 0.07));
tl.fromTo($('.sheen', panel), { x: 0 }, { x: 760, duration: 0.7, ease: 'power2.inOut' }, 40.55);
tl.to($('.mbtn', panel), { scale: 0.97, duration: 0.08, yoyo: true, repeat: 1 }, 41.2);
tl.to(panel, { opacity: 0, y: -20, scale: 0.96, duration: 0.3, ease: 'power3.in' }, 41.3);
const cur6 = cursorTrack(c6, [], [39.0, 41.2]);
function layoutMenuScene() {
  const sr = stage.getBoundingClientRect();
  const r = gly.getBoundingClientRect();
  glyX = (r.left + r.width / 2 - sr.left) / ZOOM;
  // The panel hangs from the status item, right-aligned to it like macOS.
  const left = Math.round(glyX + 34 - 540);
  panel.style.left = left + 'px';
  const btnY = 56 + 22 + 56 + 18 + 42;
  cur6.keys = [[38.3, 1180, 640], [38.95, glyX - 2, glyY - 2], [39.4, glyX, glyY], [40.5, left + 300, btnY],
    [41.2, left + 300, btnY], [41.5, left + 200, 600]];
  // Click the centre of "Send with AirDrop", measured from its laid-out box.
  const qb = $('.qbtn', quickPick);
  const qx = 820 + qb.offsetLeft + qb.offsetWidth * 0.5, qy = 300 + qb.offsetTop + qb.offsetHeight * 0.5;
  quickCur.keys = [[41.6, 1380, 640], [42.1, qx, qy], [42.5, qx + 3, qy + 2]];
}
// The click has a consequence: a file is picked and flies to AirDrop.
const quickPick = add(c6, `<div class="win" style="left:820px;top:300px;width:620px;height:300px;opacity:0">
  <div class="abs" style="left:28px;top:26px;font:700 17px/1 'SFD'">Choose files or folders to share with AirDrop.</div>
  <div class="abs" style="left:20px;right:20px;top:72px;height:46px;border-radius:10px;background:var(--sys-blue);display:flex;align-items:center;gap:14px;padding-left:14px;font:600 16px/1 'SFD';color:#fff">${miniDoc('#E8473B', 22)}<span>Launch Deck.pdf</span><span style="margin-left:auto;margin-right:16px;font-weight:500;opacity:.8">4.2 MB</span></div>
  <div class="abs" style="left:20px;right:20px;top:124px;height:46px;border-radius:10px;display:flex;align-items:center;gap:14px;padding-left:14px;font:500 16px/1 'SFD';color:rgba(235,235,245,.85)">${miniDoc('#7A8091', 22)}<span>Notes.txt</span><span style="margin-left:auto;margin-right:16px;color:rgba(235,235,245,.5)">3 KB</span></div>
  <div class="btn blue qbtn" style="right:24px;bottom:22px">Send with AirDrop</div></div>`);
tl.fromTo(quickPick, { opacity: 0, scale: 0.9, y: 30 }, { opacity: 1, scale: 1, y: 0, duration: 0.5, ease: 'back.out(1.6)' }, 41.45);
tl.to($('.qbtn', quickPick), { scale: 0.94, duration: 0.08, yoyo: true, repeat: 1 }, 42.15);
// Keys are set in layoutMenuScene() from the button's real box.
const quickCur = cursorTrack(c6, [[41.6, 1380, 640], [42.1, 1330, 556], [42.5, 1334, 559]], [42.15]);
tl.to(quickPick, { opacity: 0, scale: 0.92, filter: 'blur(8px)', duration: 0.3, ease: 'power3.in' }, 42.25);
flight({ parent: c6, t0: 42.3, t1: 42.95, p: [[880, 393], [1000, 300], [1350, 180], [1560, 170]], scale0: 0.9, scale1: 0.4, trailLen: 0.3, ease: (u) => 1 - Math.pow(1 - u, 2), fadeOut: true });
const toast6 = toast(c6, 1300, 120, 'Sent with AirFliq', "Launch Deck.pdf → Cosmin's iPhone");
playToast(toast6, 42.9);
const e6 = add(hud6, `<div class="abs eyebrow" style="left:130px;top:340px">Route 04 · Menu bar</div>`);
tl.fromTo(e6, { opacity: 0, x: -14 }, { opacity: 1, x: 0, duration: 0.8 }, 38.6);
const h6a = words(hud6, 124, 390, 'Always', 'h1');
const h6b = words(hud6, 124, 510, '[one] [click]', 'h1');
const h6c = words(hud6, 124, 630, 'away.', 'h1');
rise(h6a.parts, 39.4); rise(h6b.parts, 39.6); rise(h6c.parts, 39.8);
tl.to(c6, { scale: 1.08, filter: 'blur(12px)', opacity: 0, duration: 0.5, ease: 'power3.in' }, 43.5);
tl.to(hud6, { x: -60, filter: 'blur(10px)', opacity: 0, duration: 0.5, ease: 'power3.in' }, 43.5);

// ================================================================ S7  private (44–50)
const s7 = scene('s7'), c7 = $('.cam', s7), hud7 = $('.hud', s7);
show(s7, 43.95, 50.05);
const h7 = words(hud7, 0, 180, 'Private by [design.]', 'h1', 'width:1920px;text-align:center');
rise(h7.parts, 44.0, 0.08);
const cards7 = [['cloudslash', 'No uploads', "Files travel through Apple's AirDrop, never our servers."], ['personx', 'No account', 'Nothing to sign up for. Ever.'], ['lock', 'Your folders only', 'Access only to the folders you choose. No Full Disk Access.']];
const persp7 = add(c7, `<div class="full" style="perspective:1800px"></div>`);
const cardNodes7 = cards7.map(([ic, a, b], i) => add(persp7, `<div class="glass" style="left:${250 + i * 500}px;top:420px;width:440px;height:330px;padding:44px">
  <div style="width:84px;height:84px;border-radius:24px;display:flex;align-items:center;justify-content:center;background:linear-gradient(140deg,#2ED1FF,#1A7AFF 55%,#7D47FF);box-shadow:0 12px 30px rgba(26,122,255,.45);color:#fff">${icon(ic, 44)}</div>
  <div style="margin-top:34px;font:780 38px/1.05 'SFR';letter-spacing:-.02em">${a}</div>
  <div style="margin-top:14px;font:500 22px/1.35 'SFD';color:rgba(235,238,250,.62)">${b}</div>
  <div class="ok7 abs" style="right:34px;top:40px;width:48px;height:48px;border-radius:50%;background:linear-gradient(140deg,#7CF2A5,#22C55E);display:flex;align-items:center;justify-content:center;color:#fff;box-shadow:0 8px 22px rgba(52,226,122,.5);opacity:0">${icon('check', 28)}</div></div>`));
cardNodes7.forEach((n, i) => {
  tl.fromTo(n, { rotationY: -80, opacity: 0, x: -60, transformOrigin: '0% 50%' }, { rotationY: 0, opacity: 1, x: 0, duration: 0.8, ease: 'expo.out' }, 44.5 + i * 0.5);
  tl.fromTo($('.ok7', n), { scale: 0, opacity: 0 }, { scale: 1, opacity: 1, duration: 0.5, ease: 'back.out(3)' }, 46.0 + i * 0.25);
});
tl.fromTo(c7, { scale: 1 }, { scale: 1.04, duration: 5.5, ease: 'none' }, 44.3);
tl.to([c7, hud7], { filter: 'blur(12px)', opacity: 0, duration: 0.5, ease: 'power3.in' }, 49.5);

// ================================================================ S8  pricing (50–56)
const s8 = scene('s8'), c8 = $('.cam', s8), hud8 = $('.hud', s8);
show(s8, 49.95, 56.05);
const orb = add(c8, `<div class="abs" style="left:1210px;top:250px;width:560px;height:560px">
  <svg class="orbR" width="560" height="560" viewBox="0 0 560 560" style="position:absolute;inset:0"><circle cx="280" cy="280" r="250" fill="none" stroke="rgba(46,209,255,.5)" stroke-width="2.2" stroke-dasharray="4 13"/><circle cx="280" cy="280" r="205" fill="none" stroke="rgba(125,71,255,.55)" stroke-width="2" stroke-dasharray="3 10"/></svg>
  <svg class="orbC" width="560" height="560" viewBox="0 0 560 560" style="position:absolute;inset:0"><circle cx="280" cy="280" r="228" fill="none" stroke="url(#orbg)" stroke-width="4" stroke-linecap="round" stroke-dasharray="360 1100" style="filter:drop-shadow(0 0 10px rgba(46,209,255,.9))"/><defs><linearGradient id="orbg"><stop offset="0" stop-color="#2ED1FF" stop-opacity="0"/><stop offset="1" stop-color="#2ED1FF"/></linearGradient></defs></svg>
  <div style="position:absolute;left:130px;top:130px;width:300px;height:300px;border-radius:50%;background:radial-gradient(circle,rgba(26,122,255,.45),rgba(26,122,255,0) 70%)"></div>
  <div style="position:absolute;left:170px;top:170px;width:220px;height:220px;border-radius:50%;background:rgba(6,8,16,.55);box-shadow:inset 0 0 0 2px rgba(46,209,255,.55),0 0 60px rgba(46,209,255,.35);display:flex;align-items:center;justify-content:center">
    <svg width="130" height="130" viewBox="0 0 24 24"><defs><linearGradient id="infg" x1="0" x2="1"><stop offset="0" stop-color="#fff"/><stop offset=".5" stop-color="#2ED1FF"/><stop offset="1" stop-color="#8D5BFF"/></linearGradient></defs><path fill="none" stroke="url(#infg)" stroke-width="2.4" stroke-linecap="round" d="M12 12c-2.2-3-4-4.5-6-4.5a4.5 4.5 0 0 0 0 9c2 0 3.8-1.5 6-4.5zm0 0c2.2 3 4 4.5 6 4.5a4.5 4.5 0 0 0 0-9c-2 0-3.8 1.5-6 4.5z"/></svg></div></div>`);
tl.fromTo(orb, { scale: 0.5, opacity: 0, rotation: -30 }, { scale: 1, opacity: 1, rotation: 0, duration: 1.0, ease: 'back.out(1.5)' }, 50.0);
tl.fromTo($('.orbR', orb), { rotation: 0 }, { rotation: 90, duration: 6, ease: 'none' }, 50.0);
tl.fromTo($('.orbC', orb), { rotation: 0 }, { rotation: 720, duration: 6, ease: 'none' }, 50.0);
burst(50.0, 1490, 530, { n: 50, speed: 420, life: 1.0, ring: 2, radius: 380 });
flashAt(50.0, 0.4, 0.35);
const h8 = words(hud8, 124, 250, 'Start [free.]', 'mega');
tl.fromTo(h8.line, { scale: 1.25, opacity: 0, filter: 'blur(16px)', transformOrigin: '0% 50%' }, { scale: 1, opacity: 1, filter: 'blur(0px)', duration: 0.4, ease: 'power4.out' }, 50.0);
const chips8 = [['sparkles', '7-day unlimited trial'], ['infinity', 'Lifetime Pro · one purchase'], ['seal', 'No subscription']].map(([ic, a], i) =>
  add(hud8, `<div class="chip" style="left:130px;top:${470 + i * 100}px"><div class="dot">${icon(ic, 26)}</div>${a}</div>`));
chips8.forEach((c, i) => tl.fromTo(c, { opacity: 0, x: -40, scale: 0.9 }, { opacity: 1, x: 0, scale: 1, duration: 0.6, ease: 'back.out(1.8)' }, 51.0 + i));
const rc = add(hud8, `<div class="abs cap" style="left:134px;top:790px">Powered by RevenueCat</div>`);
tl.fromTo(rc, { opacity: 0, y: 10 }, { opacity: 1, y: 0, duration: 0.8 }, 53.5);
tl.to([c8, hud8], { filter: 'blur(12px)', opacity: 0, duration: 0.5, ease: 'power3.in' }, 55.5);

// ================================================================ S9  finale (56–62)
const s9 = scene('s9'), c9 = $('.cam', s9), hud9 = $('.hud', s9);
show(s9, 55.95, 62.0);
flight({ parent: c9, t0: 56.0, t1: 57.0, p: [[-120, 1150], [300, 400], [700, 100], [960, 420]], scale0: 2.2, scale1: 0.7, trailLen: 0.4, ease: E.inOutCubic, fadeOut: true });
const logo9 = add(c9, `<div class="abs" style="left:820px;top:270px;width:280px;height:280px;filter:drop-shadow(0 40px 80px rgba(26,122,255,.5))">${appIcon(280)}</div>`);
const orbit9 = add(c9, `<svg class="abs" style="left:610px;top:60px" width="700" height="700" viewBox="0 0 700 700"><circle cx="350" cy="350" r="250" fill="none" stroke="rgba(46,209,255,.45)" stroke-width="2" stroke-dasharray="3 12"/><circle cx="350" cy="350" r="300" fill="none" stroke="rgba(125,71,255,.35)" stroke-width="1.6" stroke-dasharray="2 10"/></svg>`);
tl.fromTo(logo9, { scale: 0.2, opacity: 0, rotation: -30 }, { scale: 1, opacity: 1, rotation: 0, duration: 0.9, ease: 'back.out(1.9)' }, 57.0);
tl.fromTo(orbit9, { scale: 0.5, opacity: 0 }, { scale: 1, opacity: 1, rotation: 60, duration: 1.4, ease: 'expo.out' }, 57.0);
tl.to(orbit9, { rotation: 160, duration: 4, ease: 'none' }, 58.4);
burst(57.0, 960, 410, { n: 80, speed: 600, life: 1.2, ring: 3, radius: 520 });
flashAt(57.0, 0.85, 0.5);
const w9 = words(hud9, 0, 600, 'AirFliq', 'mega', 'width:1920px;text-align:center;font-size:140px');
rise(w9.parts, 57.35, 0, 1.0);
const t9 = words(hud9, 0, 770, 'Select. [Fliq.] Sent.', 'h2', 'width:1920px;text-align:center;font-size:56px');
rise(t9.parts, 58.0, 0.1);
const a9 = add(hud9, `<div class="abs" style="left:0;top:880px;width:1920px;text-align:center;font:600 26px/1 'SFD';color:rgba(235,238,250,.8)">Available on the Mac App Store &nbsp;·&nbsp; <span class="grad" style="font-weight:700">airfliq.vercel.app</span></div>`);
tl.fromTo(a9, { opacity: 0, y: 14 }, { opacity: 1, y: 0, duration: 0.9 }, 59.0);
const b9 = add(hud9, `<div class="abs cap" style="left:0;top:960px;width:1920px;text-align:center">Built for RevenueCat Shipaton 2026</div>`);
tl.fromTo(b9, { opacity: 0 }, { opacity: 1, duration: 0.9 }, 59.8);
tl.to([c9, hud9], { opacity: 0, duration: 0.6, ease: 'power2.in' }, 61.4);

// ================================================================ render
function drawFlashes(t) {
  let a = 0;
  for (const f of flashes) { const p = (t - f.t0) / f.len; if (p >= 0 && p <= 1) a = Math.max(a, f.strength * (1 - E.outCubic(p))); }
  flash.style.opacity = a.toFixed(3);
}
async function renderAt(t) {
  tl.seek(Math.min(t, DUR), false);
  g.setTransform(1, 0, 0, 1, 0, 0);
  g.clearRect(0, 0, fx.width, fx.height);
  applyCamera(t);
  drawBackground(t);
  for (const mo of morphs) {
    const m = E.inOutCubic(seg(t, mo.t0, mo.t1));
    mo.node.setAttribute('d', morphPath(m, mo.w, mo.h, mo.pw, mo.ph));
  }
  drawWell(t);
  drawFlights(t);
  drawBursts(t);
  drawCursors(t);
  drawFlashes(t);
}
window.FILM = { ready: false, duration: DUR, fps: FPS, renderAt, tl };
document.fonts.ready.then(async () => { layoutMenuScene(); await renderAt(0); window.FILM.ready = true; });
