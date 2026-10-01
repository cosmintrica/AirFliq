#!/usr/bin/env node
// Deterministic seek-based renderer for film-v6.
// Every frame: FILM.renderAt(t) seeks the paused GSAP master timeline and the
// procedural layers to t, waits for image-sequence decodes, then the frame is
// captured through CDP and piped to ffmpeg. No wall-clock animation exists.
//
// Usage:
//   node render.mjs stills --times 1.0,2.5 [--scale 1.3333] [--out dir]
//   node render.mjs segment --from 0 --to 600 --out seg.mp4 [--scale 1.3333]
//   node render.mjs film [--workers 5] [--scale 1.3333]   (all segments + concat)
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { fileURLToPath, pathToFileURL } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, '..', '..', '..');
const BUILD = path.join(ROOT, 'build', 'film-v6');
const require = (await import('node:module')).createRequire(path.join(ROOT, 'build', 'film-v5', 'node', 'index.js'));
const puppeteer = require('puppeteer-core');
const CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';

const args = process.argv.slice(2);
const mode = args[0];
const opt = (name, dflt) => {
  const i = args.indexOf('--' + name);
  return i >= 0 ? args[i + 1] : dflt;
};
const SCALE = parseFloat(opt('scale', '1.3333333333'));
const FPS = parseInt(opt('fps', '60'), 10);

async function openPage() {
  const browser = await puppeteer.launch({
    executablePath: CHROME,
    headless: true,
    args: [
      '--allow-file-access-from-files',
      '--force-color-profile=srgb',
      '--hide-scrollbars',
      '--font-render-hinting=none',
      '--disable-background-timer-throttling',
      '--disable-renderer-backgrounding',
      '--disable-backgrounding-occluded-windows',
      '--mute-audio',
      '--no-first-run',
    ],
    // Chrome's headless screenshots ignore deviceScaleFactor, so the stage is
    // CSS-zoomed instead (text and vectors re-rasterize at the output size).
    defaultViewport: { width: Math.round(1920 * SCALE), height: Math.round(1080 * SCALE), deviceScaleFactor: 1 },
  });
  const page = await browser.newPage();
  page.on('console', (m) => {
    const txt = m.text();
    if (m.type() === 'error' || txt.startsWith('[film]')) console.error(`[page ${m.type()}] ${txt}`);
  });
  page.on('pageerror', (e) => console.error('[pageerror]', e.message));
  const url = pathToFileURL(path.join(HERE, 'index.html')).href + `?zoom=${SCALE}`;
  await page.goto(url, { waitUntil: 'load' });
  await page.waitForFunction('window.FILM && window.FILM.ready === true', { timeout: 60000 });
  const cdp = await page.createCDPSession();
  return { browser, page, cdp };
}

async function capture(cdp, format = 'png') {
  const r = await cdp.send('Page.captureScreenshot', {
    format,
    quality: format === 'jpeg' ? 96 : undefined,
    optimizeForSpeed: true,
    fromSurface: true,
    captureBeyondViewport: false,
  });
  return Buffer.from(r.data, 'base64');
}

async function stills() {
  const times = opt('times', '0').split(',').map(Number);
  const out = opt('out', path.join(BUILD, 'stills'));
  fs.mkdirSync(out, { recursive: true });
  const { browser, page, cdp } = await openPage();
  for (const t of times) {
    await page.evaluate((tt) => window.FILM.renderAt(tt), t);
    const buf = await capture(cdp, 'png');
    const name = path.join(out, `t${t.toFixed(3).padStart(7, '0')}.png`);
    fs.writeFileSync(name, buf);
    console.log(name);
  }
  await closeBrowser(browser);
}

async function segment(from, to, outFile) {
  const { browser, page, cdp } = await openPage();
  const ff = spawn('ffmpeg', [
    '-v', 'error', '-y',
    '-f', 'image2pipe', '-framerate', String(FPS), '-c:v', 'png', '-i', '-',
    // sRGB frames -> BT.709 limited-range YUV 4:4:4 mezzanine, tagged.
    '-vf', 'scale=out_color_matrix=bt709:out_range=tv,format=yuv444p',
    '-c:v', 'libx264', '-preset', 'fast', '-crf', '6', '-pix_fmt', 'yuv444p',
    '-color_primaries', 'bt709', '-color_trc', 'bt709', '-colorspace', 'bt709', '-color_range', 'tv',
    '-x264-params', 'keyint=60', outFile,
  ], { stdio: ['pipe', 'inherit', 'inherit'] });
  const ffDone = new Promise((r) => ff.on('close', r));
  const t0 = Date.now();
  for (let f = from; f < to; f++) {
    const t = f / FPS;
    await page.evaluate((tt) => window.FILM.renderAt(tt), t);
    const buf = await capture(cdp, 'png');
    if (!ff.stdin.write(buf)) await new Promise((r) => ff.stdin.once('drain', r));
    if ((f - from) % 120 === 0) {
      const el = (Date.now() - t0) / 1000;
      console.error(`[seg ${from}-${to}] frame ${f} (${((f - from) / Math.max(el, 0.001)).toFixed(1)} fps)`);
    }
  }
  ff.stdin.end();
  await ffDone;
  await closeBrowser(browser);
}

async function closeBrowser(browser) {
  // browser.close() occasionally never resolves after long runs; never let teardown hang a worker.
  const proc = browser.process();
  await Promise.race([browser.close().catch(() => {}), new Promise((r) => setTimeout(r, 5000))]);
  try { proc && proc.kill('SIGKILL'); } catch {}
}

async function film() {
  const workers = parseInt(opt('workers', String(Math.max(2, Math.min(6, os.cpus().length - 4)))), 10);
  const { browser, page } = await openPage();
  const duration = await page.evaluate(() => window.FILM.duration);
  await closeBrowser(browser);
  const total = Math.round(duration * FPS);
  const segDir = path.join(BUILD, 'segments');
  fs.rmSync(segDir, { recursive: true, force: true });
  fs.mkdirSync(segDir, { recursive: true });
  const per = Math.ceil(total / workers);
  const jobs = [];
  const t0 = Date.now();
  for (let w = 0; w < workers; w++) {
    const a = w * per;
    const b = Math.min(total, a + per);
    if (a >= b) continue;
    const out = path.join(segDir, `seg-${String(w).padStart(2, '0')}.mp4`);
    jobs.push(new Promise((resolve, reject) => {
      const p = spawn(process.execPath, [fileURLToPath(import.meta.url), 'segment', '--from', String(a), '--to', String(b),
        '--out', out, '--scale', String(SCALE), '--fps', String(FPS)], { stdio: 'inherit' });
      p.on('close', (code) => (code === 0 ? resolve(out) : reject(new Error(`worker ${w} exit ${code}`))));
    }));
  }
  const outs = await Promise.all(jobs);
  const list = path.join(segDir, 'list.txt');
  fs.writeFileSync(list, outs.map((o) => `file '${o}'`).join('\n') + '\n');
  const master = path.join(BUILD, 'video-master.mp4');
  await new Promise((resolve, reject) => {
    const p = spawn('ffmpeg', ['-v', 'error', '-y', '-f', 'concat', '-safe', '0', '-i', list, '-c', 'copy', master], { stdio: 'inherit' });
    p.on('close', (c) => (c === 0 ? resolve() : reject(new Error('concat failed'))));
  });
  console.log(`rendered ${total} frames with ${workers} workers in ${((Date.now() - t0) / 1000).toFixed(0)} s -> ${master}`);
}

async function exportCues() {
  const { browser, page } = await openPage();
  const data = await page.evaluate(() => ({ cues: window.FILM.cues, sections: window.FILM.sections, duration: window.FILM.duration }));
  await browser.close();
  const file = path.join(HERE, 'timeline.json');
  const prev = JSON.parse(fs.readFileSync(file, 'utf8'));
  const music = Object.fromEntries((prev.sections || []).map((s) => [s.name, s.music]));
  const out = {
    version: (prev.version || 0) + 1,
    note: 'Written by `node render.mjs cues` from film.js (FILM.cues). Times in seconds of the final film.',
    duration: data.duration, bpm: 120, sampleRate: 48000,
    sections: data.sections.map(([name, start, end]) => ({ name, start, end, music: music[name] || '' })),
    musicEvents: prev.musicEvents, risersInto: prev.risersInto,
    cues: data.cues.slice().sort((a, b) => a.t - b.t),
  };
  fs.writeFileSync(file, JSON.stringify(out, null, 1) + '\n');
  console.log(`wrote ${file}: ${out.cues.length} cues (version ${out.version})`);
}

async function thumb() {
  const browser = await puppeteer.launch({ executablePath: CHROME, headless: true,
    args: ['--allow-file-access-from-files', '--force-color-profile=srgb', '--hide-scrollbars', '--font-render-hinting=none'],
    defaultViewport: { width: 2560, height: 1440, deviceScaleFactor: 1 } });
  const page = await browser.newPage();
  await page.goto(pathToFileURL(path.join(HERE, 'thumbnail.html')).href + '?zoom=2', { waitUntil: 'load' });
  await page.waitForFunction('window.THUMB_READY === true', { timeout: 30000 });
  const cdp = await page.createCDPSession();
  const buf = await capture(cdp, 'png');
  const big = path.join(BUILD, 'thumbnail-2560.png');
  fs.writeFileSync(big, buf);
  await browser.close();
  const out = path.join(ROOT, 'marketing', 'shipaton', 'video', 'AirFliq-Film-v6-thumbnail.jpg');
  await new Promise((resolve, reject) => {
    const p = spawn('python3', ['-c', `from PIL import Image; im=Image.open(${JSON.stringify(big)}).convert('RGB').resize((1280,720), Image.LANCZOS); im.save(${JSON.stringify(out)}, quality=90, optimize=True, progressive=True)`], { stdio: 'inherit' });
    p.on('close', (c) => (c === 0 ? resolve() : reject(new Error('thumb resize failed'))));
  });
  console.log(out, fs.statSync(out).size, 'bytes');
}

if (mode === 'thumb') await thumb();
else if (mode === 'cues') await exportCues();
else if (mode === 'stills') await stills();
else if (mode === 'segment') await segment(parseInt(opt('from'), 10), parseInt(opt('to'), 10), opt('out'));
else if (mode === 'film') await film();
else {
  console.error('usage: render.mjs stills|segment|film ...');
  process.exit(2);
}
