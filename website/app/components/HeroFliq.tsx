"use client";

import { useCallback, useEffect, useRef } from "react";

/*
 * The hero's opening move, rendered from code like the app itself:
 * a file is dragged onto AirFliq's glass target, the card squashes and
 * folds into a paper plane, and the plane flies to the Mac App Store
 * button in the navigation. The headline takes the stage it leaves.
 */

const N = 64; // points per outline, so the card can morph into the plane
type Pt = [number, number];

function resample(poly: Pt[], n: number): Pt[] {
  const lengths: number[] = [];
  let total = 0;
  for (let i = 0; i < poly.length; i++) {
    const a = poly[i];
    const b = poly[(i + 1) % poly.length];
    const d = Math.hypot(b[0] - a[0], b[1] - a[1]);
    lengths.push(d);
    total += d;
  }
  const out: Pt[] = [];
  let index = 0;
  let acc = 0;
  for (let k = 0; k < n; k++) {
    const target = (k / n) * total;
    while (acc + lengths[index] < target && index < lengths.length - 1) {
      acc += lengths[index];
      index++;
    }
    const a = poly[index];
    const b = poly[(index + 1) % poly.length];
    const t = lengths[index] === 0 ? 0 : (target - acc) / lengths[index];
    out.push([a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t]);
  }
  return out;
}

/** Rounded rectangle centred on 0,0, starting at the right middle, clockwise. */
function cardOutline(w: number, h: number, r: number): Pt[] {
  const pts: Pt[] = [];
  const hw = w / 2;
  const hh = h / 2;
  const arc = (cx: number, cy: number, from: number) => {
    for (let i = 0; i <= 8; i++) {
      const a = from + (i / 8) * (Math.PI / 2);
      pts.push([cx + Math.cos(a) * r, cy + Math.sin(a) * r]);
    }
  };
  pts.push([hw, 0]);
  arc(hw - r, hh - r, 0);
  arc(-hw + r, hh - r, Math.PI / 2);
  arc(-hw + r, -hh + r, Math.PI);
  arc(hw - r, -hh + r, (3 * Math.PI) / 2);
  return resample(pts, N);
}

/** Side view of a paper dart pointing right, nose first, clockwise. */
function planeOutline(): Pt[] {
  return resample(
    [
      [86, 0],
      [-58, 40],
      [-30, 0],
      [-58, -40],
    ],
    N,
  );
}

const CARD = cardOutline(360, 168, 46);
const PLANE = planeOutline();
const CARD_D = toPath(CARD);

function toPath(pts: Pt[]) {
  return `M${pts.map((p) => `${p[0].toFixed(1)},${p[1].toFixed(1)}`).join("L")}Z`;
}

const clamp = (v: number, a = 0, b = 1) => Math.min(b, Math.max(a, v));
const seg = (t: number, a: number, b: number) => clamp((t - a) / (b - a));
const easeInOut = (u: number) => (u < 0.5 ? 4 * u * u * u : 1 - Math.pow(-2 * u + 2, 3) / 2);
// Fast launch with no slow start, then a gentle arrival at the button.
const launch = (u: number) => 1 - Math.pow(1 - u, 2.2);

type Spark = { x: number; y: number; vx: number; vy: number; life: number; size: number; hue: string };

// Timeline in seconds.
const T = {
  drag: [0.55, 1.45],
  release: 1.5,
  fold: [1.58, 2.0],
  fly: [2.02, 2.8],
  copy: 2.4,
  end: 3.5,
};

/** Fits the scene so the card is about 430 px wide, or 86 % of a narrow screen. */
function fitViewBox(svg: SVGSVGElement) {
  const w = svg.clientWidth || 1200;
  const h = svg.clientHeight || 640;
  const s = Math.min(430, w * 0.86) / 360;
  const vw = w / s;
  const vh = h / s;
  svg.setAttribute("viewBox", `${(600 - vw / 2).toFixed(1)} ${(300 - vh * 0.47).toFixed(1)} ${vw.toFixed(1)} ${vh.toFixed(1)}`);
}

export default function HeroFliq() {
  const wrap = useRef<HTMLDivElement>(null);
  const svg = useRef<SVGSVGElement>(null);
  const canvas = useRef<HTMLCanvasElement>(null);
  const raf = useRef(0);

  const play = useCallback((instant = false, freezeAt?: number) => {
    const hero = wrap.current?.closest<HTMLElement>(".hero");
    const root = svg.current;
    const cv = canvas.current;
    if (!hero || !root || !cv) return;

    const q = <E extends Element>(sel: string) => root.querySelector<E>(sel)!;
    const glass = q<SVGPathElement>(".fliq-glass");
    const paper = q<SVGPathElement>(".fliq-paper");
    const crease = q<SVGLineElement>(".fliq-crease");
    const content = q<SVGGElement>(".fliq-content");
    const body = q<SVGGElement>(".fliq-body");
    const fileG = q<SVGGElement>(".fliq-file");
    const cursor = q<SVGGElement>(".fliq-cursor");
    const title = q<SVGTextElement>(".fliq-title");
    const trail = q<SVGPathElement>(".fliq-trail");
    const trailMask = q<SVGPathElement>(".fliq-trail-mask");
    const bloom = q<SVGCircleElement>(".fliq-bloom");
    const halo = q<SVGEllipseElement>(".fliq-halo");
    const ring = q<SVGCircleElement>(".fliq-ring");
    const cta = document.querySelector<HTMLElement>("[data-fliq-target]");

    cancelAnimationFrame(raf.current);
    fitViewBox(root);
    hero.dataset.intro = instant ? "done" : "playing";
    cta?.classList.remove("is-landed");

    const ctx = cv.getContext("2d");
    if (!ctx) return;
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    cv.width = cv.clientWidth * dpr;
    cv.height = cv.clientHeight * dpr;

    // Screen and SVG coordinates, both ways, whatever the viewBox.
    const ctm = root.getScreenCTM();
    const inv = ctm?.inverse();
    const toSvg = (X: number, Y: number): Pt =>
      inv ? [inv.a * X + inv.c * Y + inv.e, inv.b * X + inv.d * Y + inv.f] : [X, Y];
    const cvBox = cv.getBoundingClientRect();
    const toCanvas = (x: number, y: number): Pt =>
      ctm
        ? [(ctm.a * x + ctm.c * y + ctm.e - cvBox.left) * dpr, (ctm.b * x + ctm.d * y + ctm.f - cvBox.top) * dpr]
        : [x, y];

    const vb = root.viewBox.baseVal;
    const P0: Pt = [600, 300];
    const P1: Pt = [700, 330];
    const P3: Pt = [vb.x + vb.width - 60, vb.y + 40];
    const P2: Pt = [0, 0];
    /** Aims at the App Store button where it is now; layout can move before launch. */
    const aim = () => {
      const r = cta?.getBoundingClientRect();
      if (r && r.width > 0) {
        const [x, y] = toSvg(r.left + r.width / 2, r.top + r.height / 2);
        if (Number.isFinite(x) && Number.isFinite(y)) {
          P3[0] = x;
          P3[1] = y;
        }
      }
      P2[0] = P3[0] - 140;
      P2[1] = P3[1] + 240;
      const d = `M${P0[0]},${P0[1]} C${P1[0]},${P1[1]} ${P2[0]},${P2[1]} ${P3[0]},${P3[1]}`;
      trail.setAttribute("d", d);
      trailMask.setAttribute("d", d);
      L = trailMask.getTotalLength();
      trailMask.style.strokeDasharray = `${L}`;
    };
    let L = 0;
    let aimed = false;
    const bez = (t: number): Pt => {
      const m = 1 - t;
      const a = m * m * m;
      const b = 3 * m * m * t;
      const c = 3 * m * t * t;
      const e = t * t * t;
      return [a * P0[0] + b * P1[0] + c * P2[0] + e * P3[0], a * P0[1] + b * P1[1] + c * P2[1] + e * P3[1]];
    };

    const sparks: Spark[] = [];
    const hues = ["#7BE6FF", "#2ED1FF", "#4C8DFF", "#9B6BFF", "#FFFFFF"];
    const t0 = performance.now();
    let last = t0;

    const frame = (now: number) => {
      const t = freezeAt ?? (instant ? T.end : (now - t0) / 1000);
      const dt = Math.min(0.05, (now - last) / 1000);
      last = now;

      // The card is already on screen from the first paint (CSS fades it in).
      const inU = 1;
      // Drag: the cursor brings a file in from the lower left.
      const dragU = easeInOut(seg(t, T.drag[0], T.drag[1]));
      const fx = 600 - 360 + dragU * 250;
      const fy = 300 + 250 - dragU * 238;
      const dockU = seg(t, T.release, T.release + 0.12);
      const shown = seg(t, T.drag[0], T.drag[0] + 0.15);
      fileG.setAttribute("transform", `translate(${fx}, ${fy}) rotate(${-10 + dragU * 10}) scale(${1 - dockU})`);
      fileG.style.opacity = String(shown * (1 - dockU));
      cursor.setAttribute("transform", `translate(${fx + 30}, ${fy + 28})`);
      cursor.style.opacity = String(shown * (1 - seg(t, T.release, T.release + 0.25)));
      title.textContent = dragU > 0.6 ? "Release to Fliq" : "Bring it here";

      // Fold: squash, then morph the outline into the plane.
      const squash = Math.sin(seg(t, T.release, T.fold[0] + 0.08) * Math.PI) * 0.07;
      const m = easeInOut(seg(t, T.fold[0], T.fold[1]));
      const pathD = m === 0 ? CARD_D : toPath(CARD.map((p, i): Pt => [p[0] + (PLANE[i][0] - p[0]) * m, p[1] + (PLANE[i][1] - p[1]) * m]));
      glass.setAttribute("d", pathD);
      paper.setAttribute("d", pathD);
      glass.style.opacity = String(1 - m);
      paper.style.opacity = String(m);
      crease.style.opacity = String(seg(m, 0.7, 1));
      halo.setAttribute("rx", String(250 - 140 * m));
      halo.setAttribute("ry", String(140 - 85 * m));
      const fade = seg(t, T.fold[0] - 0.05, T.fold[0] + 0.14);
      content.style.opacity = String(1 - fade);
      content.setAttribute("transform", `scale(${1 - 0.3 * fade})`);

      // Flight along the curve to the button.
      const flying = t >= T.fly[0];
      if (!aimed && (flying || instant)) {
        aim();
        aimed = true;
      }
      const fu = launch(seg(t, T.fly[0], T.fly[1]));
      let [x, y] = P0;
      let ang = 0;
      if (flying) {
        [x, y] = bez(fu);
        const [ax, ay] = bez(Math.max(0, fu - 0.01));
        const [bx, by] = bez(Math.min(1, fu + 0.01));
        ang = (Math.atan2(by - ay, bx - ax) * 180) / Math.PI;
      }
      const scale = (1 + squash) * inU * (flying ? 1 - 0.8 * fu : 1);
      const squashY = flying ? 1 : 1 - squash * 1.6;
      body.setAttribute("transform", `translate(${x}, ${y}) rotate(${ang}) scale(${scale}, ${scale * squashY})`);
      body.style.opacity = String(1 - seg(t, T.fly[1] - 0.06, T.fly[1]));

      // Contrail, bloom and ring at the launch point.
      trailMask.style.strokeDashoffset = String(L * (1 - fu));
      trail.style.opacity = String(flying ? 0.95 - 0.77 * seg(t, T.fly[1], T.end) : 0);
      const bu = seg(t, T.fly[0] - 0.02, T.fly[0] + 0.5);
      bloom.setAttribute("r", String(30 + 170 * bu));
      bloom.style.opacity = String(bu > 0 && bu < 1 ? 0.75 * (1 - bu) : 0);
      const ru = seg(t, T.fly[0], T.fly[0] + 0.7);
      ring.setAttribute("r", String(60 + 260 * ru));
      ring.style.opacity = String(ru > 0 && ru < 1 ? 0.8 * (1 - ru) : 0);

      // Sparks follow the plane.
      ctx.clearRect(0, 0, cv.width, cv.height);
      if (!instant && flying && fu < 0.97) {
        const [px, py] = toCanvas(x, y);
        for (let i = 0; i < 6; i++) {
          sparks.push({
            x: px,
            y: py,
            vx: (Math.random() - 0.5) * 150 * dpr,
            vy: (Math.random() - 0.5) * 150 * dpr,
            life: 1,
            size: (0.8 + Math.random() * 2.1) * dpr,
            hue: hues[(Math.random() * hues.length) | 0],
          });
        }
      }
      for (let i = sparks.length - 1; i >= 0; i--) {
        const s = sparks[i];
        s.life -= dt * 1.6;
        if (s.life <= 0) {
          sparks.splice(i, 1);
          continue;
        }
        s.x += s.vx * dt;
        s.y += s.vy * dt;
        ctx.globalAlpha = s.life;
        ctx.fillStyle = s.hue;
        ctx.beginPath();
        ctx.arc(s.x, s.y, s.size, 0, Math.PI * 2);
        ctx.fill();
      }
      ctx.globalAlpha = 1;

      if (t >= T.fly[1] - 0.03) cta?.classList.add("is-landed");
      if (t >= T.copy) hero.dataset.intro = "done";
      if (freezeAt === undefined && (t < T.end || sparks.length)) raf.current = requestAnimationFrame(frame);
    };
    raf.current = requestAnimationFrame(frame);
  }, []);

  useEffect(() => {
    const root = svg.current;
    if (root) fitViewBox(root);
    const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    // `?fliq=1.7` draws the single frame at 1.7 s, for checking the motion.
    const frozen = Number.parseFloat(new URLSearchParams(window.location.search).get("fliq") ?? "");
    let id = 0;
    let cancelled = false;
    const start = () => {
      if (cancelled) return;
      // Two frames after the fonts settle, so the intro never competes with first paint.
      requestAnimationFrame(() =>
        requestAnimationFrame(() => {
          if (cancelled) return;
          id = window.setTimeout(() => (Number.isFinite(frozen) ? play(false, frozen) : play(reduce)), reduce ? 0 : 120);
        }),
      );
    };
    if (document.fonts?.ready) document.fonts.ready.then(start, start);
    else start();
    const onResize = () => {
      if (svg.current) fitViewBox(svg.current);
    };
    window.addEventListener("resize", onResize);
    return () => {
      cancelled = true;
      window.clearTimeout(id);
      window.removeEventListener("resize", onResize);
      cancelAnimationFrame(raf.current);
    };
  }, [play]);

  return (
    <div className="fliq-wrap" ref={wrap}>
      <div className="fliq-stage" aria-hidden="true">
        <canvas className="fliq-sparks" ref={canvas} />
        <svg ref={svg} className="fliq-svg" viewBox="0 0 1200 640" preserveAspectRatio="xMidYMid meet">
          <defs>
            <linearGradient id="fliqGlass" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0" stopColor="#1B2236" stopOpacity="0.94" />
              <stop offset="1" stopColor="#0C1020" stopOpacity="0.94" />
            </linearGradient>
            <linearGradient id="fliqPaper" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0" stopColor="#F4FBFF" />
              <stop offset="0.49" stopColor="#BFE6FF" />
              <stop offset="0.51" stopColor="#3B8DFF" />
              <stop offset="1" stopColor="#6A4DFF" />
            </linearGradient>
            <linearGradient id="fliqTrail" x1="0" y1="1" x2="1" y2="0">
              <stop offset="0" stopColor="#2ED1FF" stopOpacity="0.15" />
              <stop offset="0.5" stopColor="#2ED1FF" />
              <stop offset="1" stopColor="#9B6BFF" />
            </linearGradient>
            <radialGradient id="fliqBloom">
              <stop offset="0" stopColor="#FFFFFF" stopOpacity="0.95" />
              <stop offset="0.35" stopColor="#7BE6FF" stopOpacity="0.55" />
              <stop offset="1" stopColor="#2E6BFF" stopOpacity="0" />
            </radialGradient>
            <mask id="fliqTrailMask" maskUnits="userSpaceOnUse" x="-5000" y="-5000" width="10000" height="10000">
              <path className="fliq-trail-mask" fill="none" stroke="#fff" strokeWidth="16" strokeLinecap="round" />
            </mask>
            <radialGradient id="fliqHalo">
              <stop offset="0" stopColor="#2ED1FF" stopOpacity="0.32" />
              <stop offset="0.6" stopColor="#1A7AFF" stopOpacity="0.12" />
              <stop offset="1" stopColor="#1A7AFF" stopOpacity="0" />
            </radialGradient>
          </defs>

          <circle className="fliq-bloom" cx="600" cy="300" r="30" fill="url(#fliqBloom)" opacity="0" />
          <circle className="fliq-ring" cx="600" cy="300" r="60" fill="none" stroke="#5FD8FF" strokeWidth="2" opacity="0" />
          <path
            className="fliq-trail"
            mask="url(#fliqTrailMask)"
            fill="none"
            stroke="url(#fliqTrail)"
            strokeWidth="3.5"
            strokeLinecap="round"
            strokeDasharray="10 13"
            opacity="0"
          />

          <g className="fliq-body" transform="translate(600, 300)">
            <ellipse className="fliq-halo" rx="250" ry="140" fill="url(#fliqHalo)" />
            <path className="fliq-glass" d={CARD_D} fill="url(#fliqGlass)" stroke="#5CCBFF" strokeOpacity="0.85" strokeWidth="2" />
            <path className="fliq-paper" d={CARD_D} fill="url(#fliqPaper)" opacity="0" />
            <line className="fliq-crease" x1="-30" y1="0" x2="86" y2="0" stroke="#FFFFFF" strokeOpacity="0.9" strokeWidth="2" opacity="0" />
            <g className="fliq-content">
              <image href="/assets/airfliq-icon-256.png" x="-150" y="-38" width="76" height="76" />
              <text className="fliq-title" x="-56" y="-4" fill="#F4F7FF" fontSize="27" fontWeight="760">
                Bring it here
              </text>
              <text x="-56" y="26" fill="#9FB0CC" fontSize="17" fontWeight="520">
                Launch Deck.pdf
              </text>
            </g>
          </g>

          <g className="fliq-file" opacity="0">
            <rect x="-34" y="-42" width="68" height="84" rx="12" fill="#F6F8FC" />
            <path d="M14,-42 L34,-22 L14,-22 Z" fill="#D7DDEA" />
            <rect x="-22" y="-14" width="40" height="5" rx="2.5" fill="#C3CBDA" />
            <rect x="-22" y="-3" width="30" height="5" rx="2.5" fill="#C3CBDA" />
            <rect x="-22" y="16" width="44" height="16" rx="5" fill="#E8473B" />
            <text x="0" y="28" textAnchor="middle" fontSize="11" fontWeight="800" fill="#fff">
              PDF
            </text>
          </g>
          <g className="fliq-cursor" opacity="0">
            <path d="M0,0 L0,30 L8,23 L13,35 L18,33 L13,21 L23,21 Z" fill="#0B0E16" stroke="#FFFFFF" strokeWidth="2.2" strokeLinejoin="round" />
          </g>
        </svg>
      </div>
      <button type="button" className="fliq-replay" onClick={() => play(false)}>
        <span aria-hidden="true">↻</span> Fliq it again
      </button>
    </div>
  );
}
