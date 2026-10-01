import assert from "node:assert/strict";
import { access, readFile } from "node:fs/promises";
import test from "node:test";

const developmentPreviewMeta =
  /<meta(?=[^>]*\bname=["']codex-preview["'])(?=[^>]*\bcontent=["']development["'])[^>]*>/i;

async function render(pathname = "/") {
  const workerUrl = new URL("../dist/server/index.js", import.meta.url);
  workerUrl.searchParams.set(
    "test",
    `${process.pid}-${Date.now()}-${pathname.replaceAll("/", "-")}`,
  );
  const { default: worker } = await import(workerUrl.href);

  return worker.fetch(
    new Request(`http://localhost${pathname}`, {
      headers: { accept: "text/html" },
    }),
    {
      ASSETS: {
        fetch: async () => new Response("Not found", { status: 404 }),
      },
    },
    {
      waitUntil() {},
      passThroughOnException() {},
    },
  );
}

test("server-renders the complete AirFliq landing page", async () => {
  const response = await render();
  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-type") ?? "", /^text\/html\b/i);

  const html = await response.text();
  assert.match(html, /<title>AirFliq \| AirDrop in one move on Mac<\/title>/i);
  assert.match(html, /AirDrop in <em>one move/);
  assert.match(html, /Four ways/);
  assert.match(html, /5<\/b> sends a day/);
  assert.match(html, /7<\/b> days unlimited/);
  assert.match(html, /\$4\.99/);
  assert.match(html, /now in App Review/);
  assert.match(html, /Shipaton/);
  assert.match(html, /Built in <em>public/);
  assert.match(html, /devpost\.com\/software\/airfliq/);
  assert.match(html, /apps\.apple\.com\/app\/airfliq\/id6801543708/);
  assert.match(html, /Your files stay <em>yours/);
  assert.doesNotMatch(html, /Download (?:on|from) the Mac App Store/i);
  assert.doesNotMatch(html, developmentPreviewMeta);
  assert.doesNotMatch(html, /Your site is taking shape|Building your site/);
  assert.doesNotMatch(html, /—|–/);
});

test("renders launch-ready privacy and support pages", async () => {
  const [privacyResponse, supportResponse] = await Promise.all([
    render("/privacy"),
    render("/support"),
  ]);

  assert.equal(privacyResponse.status, 200);
  assert.equal(supportResponse.status, 200);

  const [privacy, support] = await Promise.all([
    privacyResponse.text(),
    supportResponse.text(),
  ]);

  assert.match(privacy, /Privacy, without/);
  assert.match(privacy, /RevenueCat/);
  assert.match(privacy, /App Functionality/);
  assert.match(privacy, /RevenueCat Analytics/);
  assert.match(privacy, /anonymous App User ID/);
  assert.match(privacy, /does not link .* to your identity/s);
  assert.match(privacy, /does not use this data to track you across apps or websites/s);
  assert.match(privacy, /limited to folders you explicitly choose/);
  assert.match(privacy, /rel="canonical" href="https:\/\/airfliq\.vercel\.app\/privacy"/);
  assert.doesNotMatch(privacy, /trial start date remain locally/i);
  assert.doesNotMatch(privacy, /analytics profile/i);
  assert.match(support, /Back to flying/);
  assert.match(support, /Restore Pro/);
  assert.match(support, /Right-click menu/);
  assert.match(support, /rel="canonical" href="https:\/\/airfliq\.vercel\.app\/support"/);
  assert.match(support, /AirFliq support tracker/);
  assert.doesNotMatch(support, /dedicated support email will be published/i);
  assert.doesNotMatch(`${privacy}${support}`, /—|–/);
});

test("contains product metadata and no starter preview artifacts", async () => {
  const [page, layout, packageJson, film] = await Promise.all([
    readFile(new URL("../app/page.tsx", import.meta.url), "utf8"),
    readFile(new URL("../app/layout.tsx", import.meta.url), "utf8"),
    readFile(new URL("../package.json", import.meta.url), "utf8"),
    readFile(new URL("../app/components/FilmEmbed.tsx", import.meta.url), "utf8"),
  ]);

  assert.match(page, /AirFliq/);
  assert.match(page, /7 days/);
  assert.match(page, /A cancelled AirDrop never counts/);
  assert.match(page, /youtu\.be\//);
  assert.match(film, /https:\/\/www\.youtube\.com\/embed\//);
  assert.match(film, /strict-origin-when-cross-origin/);
  assert.doesNotMatch(film, /youtube-nocookie/);
  assert.match(layout, /AirFliq \| AirDrop in one move on Mac/);
  assert.match(layout, /og-airfliq\.png/);
  assert.match(layout, /https:\/\/airfliq\.vercel\.app/);
  assert.doesNotMatch(layout, /airdropper-mac|chatgpt\.site/);
  assert.doesNotMatch(page, /_sites-preview|SkeletonPreview/);
  assert.doesNotMatch(layout, /codex-preview|_sites-preview/);
  assert.doesNotMatch(packageJson, /react-loading-skeleton/);

  await Promise.all([
    access(new URL("../public/assets/airfliq-icon-256.png", import.meta.url)),
    access(new URL("../public/film/poster.jpg", import.meta.url)),
    access(new URL("../public/og-airfliq.png", import.meta.url)),
  ]);
});
