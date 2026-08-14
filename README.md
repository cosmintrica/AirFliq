# AirFliq

AirFliq is a native macOS utility that prepares Finder selections for Apple's
AirDrop panel from a shortcut, menu bar icon, Finder context menu, or animated
drag target.

## Build locally

```bash
./scripts/fetch-revenuecat.sh
./build.sh
```

The build is a universal ARM64 and x86_64 app at `build/AirFliq.app`. Local
ad-hoc signing is enough for interface testing, but macOS privacy grants may
reset when the binary changes. Use a stable Apple Development signature for
repeatable permission testing.

Reset all three onboarding permissions and start a fresh local trial with:

```bash
./reset-permissions.sh
```

## Monetization

Every feature is available during a 7-day full-access trial. A non-consumable
Lifetime Pro purchase keeps the complete app unlocked for $4.99 through
RevenueCat. There is no send counter. See
`docs/APP-STORE.md` for the App Store Connect and RevenueCat checklist.

## Website

The landing page is in `website/` and includes product, privacy and support
pages. The production site is <https://airfliq.vercel.app>.

## Verification

GitHub Actions rebuilds the universal Mac app and validates the landing page on
every push and pull request. The App Store screenshots in
`marketing/app-store/output/` are rendered at 2880 by 1800 pixels from the
matching AirFliq source artwork.

AirDrop is a trademark of Apple Inc. AirFliq is an independent product and is
not affiliated with Apple.
