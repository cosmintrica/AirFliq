# AirFliq App Store metadata

## Name

AirFliq

## Subtitle

Send files in one move

## Promotional text

Select, shortcut, send. AirFliq opens Apple's native AirDrop panel from Finder, the menu bar, right-click, or a magnetic drag target.

## Description

Send files with AirDrop in one move.

AirFliq removes the repetitive steps between selecting a file and opening Apple's native AirDrop panel. Choose the workflow that feels natural and keep your focus where it belongs.

FOUR WAYS TO SEND

• Select files in Finder and press your global shortcut
• Send directly from Finder's right-click menu
• Open AirDrop from the menu bar
• Drag files onto the magnetic target beside your cursor

YOUR SHORTCUT, YOUR WAY

Choose a preset or record your own safe global shortcut during setup. You can change it whenever you want.

SMART FOLDER ACCESS

AirFliq asks only for the folders you choose. If a file needs access, the app explains why and lets you grant that folder without requesting Full Disk Access.

NATIVE, PRIVATE, FAST

AirFliq opens the native macOS AirDrop panel. Files are not uploaded to an AirFliq server, and no AirFliq account is required.

Choose when to start a free 7-day trial of every feature. It does not renew and does not charge you. After the trial, keep full access with a one-time AirFliq Pro purchase at the localized App Store price.

Requires macOS 13 or later and a Mac that supports AirDrop.

## Keywords

airdrop,files,finder,shortcut,share,transfer,productivity,menu bar,right click,drag drop

## Support URL

https://airfliq.vercel.app/support

## Marketing URL

https://airfliq.vercel.app

## Privacy Policy URL

https://airfliq.vercel.app/privacy

## Copyright

2026 Cosmin Trica

## Version 1.0 release notes

AirFliq's first release brings one-move AirDrop from Finder, global shortcuts, right-click, the menu bar, and a magnetic drag target.

## App Review notes

AirFliq does not require an account or sign-in.

The app opens Apple's native AirDrop panel. A reviewer can test the complete flow without a second nearby Apple device by selecting a file, using any AirFliq launch method, and then closing the native AirDrop panel.

The main app includes the `com.apple.security.temporary-exception.apple-events` entitlement scoped only to `com.apple.finder`. AirFliq sends a read-only Apple Event to Finder only after the user invokes Send Finder Selection from the menu bar or global shortcut. The event returns the URLs of the items currently selected in Finder. AirFliq does not automate other Finder actions and does not use Apple Events to read file contents.

The Finder extension provides the separate right-click workflow. Folder contents are accessed only through folders explicitly selected by the user and persisted with app-scoped security bookmarks. Full Disk Access is never requested.

AirFliq follows App Review Guideline 3.1.1 for a non-subscription trial. The trial does not begin on download, first launch, onboarding, or a send attempt.

Before activation, the paywall states that the trial lasts 7 days; Finder selection, global shortcut, right-click, menu bar and drag-to-send will stop sending after it ends; there is no auto-renewal or automatic charge; and the one-time Lifetime Pro price is shown using the current storefront's localized StoreKit price when available.

The reviewer starts the trial explicitly with the `7-day Trial` button. This purchases the Price Tier 0 Non-Consumable IAP named exactly `7-day Trial`, product ID `com.cosmintrica.airfliq.trial7day`, through RevenueCat. Before presenting the sheet, AirFliq requires StoreKit to report a zero-priced Non-Consumable product. AirFliq derives the trial start from an App Store or Mac App Store transaction purchase date in RevenueCat CustomerInfo and evaluates expiry against CustomerInfo requestDate. Local preferences and the Mac system clock cannot start or extend the App Store trial.

The trial product is not attached to RevenueCat entitlement `Pro`. Only the paid Non-Consumable `com.cosmintrica.airfliq.lifetime` grants `Pro` and permanently unlocks AirFliq. Restore Purchase restores both an existing trial transaction and Lifetime Pro state for the Apple Account.
