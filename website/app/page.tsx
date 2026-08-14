import Image from "next/image";

const icon = "/assets/airfliq-icon.png";

const features = [
  {
    index: "01",
    title: "One shortcut",
    copy: "Select in Finder, press Control + Option + A, and the native AirDrop panel is ready.",
    className: "feature-card feature-wide feature-blue",
    visual: <div className="shortcut-visual" aria-hidden="true"><span>⌃</span><span>⌥</span><span>A</span></div>,
  },
  {
    index: "02",
    title: "Right where you click",
    copy: "Send with AirFliq sits directly in Finder's context menu, exactly where the file already is.",
    className: "feature-card feature-violet",
    visual: <div className="menu-visual" aria-hidden="true"><span>Open</span><span>Quick Look</span><strong>✦ Send with AirFliq</strong></div>,
  },
  {
    index: "03",
    title: "Drag. Drop. Fliq.",
    copy: "Start dragging and a responsive target glides in beside your cursor. Release and watch it confirm the handoff.",
    className: "feature-card feature-cyan",
    visual: <div className="drop-visual" aria-hidden="true"><div className="drop-orbit" /><Image src={icon} alt="" width={56} height={56} /><span>Release to send</span></div>,
  },
  {
    index: "04",
    title: "Native all the way",
    copy: "AirFliq prepares the files. Apple's own AirDrop panel handles device discovery and transfer.",
    className: "feature-card feature-wide feature-ink",
    visual: <div className="native-visual" aria-hidden="true"><div className="native-device"><i /><span>Your Mac</span></div><div className="native-device"><i /><span>Nearby device</span></div><div className="native-radar r1" /><div className="native-radar r2" /></div>,
  },
];

const faqs = [
  ["Does AirFliq replace AirDrop?", "No. It removes the repetitive steps before Apple's native panel. Discovery and transfer stay entirely macOS-native."],
  ["Which files can I send?", "AirFliq accepts files, folders and packages that Apple's system sharing service can send. It also waits for iCloud items to download."],
  ["Does it need Full Disk Access?", "No. You choose folders yourself. If a later send needs another folder, AirFliq explains why and asks for that location only."],
  ["What is included for free?", "Your first 50 successful send sessions are free. Cancels and failed attempts never consume one."],
  ["Does it work on Intel Macs?", "Yes. The app, Finder extension and RevenueCat integration ship as universal Apple Silicon and Intel binaries."],
];

export default function Home() {
  return (
    <main>
      <nav className="nav shell" aria-label="Main navigation">
        <a className="brand" href="#top" aria-label="AirFliq home"><Image src={icon} alt="" width={38} height={38} priority /><span>AirFliq</span></a>
        <div className="nav-links"><a href="#features">Features</a><a href="#privacy">Privacy</a><a href="#faq">FAQ</a></div>
        <a className="nav-cta" href="#pricing">50 sends free</a>
      </nav>

      <section className="hero shell" id="top">
        <div className="hero-copy">
          <div className="eyebrow"><span /> AirDrop, accelerated</div>
          <h1>Select.<br /><em>Fliq. Sent.</em></h1>
          <p>Send from Finder in one move with a shortcut, right-click, the menu bar, or one beautiful drop target.</p>
          <div className="hero-actions">
            <a className="primary-cta" href="#pricing"><span>Try 50 sends free</span><small>Then $4.99 Lifetime Pro</small></a>
            <a className="text-cta" href="#story">See the move <b>↓</b></a>
          </div>
          <div className="compatibility"><span>macOS 13+</span><i /><span>Apple Silicon</span><i /><span>Intel</span></div>
        </div>

        <div className="hero-stage" aria-label="A sharp animated preview of AirFliq">
          <div className="stage-glow" />
          <div className="finder-window">
            <div className="window-bar"><div><i /><i /><i /></div><span>Downloads</span><b>•••</b></div>
            <div className="finder-body"><div className="sidebar-lines"><i /><i /><i /><i /></div><div className="file-grid">
              <div className="file-card selected"><span className="file-icon">JPG</span><small>Launch.jpg</small></div>
              <div className="file-card selected"><span className="file-icon doc">PDF</span><small>Brief.pdf</small></div>
              <div className="file-card"><span className="file-icon folder" /><small>Archive</small></div>
            </div></div>
          </div>
          <div className="keystroke" aria-hidden="true"><span>⌃</span><span>⌥</span><span>A</span></div>
          <div className="flight-path" aria-hidden="true"><i /><i /><i /><i /><i /></div>
          <div className="hero-drop-card"><div className="hero-drop-ring" /><Image src={icon} alt="" width={55} height={55} priority /><strong>Ready to fliq</strong><small>2 items queued</small></div>
          <div className="time-chip"><b>26 min</b> saved this week</div>
        </div>
      </section>

      <section className="proof-strip"><div className="shell proof-inner"><span>Four gestures</span><i /><span>One native panel</span><i /><span>Zero cloud uploads</span><i /><span>Universal Mac app</span></div></section>

      <section className="story-section shell" id="story">
        <span className="section-kicker">One small move</span>
        <div className="story-track" aria-hidden="true"><span className="story-file">PDF</span><i /><i /><i /><Image src={icon} alt="" width={60} height={60} /><i /><i /><i /><span className="story-check">✓</span></div>
        <h2>The distance between<br />selected and sent just disappeared.</h2>
      </section>

      <section className="section shell" id="features">
        <div className="section-heading"><div><span className="section-kicker">Four ways to fliq</span><h2>Your fastest move<br />is already here.</h2></div><p>AirFliq meets you where your files already are. Every path ends in the same trusted macOS experience.</p></div>
        <div className="feature-grid">{features.map((feature) => <article className={feature.className} key={feature.index}><div className="feature-top"><span>{feature.index}</span><h3>{feature.title}</h3><p>{feature.copy}</p></div>{feature.visual}</article>)}</div>
      </section>

      <section className="how-section"><div className="shell how-grid">
        <div className="how-copy"><span className="section-kicker">Permission, with a reason</span><h2>Ask only<br />when needed.</h2><p>You choose the first folders. If a future send needs another one, AirFliq names the exact folder and asks in context. No Full Disk Access.</p></div>
        <div className="setup-card">
          <div className="setup-head"><Image src={icon} alt="" width={46} height={46} /><div><strong>AirFliq</strong><small>Setup & Permissions</small></div><span>1.0</span></div>
          {[["Finder access", "See your current selection"], ["Folder access", "Only folders you choose"], ["Right-click menu", "Send directly from Finder"]].map(([title, copy], index) => <div className="setup-row" key={title}><i style={{ animationDelay: `${index * 0.4}s` }}>✓</i><div><strong>{title}</strong><small>{copy}</small></div><span>{index === 1 ? "Manage" : "Ready"}</span></div>)}
          <div className="setup-ready">Done - start sending</div>
        </div>
      </div></section>

      <section className="section shell privacy-section" id="privacy">
        <div className="privacy-orb" aria-hidden="true"><Image src={icon} alt="" width={120} height={120} /><span className="orbit orbit-a"><i>⌁</i></span><span className="orbit orbit-b"><i>✓</i></span><span className="orbit orbit-c"><i>⌘</i></span></div>
        <div className="privacy-copy"><span className="section-kicker">Privacy by architecture</span><h2>Your files never<br />take a detour.</h2><p>No AirFliq account. No file cloud. No file-name analytics. Your files move through Apple&apos;s native sharing service, directly from your Mac.</p><ul><li><i>✓</i> No Full Disk Access</li><li><i>✓</i> User-selected folders only</li><li><i>✓</i> No file uploads or storage</li></ul></div>
      </section>

      <section className="pricing-section" id="pricing"><div className="pricing-glow" /><div className="pricing-content shell">
        <Image src={icon} alt="AirFliq app icon" width={92} height={92} />
        <span className="section-kicker">Fifty are on us</span><h2>Feel the faster workflow.<br />Keep it forever.</h2>
        <div className="free-meter"><span style={{ width: "62%" }} /><b>50 successful sends free</b></div>
        <div className="price"><sup>$</sup>4.99 <span>lifetime</span></div><p>One purchase through the Mac App Store. No subscription.</p>
        <a className="primary-cta pricing-cta" href="https://github.com/cosmintrica/AirFliq"><span>Follow the public build</span><small>#Shipaton 2026</small></a>
      </div></section>

      <section className="section shell faq-section" id="faq"><div className="faq-heading"><span className="section-kicker">Good to know</span><h2>Questions,<br />answered.</h2></div><div className="faq-list">{faqs.map(([question, answer], index) => <details key={question} open={index === 0}><summary><span>{question}</span><i>+</i></summary><p>{answer}</p></details>)}</div></section>

      <footer><div className="shell footer-inner"><a className="brand" href="#top"><Image src={icon} alt="" width={29} height={29} /><span>AirFliq</span></a><p>Select. Fliq. Sent.</p><div><a href="/privacy">Privacy</a><a href="/support">Support</a><a href="https://github.com/cosmintrica/AirFliq">GitHub</a></div></div></footer>
    </main>
  );
}
