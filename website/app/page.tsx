import Image from "next/image";
import FilmEmbed from "./components/FilmEmbed";
import HeroFliq from "./components/HeroFliq";
import Reveal from "./components/Reveal";
import {
  ArrowUpRight,
  CheckIcon,
  ClockIcon,
  DragIcon,
  FolderIcon,
  GiftIcon,
  GitHubIcon,
  InfinityIcon,
  KeyboardIcon,
  MenuBarIcon,
  NoAccountIcon,
  PlaneIcon,
  PlayIcon,
  RedditIcon,
  RightClickIcon,
  ShieldIcon,
  SparkIcon,
  TrophyIcon,
  XIcon,
} from "./components/Icons";

const icon = "/assets/airfliq-icon-256.png";
const APP_STORE = "https://apps.apple.com/app/airfliq/id6801543708";
const GITHUB = "https://github.com/cosmintrica/AirFliq";
const DEVPOST = "https://devpost.com/software/airfliq";
const FILM_ID = "d5o6kD_NpCk";
const X_ANNOUNCE = "https://x.com/cosmintrica/status/2088397113910505585";
const X_LESSON = "https://x.com/cosmintrica/status/2105481756384407586";
const X_FOLLOWUP = "https://x.com/cosmintrica/status/2105496480005939558";
const X_SUBMIT = "https://x.com/cosmintrica/status/2105496246458937368";
const REDDIT = "https://www.reddit.com/r/MacOSApps/comments/1v4yejr/am_i_the_only_one_who_hates_the_airdrop_sharing/";

const ext = { target: "_blank", rel: "noreferrer" } as const;

function AppMark({ small = false }: { small?: boolean }) {
  const size = small ? 34 : 42;
  return (
    <span className="app-mark">
      <Image src={icon} alt="" width={size} height={size} unoptimized priority={small} />
      <span>
        <b>AirFliq</b>
        <small>Select. Fliq. Sent.</small>
      </span>
    </span>
  );
}

const routes = [
  {
    key: "rightclick",
    Icon: RightClickIcon,
    title: "Right-click any file",
    text: "Send with AirFliq sits right in Finder's menu. No Share submenu, no hunting.",
  },
  {
    key: "drag",
    Icon: DragIcon,
    title: "Drop it on the target",
    text: "Start dragging and a magnetic target meets your cursor. Let go and it folds into a paper plane.",
  },
  {
    key: "shortcut",
    Icon: KeyboardIcon,
    title: "Press ⌃⌥A anywhere",
    text: "One global shortcut opens the picker in any app. Pick a preset or record your own.",
  },
  {
    key: "menubar",
    Icon: MenuBarIcon,
    title: "Or click the menu bar",
    text: "Choose files to send, switch the drag target and change your shortcut in one place.",
  },
];

function RouteScene({ kind }: { kind: string }) {
  if (kind === "rightclick") {
    return (
      <div className="scene scene-menu" aria-hidden="true">
        <div className="mini-file"><i>PDF</i></div>
        <ul className="mini-menu">
          <li>Open</li>
          <li>Get Info</li>
          <li>Rename</li>
          <li>Quick Look</li>
          <li className="mini-menu-hit"><PlaneIcon size={13} /> Send with AirFliq</li>
        </ul>
        <svg className="mini-cursor" viewBox="0 0 25 37" width="17" height="25"><path d="M1.5,1.5 L1.5,31 L9,24.5 L14,35.5 L19,33.5 L14,22.5 L23.5,22.5 Z" fill="#fff" stroke="#0b0e16" strokeWidth="2.2" strokeLinejoin="round" /></svg>
      </div>
    );
  }
  if (kind === "drag") {
    return (
      <div className="scene scene-drag" aria-hidden="true">
        <div className="mini-target">
          <Image src={icon} alt="" width={40} height={40} unoptimized />
          <span><b>Release to Fliq</b><small>Launch Deck.pdf</small></span>
        </div>
        <div className="mini-file mini-file-drag"><i>PDF</i></div>
        <span className="mini-plane"><PlaneIcon size={26} /></span>
      </div>
    );
  }
  if (kind === "shortcut") {
    return (
      <div className="scene scene-keys" aria-hidden="true">
        <div className="keys">
          <span className="keycap k1">⌃</span>
          <span className="keycap k2">⌥</span>
          <span className="keycap k3">A</span>
        </div>
        <div className="mini-picker"><i /><i /><i /><b>Send with AirDrop</b></div>
      </div>
    );
  }
  return (
    <div className="scene scene-bar" aria-hidden="true">
      <div className="mini-bar"><span /><span /><span className="mini-glyph"><PlaneIcon size={12} /></span><span className="mini-clock">9:41</span></div>
      <div className="mini-panel">
        <b><PlaneIcon size={12} /> Choose files to send…</b>
        <span>Drag target <i className="toggle on" /></span>
        <span>Global shortcut <em>⌃⌥A</em></span>
      </div>
    </div>
  );
}

const timeline = [
  {
    date: "Aug 15",
    title: "Announced AirFliq",
    text: "Shared the idea on X and committed to building it in public for Shipaton.",
    links: [{ href: X_ANNOUNCE, label: "Post on X", Icon: XIcon }],
  },
  {
    date: "August",
    title: "Asked Mac people",
    text: "An r/MacOSApps thread with 4.4K views shaped the product: the drag target stays optional and out of the way, and AirFliq became free to start.",
    links: [{ href: REDDIT, label: "Reddit thread", Icon: RedditIcon }],
  },
  {
    date: "Sep 29",
    title: "Live on the Mac App Store",
    text: "Version 1.0.0 shipped as a universal app for Apple Silicon and Intel, with RevenueCat powering the trial and Lifetime Pro.",
    links: [{ href: APP_STORE, label: "Mac App Store", Icon: ArrowUpRight }],
  },
  {
    date: "Oct 1",
    title: "Found a macOS 27 AirDrop quirk",
    text: "Cancelling AirDrop still reports success to apps. AirFliq now tells a real send from a cancel by its radio traffic, so a cancel never costs a free send.",
    links: [
      { href: X_LESSON, label: "The quirk", Icon: XIcon },
      { href: X_FOLLOWUP, label: "The fix", Icon: XIcon },
    ],
  },
  {
    date: "Oct 1",
    title: "Submitted to Shipaton",
    text: "Version 1.0.1 went to App Review with free daily sends, a setup that always finishes and the paper plane.",
    links: [
      { href: DEVPOST, label: "Devpost", Icon: TrophyIcon },
      { href: X_SUBMIT, label: "Post on X", Icon: XIcon },
    ],
  },
];

const faqs = [
  ["Does AirFliq replace AirDrop?", "No. It removes the clicks before Apple's own AirDrop panel. Discovery and the transfer stay inside macOS."],
  ["What is free?", "From version 1.0.1, 5 sends every day on every route, with no trial and no account. A cancelled AirDrop never counts."],
  ["How does the trial work?", "It unlocks unlimited sending for 7 days and starts only when you choose. It never renews and never charges you."],
  ["Does it need Full Disk Access?", "No. You choose the folders AirFliq may read. If a send needs another folder, AirFliq asks for it in context."],
  ["Which Macs are supported?", "macOS 13 or later, as a universal app for Apple Silicon and Intel."],
];

export default function Home() {
  return (
    <main>
      <Reveal />
      <div className="ambient" aria-hidden="true"><i /><i /><i /></div>

      <header className="hero" id="top" data-intro="pending">
        <nav className="nav shell" aria-label="Main navigation">
          <a href="#top" aria-label="AirFliq home"><AppMark small /></a>
          <div className="nav-links">
            <a href="#routes">How it works</a>
            <a href="#film">Film</a>
            <a href="#pricing">Pricing</a>
            <a href="#shipaton">Shipaton</a>
          </div>
          <a className="nav-cta" href={APP_STORE} {...ext} data-fliq-target>
            <span>Mac App Store</span>
            <ArrowUpRight size={14} />
          </a>
        </nav>

        <HeroFliq />

        <div className="hero-copy shell">
          <p className="pill"><SparkIcon size={14} /> Built in public for RevenueCat Shipaton 2026</p>
          <h1>
            AirDrop in <em>one move.</em>
          </h1>
          <p className="hero-lead">
            Right-click in Finder, drop on the magnetic target, press ⌃⌥A or click the menu bar.
            Apple&apos;s own AirDrop opens. Nothing in between.
          </p>
          <div className="hero-actions">
            <a className="button button-primary" href={APP_STORE} {...ext}>
              <span>Get it on the Mac App Store</span>
              <ArrowUpRight size={18} />
            </a>
            <a className="button button-quiet" href="#film">
              <PlayIcon size={18} />
              <span>Watch the film</span>
            </a>
          </div>
          <ul className="hero-meta">
            <li><CheckIcon size={14} /> macOS 13 or later</li>
            <li><CheckIcon size={14} /> Apple Silicon and Intel</li>
            <li><CheckIcon size={14} /> No account, no servers</li>
          </ul>
        </div>
      </header>

      <section className="routes shell" id="routes">
        <div className="section-head" data-reveal>
          <p className="eyebrow">How it works</p>
          <h2>One move. <em>Four ways.</em></h2>
          <p>Use whichever is closest to your hand. Every route ends in the same place: Apple&apos;s AirDrop panel, ready.</p>
        </div>
        <div className="route-grid">
          {routes.map(({ key, Icon, title, text }, i) => (
            <article key={key} className={`route-card route-${key}`} data-reveal data-animate style={{ transitionDelay: `${i * 70}ms` }}>
              <RouteScene kind={key} />
              <div className="route-copy">
                <span className="route-icon"><Icon size={20} /></span>
                <h3>{title}</h3>
                <p>{text}</p>
              </div>
            </article>
          ))}
        </div>
      </section>

      <section className="film shell" id="film">
        <div className="section-head" data-reveal>
          <p className="eyebrow">The film</p>
          <h2>Sixty seconds. <em>Every frame is code.</em></h2>
          <p>No screen recordings and no stock footage. The interface, the motion and the soundtrack are generated from code.</p>
        </div>
        <div data-reveal>
          <FilmEmbed id={FILM_ID} title="AirFliq: AirDrop in one move on Mac" />
          <a className="film-youtube" href={`https://youtu.be/${FILM_ID}`} {...ext}>
            <PlayIcon size={18} /> Watch on YouTube <ArrowUpRight size={14} />
          </a>
        </div>
      </section>

      <section className="privacy shell" id="privacy">
        <div className="section-head" data-reveal>
          <p className="eyebrow">Private by design</p>
          <h2>Your files stay <em>yours.</em></h2>
        </div>
        <div className="privacy-grid">
          {[
            { Icon: ShieldIcon, title: "Apple's AirDrop only", text: "Files travel straight to your device through AirDrop. Never through our servers." },
            { Icon: NoAccountIcon, title: "No account", text: "Nothing to sign up for. Open it and send." },
            { Icon: FolderIcon, title: "Your folders only", text: "AirFliq reads only the folders you choose. No Full Disk Access." },
          ].map(({ Icon, title, text }, i) => (
            <article key={title} className="privacy-card" data-reveal style={{ transitionDelay: `${i * 80}ms` }}>
              <span className="privacy-icon"><Icon size={26} /></span>
              <h3>{title}</h3>
              <p>{text}</p>
            </article>
          ))}
        </div>
        <a className="inline-link" href="/privacy">Read the privacy details <ArrowUpRight size={14} /></a>
      </section>

      <section className="pricing shell" id="pricing">
        <div className="section-head" data-reveal>
          <p className="eyebrow">Pricing</p>
          <h2>Free every day. <em>Unlimited, once.</em></h2>
          <p>No subscription, ever. Purchases and the trial run through the Mac App Store and RevenueCat.</p>
        </div>
        <div className="price-grid">
          <article className="price-card" data-reveal>
            <span className="price-icon"><GiftIcon size={24} /></span>
            <h3>Free</h3>
            <p className="price"><b>5</b> sends a day</p>
            <p>Every route, no trial and no account. A cancelled AirDrop never counts.</p>
            <span className="price-tag">Version 1.0.1</span>
          </article>
          <article className="price-card" data-reveal style={{ transitionDelay: "80ms" }}>
            <span className="price-icon"><ClockIcon size={24} /></span>
            <h3>Trial</h3>
            <p className="price"><b>7</b> days unlimited</p>
            <p>Starts only when you choose. It never renews and never charges.</p>
          </article>
          <article className="price-card price-pro" data-reveal style={{ transitionDelay: "160ms" }}>
            <span className="price-icon"><InfinityIcon size={24} /></span>
            <h3>Lifetime Pro</h3>
            <p className="price"><b>$4.99</b> once</p>
            <p>Unlimited sending forever on every Mac with your Apple Account.</p>
            <span className="price-tag">US price, shown in your currency on the App Store</span>
          </article>
        </div>
        <p className="price-note">Free daily sends arrive with version 1.0.1, now in App Review. Version 1.0.0 starts with the free 7-day trial.</p>
      </section>

      <section className="shipaton" id="shipaton">
        <div className="shell">
          <div className="section-head" data-reveal>
            <p className="eyebrow"><TrophyIcon size={14} /> RevenueCat Shipaton 2026</p>
            <h2>Built in <em>public.</em></h2>
            <p>From the first post to the App Store, every step was shared, and the people who answered changed the app.</p>
          </div>
          <ol className="timeline">
            {timeline.map((item, i) => (
              <li key={item.title} data-reveal style={{ transitionDelay: `${i * 60}ms` }}>
                <span className="tl-dot"><PlaneIcon size={14} /></span>
                <time>{item.date}</time>
                <div>
                  <h3>{item.title}</h3>
                  <p>{item.text}</p>
                  <div className="tl-links">
                    {item.links.map(({ href, label, Icon }) => (
                      <a key={href} href={href} {...ext}><Icon size={15} /> {label}</a>
                    ))}
                  </div>
                </div>
              </li>
            ))}
          </ol>
          <div className="ship-links" data-reveal>
            <a href={DEVPOST} {...ext}><TrophyIcon size={18} /> Devpost project</a>
            <a href={GITHUB} {...ext}><GitHubIcon size={18} /> Source on GitHub</a>
            <a href={`https://youtu.be/${FILM_ID}`} {...ext}><PlayIcon size={18} /> Film on YouTube</a>
          </div>
        </div>
      </section>

      <section className="faq shell" id="faq">
        <div className="section-head" data-reveal>
          <p className="eyebrow">Good to know</p>
          <h2>Clear answers.</h2>
        </div>
        <div className="faq-list" data-reveal>
          {faqs.map(([question, answer], index) => (
            <details key={question} open={index === 0}>
              <summary><span>{question}</span><i>+</i></summary>
              <p>{answer}</p>
            </details>
          ))}
        </div>
      </section>

      <section className="final shell" data-reveal>
        <Image src={icon} alt="AirFliq app icon" width={96} height={96} unoptimized />
        <h2>Send it in <em>one move.</em></h2>
        <a className="button button-primary" href={APP_STORE} {...ext}>
          <span>Get it on the Mac App Store</span>
          <ArrowUpRight size={18} />
        </a>
      </section>

      <footer>
        <div className="shell footer-inner">
          <a href="#top"><AppMark small /></a>
          <p>Made for people who AirDrop all day.</p>
          <div>
            <a href="/privacy">Privacy</a>
            <a href="/support">Support</a>
            <a href={GITHUB} {...ext}>GitHub</a>
            <a href={DEVPOST} {...ext}>Devpost</a>
          </div>
        </div>
      </footer>
    </main>
  );
}
