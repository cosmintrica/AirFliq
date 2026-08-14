/* eslint-disable @next/next/no-html-link-for-pages */
import type { Metadata } from "next";
import Image from "next/image";

export const metadata: Metadata = {
  title: "Support - AirFliq",
  description: "Setup, purchases and troubleshooting help for AirFliq on macOS.",
};

const items = [
  ["Finder access", "Open Setup & Permissions, choose Grant, then allow AirFliq under Privacy & Security > Automation."],
  ["Folder access", "Choose only the folders you send from. Use Manage at any time to replace or remove the saved access."],
  ["Right-click menu", "Open Setup & Permissions and choose Enable. macOS may ask you to enable AirFliq in Extensions."],
  ["A new folder", "Choose the folder named by AirFliq, or a parent folder. Existing folder access is preserved."],
  ["Restore Pro", "Open the AirFliq menu, choose Unlock Lifetime Pro, then Restore Purchase."],
  ["Nothing selected", "Make Finder the active app, select one or more files or folders, then use the shortcut again."],
];

export default function SupportPage() {
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
        <span className="legal-meta">AirFliq support</span>
        <h1>Back to flying<br />in a minute.</h1>
        <p className="legal-lead">
          Most issues are one of the three setup permissions. AirFliq shows
          their live state and links directly to the relevant macOS controls.
        </p>

        <div className="support-grid">
          {items.map(([title, copy]) => (
            <div className="support-tile" key={title}>
              <strong>{title}</strong>
              <p>{copy}</p>
            </div>
          ))}
        </div>

        <section className="legal-section">
          <h2>Clean first-run test</h2>
          <p>
            Quit AirFliq, run <strong>reset-permissions.sh</strong> from the
            downloaded project build, and launch the app again. All three setup
            items should return to their initial state.
          </p>
        </section>

        <section className="legal-section">
          <h2>Before launch</h2>
          <p>
            A dedicated support email will be published here and in the Mac App
            Store listing before the app goes on sale.
          </p>
        </section>
      </article>
    </main>
  );
}
