# AirFliq App Store metadata

## Name

AirFliq

## Subtitle

Send files in one move

## Promotional text

Choose, shortcut, send. AirFliq opens Apple's native AirDrop panel from Finder, the menu bar, right-click, or a magnetic drag target.

## Description

Send files with the native AirDrop panel.

AirFliq offers convenient ways to choose files and open Apple's native AirDrop panel. Choose the workflow that feels natural and keep your focus where it belongs.

FOUR WAYS TO SEND

• Press your global shortcut, choose files or folders, and send
• Send directly from Finder's right-click menu
• Choose files to send from the menu bar
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

The Mac App Store build does not request Apple Events, Automation access, scripting targets or temporary sandbox exceptions. The global shortcut and the “Choose files to send…” menu action open NSOpenPanel so the user explicitly selects files or folders. Cancelling the picker sends nothing.

For an existing Finder selection, enable the bundled Finder Sync extension in System Settings and choose “Send with AirFliq” from the selection’s contextual menu. The extension gets selected URLs using FIFinderSyncController.selectedItemURLs() and passes the selection paths to its host through a validated custom URL command using NSWorkspace. The command grants no file access: if the host needs access, it opens the native folder picker at the required folder. Allow & Continue saves a read-only security-scoped bookmark and resumes the pending send automatically. Files may also be dropped onto the menu bar icon or the optional drag target. All routes use NSSharingService.sendViaAirDrop.

The original setup walks through file selection, folder access, the Finder extension and shortcut configuration. Folder contents are accessed only through user-selected items or folders explicitly selected by the user and persisted with app-scoped security bookmarks. Full Disk Access is never requested.

AirFliq follows App Review Guideline 3.1.1 for a non-subscription trial. The trial does not begin on download, first launch, onboarding, or a send attempt.

Before activation, the paywall states that the trial lasts 7 days; file sharing, global shortcut, right-click, menu bar and drag-to-send will stop sending after it ends; there is no auto-renewal or automatic charge; and the one-time Lifetime Pro price is shown using the current storefront's localized StoreKit price when available.

The reviewer starts the trial explicitly with the `7-day Trial` button. This purchases the Price Tier 0 Non-Consumable IAP named exactly `7-day Trial`, product ID `com.cosmintrica.airfliq.trial7day`, through RevenueCat. Before presenting the sheet, AirFliq requires StoreKit to report a zero-priced Non-Consumable product. AirFliq derives the trial start from an App Store or Mac App Store transaction purchase date in RevenueCat CustomerInfo and evaluates expiry against CustomerInfo requestDate. Local preferences and the Mac system clock cannot start or extend the App Store trial.

The trial product is not attached to RevenueCat entitlement `Pro`. Only the paid Non-Consumable `com.cosmintrica.airfliq.lifetime` grants `Pro` and permanently unlocks AirFliq. Restore Purchase restores both an existing trial transaction and Lifetime Pro state for the Apple Account.
