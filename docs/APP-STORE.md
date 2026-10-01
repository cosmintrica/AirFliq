# AirFliq App Store and RevenueCat checklist

## Product model

- Free download on the Mac App Store.
- Free tier: every route can send 5 times per local calendar day, without a
  trial. Only a share that AirDrop reports as completed counts
  (`FreeSendAllowance` in `Sources/App/Monetization.swift`).
- The App Store build does not start a trial on download or first launch.
- The user explicitly starts the trial by confirming a Price Tier 0
  non-consumable IAP named exactly `7-day Trial`.
- Product identifier: `com.cosmintrica.airfliq.trial7day`.
- The trial unlocks every feature for 7 elapsed days and does not count send
  attempts. It never renews and never charges the user.
- Trial expiry is derived from the verified RevenueCat transaction purchase
  date in `CustomerInfo.nonSubscriptions`, the current SDK name for
  `nonSubscriptionTransactions`. Only App Store or Mac App Store transactions
  are accepted, and RevenueCat's `CustomerInfo.requestDate` is used as the
  trusted current time. Local preferences and the Mac system clock are not
  accepted as App Store trial authority.
- Before presenting the StoreKit sheet, AirFliq rejects the trial product unless
  StoreKit reports both a zero price and the Non-Consumable product type.
- `AirFliq Pro` is a non-consumable Lifetime unlock at $4.99.
- RevenueCat entitlement: `Pro`.
- Suggested product identifier: `com.cosmintrica.airfliq.lifetime`.
- RevenueCat offering: `airfliq`, with the Lifetime product attached.
- Do not attach `com.cosmintrica.airfliq.trial7day` to `Pro` or to any other
  entitlement. The trial transaction is checked independently.

Apple processes payment, VAT or sales tax, refunds and customer receipts for
Mac App Store purchases. RevenueCat synchronizes entitlement state and purchase
restoration. AirFliq should not add Stripe checkout for digital functionality in
the App Store build.

## App Privacy disclosure

For the current anonymous RevenueCat integration, declare `Purchases` in App
Store Connect with both `App Functionality` and `Analytics` as purposes. The
purchase history is not linked to the user's identity and is not used for
tracking. AirFliq does not supply RevenueCat with a custom user ID, advertising
identifier, file name or file content. If customer attributes, advertising
integrations or any identity-linked App User ID are added later, reassess the
App Privacy answers and the public privacy policy before shipping that build.

Keep the public policy at `https://airfliq.vercel.app/privacy` synchronized with
these answers. RevenueCat's current Apple disclosure guidance is at
`https://www.revenuecat.com/docs/platform-resources/apple-platform-resources/apple-app-privacy`.

## Records to create

1. App Store Connect app with bundle ID `com.cosmintrica.airfliq`.
2. Finder extension ID `com.cosmintrica.airfliq.finder`.
3. A non-consumable Lifetime in-app purchase using
   `com.cosmintrica.airfliq.lifetime`.
4. A Price Tier 0 non-consumable named exactly `7-day Trial` using
   `com.cosmintrica.airfliq.trial7day`.
5. Localize the trial IAP name with the equivalent `7-day Trial` convention in
   every supported language and make it available in every app storefront.
6. A RevenueCat project linked to the App Store Connect app.
7. RevenueCat entitlement `Pro`, offering `airfliq`, and Lifetime package.
8. Import the trial product into RevenueCat as a standalone product. Do not add
   it to entitlement `Pro`; the app fetches it directly by product ID.
9. App Store Connect In-App Purchase key uploaded to RevenueCat.

## Trial configuration verification

Before packaging a release, confirm all of the following in App Store Connect
and RevenueCat:

Use the checkbox version at
`marketing/app-store/revenuecat-config-checklist.md` during the final sandbox
test.

- IAP type is Non-Consumable, reference/display name is `7-day Trial`, price is
  Tier 0 and product ID is `com.cosmintrica.airfliq.trial7day`.
- The Lifetime product remains a paid Non-Consumable with product ID
  `com.cosmintrica.airfliq.lifetime`.
- Both IAPs are cleared for sale and have the same storefront availability as
  the AirFliq app, including Romania and the United States.
- Only the Lifetime product grants RevenueCat entitlement `Pro`.
- The `airfliq` current offering contains the Lifetime package. The trial does
  not need an offering because the app uses `Purchases.getProducts` and
  `purchase(product:)`.
- A fresh sandbox Apple Account sees the pre-trial disclosure before the App
  Store sheet, can cancel without starting the clock, and receives full access
  only after CustomerInfo reports the trial transaction.
- A misconfigured paid or non-Non-Consumable trial product is rejected by the
  release build and must not start access.
- Relaunch and Restore Purchase recover the same verified purchase date. Seven
  days after that date, sending returns to the free allowance of 5 sends per
  day until Lifetime Pro is purchased.
- The UI shows the current storefront's localized Lifetime price before the
  user confirms trial activation whenever StoreKit has loaded it.

The public RevenueCat macOS SDK key is injected at build time. Never commit it
or any App Store Connect private key to Git:

```bash
MARKETING_VERSION=1.0.0 \
BUILD_NUMBER=1 \
REVENUECAT_API_KEY="appl_public_key" \
SIGN_IDENTITY="Apple Distribution: Name (TEAMID)" \
INSTALLER_IDENTITY="Mac Installer Distribution: Name (TEAMID)" \
APP_PROFILE="/absolute/path/AirFliq.provisionprofile" \
EXT_PROFILE="/absolute/path/AirFliqFinder.provisionprofile" \
./build-app-store.sh
```

The script verifies the sandbox, privacy manifest, nested framework signature,
and universal ARM64 plus x86_64 binaries. It outputs
`build/AirFliq-AppStore.pkg`.

## Signed package in GitHub Actions

The manual workflow `.github/workflows/app-store-package.yml` builds the same
universal app and Finder extension with stable Xcode 26.6 on GitHub's
`macos-26` runner. It creates a signed installer package, its SHA-256 checksum
and a build manifest. It uploads those files only as a private GitHub Actions
artifact. It does not upload to App Store Connect, create a release or submit
the app for review.

Add these encrypted repository or environment secrets in GitHub under
`Settings > Secrets and variables > Actions`:

| Secret | Exact content |
| --- | --- |
| `AIRFLIQ_APPLE_DISTRIBUTION_P12_BASE64` | Base64 of a `.p12` containing the Apple Distribution application certificate and private key |
| `AIRFLIQ_APPLE_DISTRIBUTION_P12_PASSWORD` | Password used when exporting that application `.p12` |
| `AIRFLIQ_MAC_INSTALLER_DISTRIBUTION_P12_BASE64` | Base64 of a `.p12` containing the Mac Installer Distribution certificate and private key |
| `AIRFLIQ_MAC_INSTALLER_DISTRIBUTION_P12_PASSWORD` | Password used when exporting that installer `.p12` |
| `AIRFLIQ_APP_STORE_APP_PROFILE_BASE64` | Base64 of the Mac App Store distribution profile for `com.cosmintrica.airfliq` |
| `AIRFLIQ_APP_STORE_EXTENSION_PROFILE_BASE64` | Base64 of the Mac App Store distribution profile for `com.cosmintrica.airfliq.finder` |
| `AIRFLIQ_REVENUECAT_PUBLIC_SDK_KEY` | RevenueCat public Apple SDK key beginning with `appl_` or `mac_` |

Encode each binary file on macOS without changing it:

```bash
base64 -i AirFliq-Apple-Distribution.p12 | pbcopy
base64 -i AirFliq-Mac-Installer-Distribution.p12 | pbcopy
base64 -i AirFliq.provisionprofile | pbcopy
base64 -i AirFliqFinder.provisionprofile | pbcopy
```

The two provisioning profiles must be App Store distribution profiles, must
belong to the same Apple Developer team, must not be expired and must use the
exact bundle IDs above. Do not use development, Developer ID or direct
distribution profiles.

To build, open `Actions > Build signed Mac App Store package > Run workflow`.
Enter the marketing version from the App Store record, such as `1.0.0`, and a
new build number containing one to three integers. Every build uploaded to the
same App Store version must have a greater build number than the previous
upload. The selected Xcode is explicitly checked to be stable Xcode 26.6, not
a beta.

Download the `AirFliq-AppStore-<version>-<build>` artifact and verify its
checksum before using Transporter:

```bash
shasum -a 256 -c AirFliq-AppStore.pkg.sha256
```

The package validator checks all of the following before the artifact exists:

- Both `AirFliq` and `AirFliqFinder` contain ARM64 and x86_64 slices.
- The app, Finder extension and RevenueCat framework have valid nested
  signatures.
- App Sandbox, folder bookmarks, read-only user-selected items and network client
  entitlements are present. Apple Events, scripting targets, temporary exceptions
  and the Automation usage description are absent.
- `get-task-allow` is not enabled.
- The app and extension bundle IDs, versions and build numbers match.
- Both embedded profiles are current App Store profiles for the same team.
- The signed installer contains the expected AirFliq executable.

The App Store build uses NSOpenPanel for the global shortcut/menu action and
Finder Sync for the right-click action. Keep the App Review explanation
synchronized with `marketing/app-store/metadata-en-US.md`.
Passing the local validator does not replace App Store Connect processing or
App Review.

## Local release validation

The signed build script accepts injectable version values without editing the
source plists:

```bash
MARKETING_VERSION=1.0.0 \
BUILD_NUMBER=2 \
REVENUECAT_API_KEY="appl_public_key" \
SIGN_IDENTITY="Apple Distribution: Name (TEAMID)" \
INSTALLER_IDENTITY="Mac Installer Distribution: Name (TEAMID)" \
APP_PROFILE="/absolute/path/AirFliq.provisionprofile" \
EXT_PROFILE="/absolute/path/AirFliqFinder.provisionprofile" \
./build-app-store.sh
```

You can rerun the complete offline checks against an existing signed package:

```bash
MARKETING_VERSION=1.0.0 BUILD_NUMBER=2 \
  ./scripts/verify-app-store-build.sh
```

## Shipaton release evidence

- Store URL for the first public AirFliq release during the competition window.
- Public demo video no longer than two minutes.
- High-resolution screenshots showing onboarding, shortcut, context menu and
  drag target.
- Build-in-public posts using `#Shipaton`.
- A working RevenueCat purchase or restore flow in the submitted build.
- Offer codes or a reviewer unlock path so judges can evaluate Pro. One-time
  Lifetime Pro offer codes exist (see `build/judge-access/README.md`, not in
  Git); the paywall's Redeem Code button opens StoreKit's redemption sheet on
  macOS 15 and later.

## Tax and invoicing note

For App Store sales, Apple is the merchant handling the end-user transaction and
consumer tax collection. Apple pays developer proceeds and provides financial
reports. Romanian company or individual income reporting still needs advice
from an accountant based on the developer account owner and legal form.
