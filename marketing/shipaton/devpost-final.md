# AirFliq — final Devpost copy (Shipaton 2026)

Deadline: **October 1, 12:00 PM Pacific = 22:00 EEST**. After it, the submission is locked.
Judge instructions without codes: [judge-testing-instructions.md](judge-testing-instructions.md). The copy with the private offer codes lives in `build/judge-access/` (gitignored).

## Name and tagline

**AirFliq** — AirDrop from Finder in one move.

## Links

- App Store (US): https://apps.apple.com/us/app/airfliq/id6801543708
- Website: https://airfliq.vercel.app
- Source: https://github.com/cosmintrica/AirFliq
- Demo video (public): https://youtu.be/d5o6kD_NpCk
- RevenueCat project ID: `cc3eb2b7` (confirm in the dashboard before submitting)

## Story

### Inspiration

AirDrop is fast once its panel is open, but reaching that panel interrupts the flow: select, Share, AirDrop, wait. AirFliq started with one question: what if sending a file felt like one continuous gesture?

### What it does

AirFliq is a native macOS menu bar utility that opens Apple's AirDrop panel in one move, from wherever you already are:

- Finder's right-click menu: **Send with AirFliq**.
- A global shortcut (default ⌃⌥A, fully customizable) that opens the native file picker.
- The menu bar.
- A magnetic drag target that appears beside your cursor while you drag a file. Drop it and the card folds into a paper plane that flies off the screen while AirDrop opens.

Files go through Apple's own AirDrop. Nothing is uploaded to an AirFliq server, there is no account, and AirFliq only reads folders the user chooses. It never asks for Full Disk Access.

### Monetization with RevenueCat

- **Free forever:** 5 sends a day on every route, no trial needed.
- **7-day trial of unlimited sending:** a free App Store product the user starts explicitly; it never renews or charges.
- **Lifetime Pro:** one purchase, unlimited forever.

RevenueCat verifies the trial and the non-consumable Lifetime entitlement, powers restore, and syncs App Store offer-code redemptions. The trial's start date comes from the verified transaction, not the Mac's clock.

### How we built it

Swift 6 with strict concurrency, SwiftUI and AppKit, a FinderSync extension, Carbon hot keys, security-scoped bookmarks, StoreKit offer-code redemption and the RevenueCat SDK. It is a universal binary for Apple Silicon and Intel, built and archived by Xcode Cloud.

### Challenges

macOS permissions change outside the app. The Finder extension lives deep in System Settings, and on managed Macs it can be blocked by policy. Our first public release could leave people stuck on that step. Version 1.0.1:

- makes every optional step skippable, so setup always finishes;
- shows an animated miniature of the exact clicks before opening System Settings;
- docks a small guide beside System Settings that confirms the switch the moment macOS reports it.

The drag target needs AppKit to own the drop surface while SwiftUI renders hover, attraction and release. The release animation runs in a separate click-through overlay, so it never delays the AirDrop handoff.

### Accomplishments

- Four routes around one native AirDrop flow.
- A free tier that is genuinely useful, and an honest trial.
- Setup that always finishes, with a guide that finds the Finder extension for you.
- A signature release moment: the card folds into a paper plane and flies off the screen, built with Core Animation at the display's refresh rate.

### What we learned

Real users found the blocker within hours of launch: a setup that cannot finish loses the user. Optional means skippable. Trust also comes from small things: a free send is used only when AirDrop really sends. On macOS 27 a cancelled AirDrop panel reports the same "shared" result as a real send, so AirFliq tells them apart by the AirDrop radio traffic before counting.

### What's next

- Measure trial starts, conversions and restores in RevenueCat.
- Localize the app.
- Bring the paper-plane confirmation to every route.

## RevenueCat Design Award

AirFliq treats motion as feedback:

- **Setup:** a flight route connects the setup steps. A comet travels each new connection; skipped steps stay visibly optional.
- **Finder extension guide:** loops the exact clicks in a miniature System Settings and resolves the moment the switch flips.
- **Drag target:** the target leans toward the dragged file. It shows the file's icon docking beside AirFliq's and pulls light inward like a gravity well. On release the card squashes, folds into a paper plane and fliqs off the screen on a curved path, trailing sparks.
- **Respect for the user:** every effect respects Reduce Motion, and none of them delays the native AirDrop panel.

## HAMM Award

AirFliq is freemium with a lifetime unlock:

- 5 free sends every day keep the app useful forever.
- An explicit 7-day trial of unlimited sending lets people feel the difference.
- A one-time Lifetime Pro purchase fits a focused utility.

RevenueCat supplies the verified trial transaction, the Pro entitlement, restore and offer-code sync. The offer screen explains exactly what happens when the trial ends: you keep the free daily sends, nothing renews and nothing charges. We have not invented any conversion data; results will be added from the RevenueCat dashboard once there is real traffic.
