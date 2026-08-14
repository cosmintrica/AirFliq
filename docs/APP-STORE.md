# AirFliq App Store and RevenueCat checklist

## Product model

- Free download on the Mac App Store.
- 50 successful AirDrop sharing sessions are free.
- Cancels, validation errors and failed transfers do not consume a send.
- `AirFliq Pro` is a non-consumable Lifetime unlock at $4.99.
- RevenueCat entitlement: `pro`.
- Suggested product identifier: `com.cosmintrica.airfliq.lifetime`.
- Suggested offering: `default`, with the Lifetime product attached.

Apple processes payment, VAT or sales tax, refunds and customer receipts for
Mac App Store purchases. RevenueCat synchronizes entitlement state and purchase
restoration. AirFliq should not add Stripe checkout for digital functionality in
the App Store build.

## Records to create

1. App Store Connect app with bundle ID `com.cosmintrica.airfliq`.
2. Finder extension ID `com.cosmintrica.airfliq.finder`.
3. A non-consumable in-app purchase using the product ID above.
4. A RevenueCat project linked to the App Store Connect app.
5. RevenueCat entitlement `pro`, offering `default`, and Lifetime package.
6. App Store Connect In-App Purchase key uploaded to RevenueCat.

The public RevenueCat macOS SDK key is injected at build time. Never commit it
or any App Store Connect private key to Git:

```bash
REVENUECAT_API_KEY="appl_public_key" \
SIGN_IDENTITY="Apple Distribution: Name (TEAMID)" \
INSTALLER_IDENTITY="3rd Party Mac Developer Installer: Name (TEAMID)" \
APP_PROFILE="/absolute/path/AirFliq.provisionprofile" \
EXT_PROFILE="/absolute/path/AirFliqFinder.provisionprofile" \
./build-app-store.sh
```

The script verifies the sandbox, privacy manifest, nested framework signature,
and universal ARM64 plus x86_64 binaries. It outputs
`build/AirFliq-AppStore.pkg`.

## Shipaton release evidence

- Store URL for the first public AirFliq release during the competition window.
- Public demo video no longer than two minutes.
- High-resolution screenshots showing onboarding, shortcut, context menu and
  drag target.
- Build-in-public posts using `#Shipaton`.
- A working RevenueCat purchase or restore flow in the submitted build.
- Offer codes or a reviewer unlock path so judges can evaluate Pro.

## Tax and invoicing note

For App Store sales, Apple is the merchant handling the end-user transaction and
consumer tax collection. Apple pays developer proceeds and provides financial
reports. Romanian company or individual income reporting still needs advice
from an accountant based on the developer account owner and legal form.
