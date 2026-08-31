# AirFliq - RevenueCat Shipaton 2026 submission draft

Status: Devpost registration is complete. The project submission is still a draft and must not be submitted until the App Store listing is live and every requirement below is verified.

## Project name

AirFliq

## Tagline

AirDrop from Finder in one move.

## Short pitch

AirFliq is a native macOS utility that removes the repetitive steps between selecting a file and opening Apple's AirDrop panel. Send from a global shortcut, Finder's right-click menu, the menu bar, or a magnetic drag target that appears beside the cursor.

## Inspiration

AirDrop is fast once its native panel is open, but reaching that panel repeatedly interrupts the flow. AirFliq started with a small question: what if sending a file felt like one continuous gesture instead of a sequence of Finder menus?

The product grew around that constraint. Every launch method had to feel immediate, every permission had to be transparent, and every animation had to communicate state instead of decorating it.

## What it does

AirFliq gives Mac users four fast ways to prepare files for AirDrop:

- Select files in Finder and press a configurable global shortcut.
- Send directly from Finder's right-click menu.
- Open the native AirDrop flow from the menu bar.
- Drag files onto a magnetic target that appears beside the cursor.

AirFliq opens Apple's native AirDrop panel. It does not upload files to an AirFliq server and does not require an account. Folder access is user-selected and requested only when a chosen file needs it. Users explicitly start a free seven-day trial that never renews or charges automatically, then can keep the complete experience with a one-time Lifetime Pro purchase powered by RevenueCat.

## How we built it

AirFliq is built natively for macOS with Swift 6, SwiftUI, AppKit, FinderSync, Carbon hot keys, and the RevenueCat Apple SDK. The release binary is universal and supports both Apple Silicon and Intel Macs.

AppKit owns the system-level behavior: Finder selection access, drag routing, the menu bar panel, non-activating floating windows, and the native AirDrop handoff. SwiftUI renders onboarding, permission state, paywall, shortcuts, notifications, and the animated drag experience. RevenueCat manages the non-consumable Lifetime Pro entitlement and restore flow.

The landing page, privacy policy, and support pages are deployed on Vercel. CI rebuilds the universal app and validates the website on every push.

## Challenges

macOS permissions are intentionally strict, and each permission has different lifecycle behavior. The hardest part was making setup feel calm while Finder Automation, folder security-scoped access, and the Finder extension changed state outside the app.

The drag target also required a careful bridge between AppKit and SwiftUI. AppKit must own the complete drop surface so the icon cannot intercept the file, while SwiftUI must render hover, attraction, launch, and completion as one continuous state machine.

Finally, App Store purchases must remain trustworthy. Opening or cancelling the native AirDrop panel never starts the trial or changes access. The App Store trial begins only after the user explicitly confirms its free product and RevenueCat reports the verified transaction.

## Accomplishments

- Four coherent launch methods around one native AirDrop flow.
- A permission model that never requests Full Disk Access.
- User-selected folder boundaries with contextual recovery when access is missing.
- A fully configurable global shortcut with safe presets and collision handling.
- A universal ARM64 and x86_64 release build under Swift 6 strict concurrency.
- A seven-day full-access trial and one-time Lifetime Pro purchase through RevenueCat.
- Native, state-driven onboarding and drag animations designed specifically for macOS.

## What we learned

The fastest workflow is not the one with the fewest visible controls. It is the one that makes the next action obvious and preserves user trust. Permission copy, transition timing, cancellation behavior, and native placement mattered as much as the core AirDrop invocation.

Building in public made visual defects and interaction friction impossible to ignore. Repeated screenshots and concrete feedback led to narrower folder permissions, a custom shortcut step, better drag hit testing, clearer completion feedback, and a more coherent menu bar experience.

## What's next

- Ship the first public App Store version during the Shipaton submission window.
- Measure trial activation, paywall conversion, restores, and real purchase revenue through RevenueCat.
- Use launch feedback to refine timing, accessibility, and recovery flows.
- Expand localization and continue publishing product decisions and measurable results in public.

## RevenueCat integration

- Product: AirFliq Lifetime Pro
- Type: non-consumable in-app purchase
- Price: $4.99 lifetime
- Trial: a free seven-day non-consumable started explicitly by the user, with no renewal or automatic charge
- Entitlement behavior: permanent unlock after a verified purchase
- Restore Purchases: supported
- Required before submission: production Apple SDK key, first Store API call, one verified sandbox purchase, and one real purchase after release

## Best-fit categories

1. RevenueCat Design Award
   - Highlight the permission journey, shortcut constellation, magnetic drag target, native transitions, and interaction polish.
2. #BuildInPublic Award
   - Submit links to every public build update and explain which feedback changed the product.
3. HAMM Award
   - Explain the seven-day full trial, $4.99 lifetime price, paywall rationale, and RevenueCat conversion data.
4. Influencer Award - Productivity: Christopher Lawley
   - AirFliq is a focused Apple power-user utility for moving selected files and documents quickly.
5. Grand Prize
   - Eligible automatically, but needs post-launch installs, active users, paying customers, conversion, revenue, and growth experiments.

AirFliq should not enter sponsor categories that require unrelated integrations merely to qualify. OneSignal, Layers, Noise, Replit, Kotlin Multiplatform, Samsung Galaxy, RevenueCat Funnels, and Stripe should be used only if they become a genuine part of the product or launch strategy.

## Demo video outline - under two minutes

1. 0:00-0:08 - The problem: too many steps between a selected file and AirDrop.
2. 0:08-0:23 - Finder selection plus global shortcut.
3. 0:23-0:38 - Finder right-click menu.
4. 0:38-0:53 - Magnetic drag target, hover, drop, and completion feedback.
5. 0:53-1:08 - Menu bar launch and shortcut customization.
6. 1:08-1:25 - User-selected folder access and contextual permission recovery.
7. 1:25-1:40 - Seven-day trial, RevenueCat paywall, purchase, and restore.
8. 1:40-1:52 - Native AirDrop panel and privacy statement.
9. 1:52-1:58 - AirFliq logo, website, and #Shipaton.

The final video must be public on YouTube or Vimeo, show the real macOS app running on a Mac, avoid unlicensed music and unrelated third-party trademarks, and remain under two minutes. Devpost's generic form also recognizes Youku, but the Shipaton rules specifically require YouTube or Vimeo, so AirFliq should use YouTube.

Record a clean native macOS screencast with narration. Open with the elevator pitch in the first eight seconds, show the actual interactions rather than a marketing montage, edit out permission waits and failed takes, and demonstrate the trial, paywall, purchase, and restore inside the same sub-two-minute video. Upload early enough for YouTube processing and verify playback while signed out.

## Devpost media roles

- Project thumbnail: a polished 3:2 marketing image for the Devpost gallery card.
- Image gallery: real product screenshots and optional supporting marketing images, each under 5 MB.
- Required Shipaton screenshot: at least one real app screenshot at exactly 1179 by 2556 pixels, without a Mac, laptop, phone, or other device mockup frame.
- App icon: an uncropped 1024 by 1024 image.

For the macOS app, the exact portrait screenshot can contain multiple native AirFliq windows arranged on one 1179 by 2556 canvas, but every visible interface must come from a real app capture. Upload the raw native window captures to the gallery as additional proof.

## Required submission assets

- [ ] Public App Store URL, accessible from the United States.
- [ ] Public YouTube or Vimeo demo URL.
- [ ] 1024 by 1024 app icon.
- [ ] Upload `marketing/shipaton/assets/airfliq-app-screenshot-1179x2556.jpg`
  as the required 1179 by 2556 screenshot without a device frame. Use the JPEG,
  because the lossless PNG source exceeds Devpost's 5 MB upload limit.
- [ ] English project description and testing instructions.
- [ ] Seven-day trial verified, or an App Store promo code for judges.
- [ ] Public #Shipaton post links.
- [ ] Growth and monetization results added after launch.
- [ ] RevenueCat project connected to the real App Store product.
- [ ] First real purchase recorded before September 30, 2026.

## Important dates in Romania time

- Registration and submission close: October 1, 2026 at 09:45 EEST.
- Judging begins: October 1, 2026 at 10:00 EEST.
- Judging ends: October 13, 2026 at 22:00 EEST.
- Winners announced: October 21, 2026.

Store review can take several days. The release should be submitted well before the final week.

## Stronger follow-up post

Building AirFliq for #Shipaton: AirDrop in one move on macOS. Select files, then use a shortcut, right-click, the menu bar, or a magnetic drag target. Native Swift. A 7-day full trial powered by @RevenueCat. What should I polish next? #BuildInPublic

Attach a crisp native screen recording or screenshot and include the published landing-page URL in the first reply.
