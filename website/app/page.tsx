import Image from "next/image";

const icon = "/assets/airfliq-icon.png";
const github = "https://github.com/cosmintrica/AirFliq";

const faqs = [
  [
    "Does AirFliq replace AirDrop?",
    "No. AirFliq removes the repetitive steps before Apple's native AirDrop panel. Discovery and transfer remain inside macOS.",
  ],
  [
    "What is included in the trial?",
    "Every feature is unlocked for 7 days. There is no send counter and cancelling the AirDrop panel has no effect on your trial.",
  ],
  [
    "Does it need Full Disk Access?",
    "No. You choose the folders AirFliq may use. If a future send needs another location, AirFliq asks for that folder in context.",
  ],
  [
    "Which files can I send?",
    "AirFliq accepts files, folders and packages supported by Apple's sharing service. It also waits for iCloud items to become available.",
  ],
  [
    "Does it work on Intel Macs?",
    "Yes. AirFliq and its Finder extension ship as universal Apple Silicon and Intel binaries for macOS 13 or later.",
  ],
];

function AppMark({ small = false }: { small?: boolean }) {
  const size = small ? 34 : 42;
  return (
    <span className="app-mark">
      <Image src={icon} alt="" width={size} height={size} unoptimized priority={!small} />
      <span><b>AirFliq</b><small>Select. Fliq. Sent.</small></span>
    </span>
  );
}

export default function Home() {
  return (
    <main id="top">
      <div className="ambient" aria-hidden="true"><i /><i /><i /></div>

      <nav className="nav shell" aria-label="Main navigation">
        <a href="#top" aria-label="AirFliq home"><AppMark small /></a>
        <div className="nav-links">
          <a href="#experience">Experience</a>
          <a href="#privacy">Privacy</a>
          <a href="#trial">Pricing</a>
          <a href="#faq">FAQ</a>
        </div>
        <a className="nav-cta" href="#trial"><span>7 days</span> full access</a>
      </nav>

      <section className="hero shell">
        <div className="hero-copy">
          <p className="eyebrow"><i /> Built for macOS</p>
          <h1>AirDrop at the speed of <em>one move.</em></h1>
          <p className="hero-lead">
            Select in Finder, use your gesture, and the native AirDrop panel is ready.
            No detours. No cloud. No repeated clicks.
          </p>
          <div className="hero-actions">
            <a className="button button-primary" href="#experience">
              <span>See the real app</span><b>↓</b>
            </a>
            <a className="button button-quiet" href={github} target="_blank" rel="noreferrer">
              Public build <b>↗</b>
            </a>
          </div>
          <div className="compatibility" aria-label="Compatibility">
            <span>macOS 13+</span><i /><span>Apple Silicon</span><i /><span>Intel</span>
          </div>
        </div>

        <div className="hero-flight" aria-label="AirFliq file handoff animation">
          <svg className="flight-svg" viewBox="0 0 760 470" aria-hidden="true">
            <defs>
              <linearGradient id="flightGradient" x1="0" x2="1">
                <stop offset="0" stopColor="#39d6ff" />
                <stop offset="0.52" stopColor="#347fff" />
                <stop offset="1" stopColor="#9b5cff" />
              </linearGradient>
            </defs>
            <path className="flight-shadow" d="M55 305 C220 102 455 425 707 174" />
            <path className="flight-core" d="M55 305 C220 102 455 425 707 174" />
          </svg>
          <div className="flight-file" aria-hidden="true"><i>PDF</i><span>Launch brief</span></div>
          <div className="flight-app" aria-hidden="true">
            <span className="app-radar" />
            <Image src={icon} alt="" width={108} height={108} unoptimized priority />
            <i className="flight-check">✓</i>
          </div>
          <div className="flight-caption"><span>SELECT</span><i /><span>FLIQ</span><i /><span>SENT</span></div>
        </div>
      </section>

      <section className="signal-strip" aria-label="Product highlights">
        <div className="signal-track">
          <span>Shortcut</span><i />
          <span>Finder right-click</span><i />
          <span>Menu bar</span><i />
          <span>Drag target</span><i />
          <span>Native AirDrop</span><i />
          <span>No cloud upload</span>
        </div>
      </section>

      <section className="experience shell" id="experience">
        <div className="section-intro centered">
          <p className="eyebrow"><i /> The real application</p>
          <h2>What you see here<br />is what ships.</h2>
          <p>Sharp Retina captures from the current universal build. No painted interface and no blurred mockup.</p>
        </div>

        <figure className="real-shot shot-ready">
          <div className="shot-glow" aria-hidden="true" />
          <Image
            src="/screenshots/onboarding-ready.png"
            alt="AirFliq ready screen after all four onboarding steps are complete"
            width={1544}
            height={1428}
            quality={100}
            unoptimized
          />
          <figcaption><b>01</b><span>Four transparent steps. One clear finish.</span></figcaption>
        </figure>
      </section>

      <section className="moves shell">
        <article className="move-card move-shortcut">
          <div className="move-copy"><span>01</span><h3>Your shortcut.<br />Your muscle memory.</h3><p>Pick a safe preset or record your own global combination. The whole orbit moves when your selection changes.</p></div>
          <div className="shortcut-orbit" aria-hidden="true">
            <i className="orbit-ring ring-one" /><i className="orbit-ring ring-two" />
            <span className="key key-a">⌃⌥A</span><span className="key key-b">F13</span><span className="key key-c">⌘⇧D</span>
            <strong><small>YOUR GESTURE</small>⌘⌥⇧A</strong>
          </div>
        </article>

        <article className="move-card move-drag">
          <div className="move-copy"><span>02</span><h3>The target meets<br />your cursor.</h3><p>Start dragging a file and AirFliq appears beside it. Hover, release, and get a clear completion response.</p></div>
          <div className="drag-scene" aria-hidden="true">
            <span className="drag-cursor">➤</span>
            <div className="drag-file"><i>IMG</i><small>photo.heic</small></div>
            <div className="drag-target"><i /><Image src={icon} alt="" width={62} height={62} unoptimized /><span>Release to send</span></div>
          </div>
        </article>

        <article className="move-card move-native">
          <div className="move-copy"><span>03</span><h3>Native where<br />it matters.</h3><p>AirFliq prepares the selection. Apple&apos;s own AirDrop panel handles nearby devices and the transfer.</p></div>
          <div className="native-scene" aria-hidden="true">
            <span className="native-ring r1" /><span className="native-ring r2" /><span className="native-ring r3" />
            <Image src={icon} alt="" width={74} height={74} unoptimized />
            <i className="device one">Mac</i><i className="device two">iPhone</i>
          </div>
        </article>
      </section>

      <section className="shortcut-proof shell">
        <div className="proof-copy">
          <p className="eyebrow"><i /> Designed, not configured around you</p>
          <h2>Make the launch gesture yours.</h2>
          <p>Eight presets, one custom recorder, and a fully animated orbit that shows exactly what changed.</p>
          <ul><li><i>✓</i> Global and conflict-aware</li><li><i>✓</i> Editable again from the menu bar</li><li><i>✓</i> Stored locally on your Mac</li></ul>
        </div>
        <figure className="real-shot shot-shortcut">
          <Image
            src="/screenshots/onboarding-shortcut.png"
            alt="AirFliq shortcut selection step with the animated shortcut orbit"
            width={1544}
            height={1428}
            quality={100}
            unoptimized
          />
        </figure>
      </section>

      <section className="privacy" id="privacy">
        <div className="shell privacy-grid">
          <div className="privacy-visual" aria-hidden="true">
            <span className="privacy-wave w1" /><span className="privacy-wave w2" /><span className="privacy-wave w3" />
            <Image src={icon} alt="" width={126} height={126} unoptimized />
            <i className="privacy-lock">✓</i>
          </div>
          <div className="privacy-copy">
            <p className="eyebrow"><i /> Privacy by architecture</p>
            <h2>Your files never take a detour.</h2>
            <p>No AirFliq account, no file cloud, and no Full Disk Access. You choose the folders and Apple moves the files.</p>
            <div className="privacy-points"><span><b>01</b>User-selected folders only</span><span><b>02</b>No file names or contents collected</span><span><b>03</b>Purchases verified without file access</span></div>
            <a className="inline-link" href="/privacy">Read the privacy details <b>→</b></a>
          </div>
        </div>
      </section>

      <section className="trial shell" id="trial">
        <div className="trial-card">
          <div className="trial-aura" aria-hidden="true" />
          <Image src={icon} alt="AirFliq app icon" width={104} height={104} unoptimized />
          <p className="eyebrow"><i /> Seven days. Everything unlocked.</p>
          <h2>Try the complete workflow.<br />Keep it for <em>$4.99.</em></h2>
          <p className="trial-lead">One lifetime purchase through the Mac App Store. No subscription and no send counter.</p>
          <div className="trial-timeline" aria-label="7-day trial timeline">
            <span className="timeline-fill" /><i className="day active">1</i><i>2</i><i>3</i><i>4</i><i>5</i><i>6</i><i>7</i><b>∞</b>
          </div>
          <div className="trial-actions">
            <a className="button button-primary" href={github} target="_blank" rel="noreferrer"><span>Follow the public release</span><b>↗</b></a>
            <span className="store-note"><i></i><b>Mac App Store</b><small>Listing in preparation</small></span>
          </div>
        </div>
      </section>

      <section className="faq shell" id="faq">
        <div className="faq-heading"><p className="eyebrow"><i /> Good to know</p><h2>Clear answers.<br />No fine print.</h2></div>
        <div className="faq-list">
          {faqs.map(([question, answer], index) => (
            <details key={question} open={index === 0}>
              <summary><span>{question}</span><i>+</i></summary>
              <p>{answer}</p>
            </details>
          ))}
        </div>
      </section>

      <footer>
        <div className="shell footer-inner">
          <a href="#top"><AppMark small /></a>
          <p>Built in public for macOS.</p>
          <div><a href="/privacy">Privacy</a><a href="/support">Support</a><a href={github} target="_blank" rel="noreferrer">GitHub</a></div>
        </div>
      </footer>
    </main>
  );
}
