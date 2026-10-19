"use client";

import { useEffect, useState } from "react";

type Claim = { code: string; url: string; left: number; again?: boolean };

const APP_STORE = "https://apps.apple.com/app/airfliq/id6801543708";

export default function ClaimCode() {
  const [left, setLeft] = useState<number | null>(null);
  const [claim, setClaim] = useState<Claim | null>(null);
  const [state, setState] = useState<"idle" | "busy" | "gone" | "error">("idle");
  const [copied, setCopied] = useState(false);

  useEffect(() => {
    fetch("/api/ph-code", { cache: "no-store" })
      .then((response) => response.json())
      .then((data) => {
        setLeft(typeof data.left === "number" ? data.left : null);
        if (data.left === 0) setState("gone");
      })
      .catch(() => setLeft(null));
  }, []);

  async function takeCode() {
    setState("busy");
    try {
      const response = await fetch("/api/ph-code", { method: "POST" });
      if (response.status === 410) {
        setLeft(0);
        setState("gone");
        return;
      }
      if (!response.ok) throw new Error(String(response.status));
      const data = (await response.json()) as Claim;
      setClaim(data);
      setLeft(data.left);
      setState("idle");
    } catch {
      setState("error");
    }
  }

  async function copyCode() {
    if (!claim) return;
    try {
      await navigator.clipboard.writeText(claim.code);
      setCopied(true);
    } catch {
      setCopied(false);
    }
  }

  if (claim) {
    return (
      <div className="ph-claim">
        <span className="legal-meta">{claim.again ? "Your code from before" : "Your code"}</span>
        <button type="button" className="ph-code" onClick={copyCode} title="Copy the code">
          {claim.code}
        </button>
        <span className="ph-left">{copied ? "Copied." : "Tap the code to copy it."}</span>
        <div className="ph-actions">
          <a className="button button-primary" href={claim.url}>Redeem on the Mac App Store</a>
          <a className="button button-quiet" href={APP_STORE}>Get AirFliq first</a>
        </div>
      </div>
    );
  }

  return (
    <div className="ph-claim">
      {state === "gone" ? (
        <p className="legal-lead">All the Product Hunt codes are taken. Thank you for the support!</p>
      ) : (
        <button type="button" className="button button-primary" onClick={takeCode} disabled={state === "busy"}>
          {state === "busy" ? "Getting your code..." : "Get my free code"}
        </button>
      )}
      {state === "error" && <span className="ph-left">Something went wrong. Please try again.</span>}
      {left !== null && state !== "gone" && <span className="ph-left">{left} codes left</span>}
    </div>
  );
}
