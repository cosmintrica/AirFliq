import { createHash } from "node:crypto";

// Hands out one free Lifetime Pro offer code per visitor for the Product Hunt launch, and keeps the
// record Apple does not: which code left and when (hash ph:given). The codes live only in the
// Upstash Redis store (set ph:codes), never in this public repo.
export const dynamic = "force-dynamic";

const APP_ID = "6801543708";
const STORE_URL = process.env.KV_REST_API_URL ?? process.env.UPSTASH_REDIS_REST_URL;
const STORE_TOKEN = process.env.KV_REST_API_TOKEN ?? process.env.UPSTASH_REDIS_REST_TOKEN;
const TWO_WEEKS = 60 * 60 * 24 * 14;

async function redis(...command: (string | number)[]) {
  const response = await fetch(STORE_URL!, {
    method: "POST",
    headers: { Authorization: `Bearer ${STORE_TOKEN}` },
    body: JSON.stringify(command),
    cache: "no-store",
  });
  if (!response.ok) throw new Error(`store ${response.status}`);
  return (await response.json()).result;
}

// One code per visitor: the network address, hashed so the store keeps no address.
function visitorKey(request: Request) {
  const address = (request.headers.get("x-forwarded-for") ?? "").split(",")[0].trim() || "unknown";
  return `ph:visitor:${createHash("sha256").update(`airfliq-ph:${address}`).digest("hex").slice(0, 32)}`;
}

const redeemUrl = (code: string) => `https://apps.apple.com/redeem?ctx=offercodes&id=${APP_ID}&code=${code}`;

export async function GET() {
  if (!STORE_URL || !STORE_TOKEN) return Response.json({ left: 0 }, { status: 503 });
  return Response.json({ left: await redis("SCARD", "ph:codes") }, { headers: { "Cache-Control": "no-store" } });
}

export async function POST(request: Request) {
  if (!STORE_URL || !STORE_TOKEN) return Response.json({ error: "unavailable" }, { status: 503 });
  const key = visitorKey(request);
  const given = await redis("GET", key);
  if (given) {
    return Response.json({ code: given, url: redeemUrl(given), again: true, left: await redis("SCARD", "ph:codes") });
  }
  const code = await redis("SPOP", "ph:codes");
  if (!code) return Response.json({ error: "gone", left: 0 }, { status: 410 });
  await redis("SET", key, code, "EX", TWO_WEEKS);
  await redis("HSET", "ph:given", code, new Date().toISOString());
  return Response.json({ code, url: redeemUrl(code), left: await redis("SCARD", "ph:codes") });
}
