export const overview = {
  name: "AirFliq",
  pitch: "AirDrop from Finder in one move.",
};

export const story = `## Inspiration

AirDrop is fast once its native panel is open, but reaching that panel repeatedly interrupts the flow. AirFliq started with one question: what if sending a file felt like one continuous gesture instead of a sequence of Finder menus?

Every launch method had to feel immediate, every permission had to be transparent, and every animation had to communicate state instead of merely decorating it.

## What it does

AirFliq gives Mac users four fast ways to prepare files for AirDrop:

- Select files in Finder and press a configurable global shortcut.
- Send directly from Finder's right-click menu.
- Open the native AirDrop flow from the menu bar.
- Drag files onto a magnetic target that appears beside the cursor.

AirFliq opens Apple's native AirDrop panel. It does not upload files to an AirFliq server and does not require an account. Folder access is user-selected and requested only when a chosen file needs it. Users explicitly start a free seven-day trial that never renews or charges automatically, then can keep the complete experience with a one-time Lifetime Pro purchase powered by RevenueCat.

## How we built it

AirFliq is built natively for macOS with Swift 6, SwiftUI, AppKit, FinderSync, Carbon hot keys, and the RevenueCat Apple SDK. The release binary is universal and supports both Apple Silicon and Intel Macs.

AppKit owns Finder selection access, drag routing, the menu bar panel, non-activating floating windows, and the native AirDrop handoff. SwiftUI renders onboarding, permission state, paywall, shortcuts, notifications, and the animated drag experience. RevenueCat manages the non-consumable Lifetime Pro entitlement and restore flow.

The landing page, privacy policy, and support pages are deployed on Vercel. GitHub Actions rebuilds the universal app and validates the website.

## Challenges

macOS permissions are intentionally strict, and each permission has different lifecycle behavior. The hardest part was making setup feel calm while Finder Automation, folder security-scoped access, and the Finder extension changed state outside the app.

The drag target required a careful bridge between AppKit and SwiftUI. AppKit owns the complete drop surface so the icon cannot intercept a file, while SwiftUI renders hover, attraction, launch, and completion as one continuous state machine.

We also designed trial and purchase behavior so opening or cancelling Apple's AirDrop panel never starts the trial or changes access. The trial begins only after the user explicitly confirms its free App Store product and RevenueCat reports the verified transaction.

## Accomplishments that we're proud of

- Four coherent launch methods around one native AirDrop flow.
- A permission model that never requests Full Disk Access.
- User-selected folder boundaries with contextual recovery.
- A configurable global shortcut with safe presets and collision handling.
- A universal ARM64 and x86_64 build under Swift 6 strict concurrency.
- A seven-day full-access trial and one-time Lifetime Pro purchase through RevenueCat.
- Native, state-driven onboarding and drag animations designed for macOS.

## What we learned

The fastest workflow is not simply the one with the fewest controls. It is the one that makes the next action obvious and preserves trust. Permission copy, transition timing, cancellation behavior, and native placement mattered as much as the AirDrop invocation itself.

Building in public made visual defects and interaction friction impossible to ignore. Repeated screenshots and concrete feedback led to narrower folder permissions, a custom shortcut step, better drag hit testing, clearer completion feedback, and a more coherent menu bar experience.

## What's next for AirFliq

- Ship the first public App Store version during the Shipaton window.
- Measure trial activation, paywall conversion, restores, and real purchase revenue through RevenueCat.
- Use launch feedback to refine timing, accessibility, and recovery flows.
- Expand localization and continue publishing product decisions and measurable results in public.`;

export const builtWith =
  "Swift, SwiftUI, AppKit, macOS, FinderSync, RevenueCat, RevenueCat SDK, Carbon HIToolbox, ServiceManagement, security-scoped bookmarks, global hotkeys, drag and drop, menu bar app, Finder extension, Apple Events, universal binary, Apple Silicon, Intel Mac, Swift 6, in-app purchases, Next.js, React, TypeScript, Vercel, GitHub Actions";

export const links = [
  "https://airfliq.vercel.app",
  "https://github.com/cosmintrica/AirFliq",
];

export const buildInPublic = `Building in public turned every rough edge into a concrete product decision. Sharing frequent screenshots and interaction recordings created accountability and made visual defects impossible to dismiss. Feedback led directly to user-selected folder permissions instead of Full Disk Access, a dedicated shortcut configuration step, better drag hit testing, clearer completion feedback, and a more coherent menu bar experience. We will keep sharing the release, conversion experiments, and lessons after launch.`;

export const buildInPublicLinks =
  "https://x.com/cosmintrica/status/2088397113910505585";

export const hamm = `AirFliq uses a simple, user-aligned model: the user explicitly starts a free seven-day full-access trial that never renews or charges automatically, followed by an optional one-time $4.99 Lifetime Pro purchase. RevenueCat verifies the trial transaction and non-consumable entitlement and powers purchase restoration. We chose lifetime pricing because AirFliq is a focused utility with durable value rather than an ongoing content service. The offer is available from the menu and appears when a send needs access, so no action silently starts the trial. Conversion and revenue results will be added after the App Store launch.`;

export const designAward = `AirFliq treats motion as product feedback. The onboarding path connects four setup steps with a state-driven flight route, animated completion marks, and a final ready state. Shortcut selection uses a constellation whose complete cards exchange positions instead of replacing only their labels. The magnetic drag target moves beside the cursor and transitions through waiting, attraction, launch, and completion without interrupting the native drag session. The menu bar panel, paywall, notifications, troubleshooting, and folder-access recovery share one restrained visual language designed specifically for macOS.`;

export const productivityAward = `AirFliq is built for Apple power users who repeatedly move files and documents from Finder. It removes navigation overhead while preserving the native AirDrop destination experience. Users can act from the current Finder selection, a configurable global shortcut, the right-click menu, the menu bar, or a magnetic drag target. The product stays focused on speed, predictable organization through Finder, and a polished interaction model rather than becoming another file manager.`;

export const judgeNotes = `AirFliq is a macOS-only utility. The public App Store URL, final demo video, production purchase verification, and post-launch metrics will be added before submission. The seven-day trial provides full access without a promo code. No project submission should be finalized until those items are verified.`;
