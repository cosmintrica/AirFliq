/* eslint-disable @next/next/no-html-link-for-pages */
import type { Metadata } from "next";
import Image from "next/image";

export const metadata: Metadata = {
  title: "Support - AirFliq",
  description: "Setup, purchases and troubleshooting help for AirFliq on macOS.",
  alternates: {
    canonical: "/support",
  },
};

const githubIssues = "https://github.com/cosmintrica/AirFliq/issues";

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
          <h2>Start setup again</h2>
          <p>
            Open Setup &amp; Permissions from the menu bar to review each live
            permission, choose different folders, or select a new global
            shortcut. AirFliq keeps the setup window open while macOS presents
            its permission controls.
          </p>
        </section>

        <section className="legal-section">
          <h2>Still need help?</h2>
          <p>
            Open a ticket on the{" "}
            <a href={githubIssues} target="_blank" rel="noreferrer">
              AirFliq support tracker
            </a>{" "}
            with your macOS version, the AirFliq version shown in About, and the
            step that did not complete. Never attach private files, purchase
            credentials or Apple Account details.
          </p>
        </section>
      </article>
    </main>
  );
}
