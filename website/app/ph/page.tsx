/* eslint-disable @next/next/no-html-link-for-pages */
import type { Metadata } from "next";
import Image from "next/image";
import ClaimCode from "./ClaimCode";

export const metadata: Metadata = {
  title: "Free Lifetime Pro for Product Hunt - AirFliq",
  description: "A one-time code for AirFliq Lifetime Pro, for the Product Hunt community.",
  alternates: {
    canonical: "/ph",
  },
  robots: {
    index: false,
  },
};

export default function ProductHuntPage() {
  return (
    <main className="legal-page">
      <nav className="legal-nav shell">
        <a className="brand" href="/">
          <Image
            src="/assets/airfliq-icon-256.png"
            alt=""
            width={34}
            height={34}
            unoptimized
          />
          <span>AirFliq</span>
        </a>
        <a href="/">Back to home</a>
      </nav>

      <article className="legal-card shell">
        <span className="legal-meta">Product Hunt launch</span>
        <h1>Lifetime Pro,<br />on the house.</h1>
        <p className="legal-lead">
          Thanks for coming over from Product Hunt. Take one code: it unlocks
          unlimited sending in AirFliq forever, on every Mac with your Apple
          Account.
        </p>

        <ClaimCode />

        <section className="legal-section">
          <h2>How to redeem</h2>
          <p>
            Install AirFliq from the Mac App Store, then open the redeem link on
            your Mac, or choose Redeem Code on AirFliq&apos;s Unlock Lifetime Pro
            screen. Redeeming needs macOS 15 or later, and each code works once.
          </p>
        </section>
      </article>
    </main>
  );
}
