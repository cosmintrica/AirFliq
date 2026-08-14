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
  assert.match(html, /<title>AirFliq - Select\. Fliq\. Sent\.<\/title>/i);
  assert.match(html, /AirDrop at the speed of/);
  assert.match(html, /7 days/);
  assert.match(html, /no send counter/i);
  assert.match(html, /\$4\.99/);
  assert.match(html, /Your shortcut/);
  assert.match(html, /target meets/);
  assert.match(html, /Native where/);
  assert.match(html, /Privacy by architecture/);
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
  assert.match(privacy, /limited to folders you explicitly choose/);
  assert.match(support, /Back to flying/);
  assert.match(support, /Restore Pro/);
  assert.match(support, /Right-click menu/);
  assert.doesNotMatch(`${privacy}${support}`, /—|–/);
});

test("contains product metadata and no starter preview artifacts", async () => {
  const [page, layout, packageJson] = await Promise.all([
    readFile(new URL("../app/page.tsx", import.meta.url), "utf8"),
    readFile(new URL("../app/layout.tsx", import.meta.url), "utf8"),
    readFile(new URL("../package.json", import.meta.url), "utf8"),
  ]);

  assert.match(page, /AirFliq/);
  assert.match(page, /7 days/);
  assert.match(page, /no send counter/i);
  assert.match(layout, /AirFliq - Select\. Fliq\. Sent\./);
  assert.match(layout, /og-airfliq\.png/);
  assert.doesNotMatch(page, /_sites-preview|SkeletonPreview/);
  assert.doesNotMatch(layout, /codex-preview|_sites-preview/);
  assert.doesNotMatch(packageJson, /react-loading-skeleton/);

  await Promise.all([
    access(new URL("../public/assets/airfliq-icon.png", import.meta.url)),
    access(new URL("../public/og-airfliq.png", import.meta.url)),
    access(new URL("../public/screenshots/onboarding-ready.png", import.meta.url)),
    access(new URL("../public/screenshots/onboarding-shortcut.png", import.meta.url)),
  ]);
});
