/* eslint-disable @next/next/no-html-link-for-pages */
import type { Metadata } from "next";
import Image from "next/image";

export const metadata: Metadata = {
  title: "Privacy - AirFliq",
  description: "How AirFliq handles files, permissions, purchases and personal data.",
  alternates: {
    canonical: "/privacy",
  },
};

export default function PrivacyPage() {
  return (
    <main className="legal-page">
      <nav className="legal-nav shell">
        <a className="brand" href="/">
          <Image
            src="/assets/airfliq-icon.png"
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
        <span className="legal-meta">Effective July 29, 2026</span>
        <h1>Privacy, without<br />the fine print.</h1>
        <p className="legal-lead">
          AirFliq is designed to move files through macOS without collecting
          your identity or file data. There is no AirFliq account, cloud
          upload or advertising tracker.
        </p>

        <section className="legal-section">
          <h2>Files stay on your devices</h2>
          <p>
            AirFliq passes the files you choose to Apple&apos;s native AirDrop
            sharing service. AirFliq does not upload, copy, store or inspect
            their contents on an external server.
          </p>
        </section>

        <section className="legal-section">
          <h2>Permissions are limited and explained</h2>
          <ul>
            <li>
              <strong>Finder access</strong> reads the items currently selected
              in Finder when you invoke a send command.
            </li>
            <li>
              <strong>Folder access</strong> is limited to folders you explicitly
              choose and is stored locally as security-scoped bookmarks.
            </li>
            <li>
              <strong>Finder extension</strong> adds the optional right-click
              action and is controlled by macOS.
            </li>
          </ul>
        </section>

        <section className="legal-section">
          <h2>Data collection</h2>
          <p>
            AirFliq does not collect file names, file contents or advertising
            identifiers. Preferences remain locally on your Mac. Apple and
            RevenueCat process purchase history and a RevenueCat-generated
            anonymous App User ID to verify trial and purchase status. Neither
            service receives your files or file names.
          </p>
        </section>

        <section className="legal-section">
          <h2>Purchases</h2>
          <p>
            Mac App Store purchases are processed by Apple. AirFliq uses
            RevenueCat to verify the Pro entitlement and restore purchases.
            Purchase history is used for App Functionality, including receipt
            validation and entitlements, and for RevenueCat Analytics. AirFliq
            does not link the anonymous App User ID or purchase history to your
            identity, and does not use this data to track you across apps or
            websites.
          </p>
        </section>

        <section className="legal-section">
          <h2>Changes and questions</h2>
          <p>
            Material changes will be posted on this page with a new effective
            date. Support information is available on the{" "}
            <a href="/support">AirFliq support page</a>.
          </p>
        </section>
      </article>
    </main>
  );
}
