import { createHash } from "node:crypto";
import { head, list, put } from "@vercel/blob";

// Hands out one free Lifetime Pro offer code per visitor for the Product Hunt launch, and keeps the
// record Apple does not: which code left and when. The codes come from the PH_CODES environment
// variable (never from this repo). The private Vercel Blob store "airfliq-ph" keeps one small file
// per given code (ph/<env>/given/<code>, its upload time is when it left) and one per visitor
// (ph/<env>/visitors/<hash>/<code>), so a visitor asking again gets the same code.
export const dynamic = "force-dynamic";

const APP_ID = "6801543708";
const ROOT = `ph/${process.env.VERCEL_ENV ?? "development"}`;
const GIVEN = `${ROOT}/given/`;
const CODES = (process.env.PH_CODES ?? "").split(/[\s,]+/).filter(Boolean);

const redeemUrl = (code: string) => `https://apps.apple.com/redeem?ctx=offercodes&id=${APP_ID}&code=${code}`;

// The visitor's network address, hashed, so the store keeps no address.
function visitorPrefix(request: Request) {
  const address = (request.headers.get("x-forwarded-for") ?? "").split(",")[0].trim() || "unknown";
  return `${ROOT}/visitors/${createHash("sha256").update(`airfliq-ph:${address}`).digest("hex").slice(0, 32)}/`;
}

async function freeCodes() {
  const { blobs } = await list({ prefix: GIVEN, limit: 1000 });
  const given = new Set(blobs.map((blob) => blob.pathname.slice(GIVEN.length)));
  return CODES.filter((code) => !given.has(code));
}

export async function GET() {
  const left = CODES.length ? (await freeCodes()).length : 0;
  return Response.json({ left }, { headers: { "Cache-Control": "public, s-maxage=30" } });
}

export async function POST(request: Request) {
  if (!CODES.length) return Response.json({ error: "unavailable" }, { status: 503 });
  const mine = visitorPrefix(request);
  const before = await list({ prefix: mine, limit: 1 });
  if (before.blobs.length) {
    const code = before.blobs[0].pathname.slice(mine.length);
    return Response.json({ code, url: redeemUrl(code), again: true, left: (await freeCodes()).length });
  }
  const free = await freeCodes();
  // Two visitors can pick the same code at once: the store refuses the second file, so take another.
  for (let attempt = 0; attempt < 5 && free.length; attempt++) {
    const [code] = free.splice(Math.floor(Math.random() * free.length), 1);
    try {
      await put(`${GIVEN}${code}`, new Date().toISOString(), { access: "private", addRandomSuffix: false });
    } catch (error) {
      const taken = await head(`${GIVEN}${code}`).then(() => true, () => false);
      if (taken) continue;
      throw error;
    }
    await put(`${mine}${code}`, new Date().toISOString(), { access: "private", addRandomSuffix: false });
    return Response.json({ code, url: redeemUrl(code), left: free.length });
  }
  return Response.json({ error: "gone", left: 0 }, { status: 410 });
}
