# AirFliq

[Website](https://airfliq.vercel.app) | [Privacy](https://airfliq.vercel.app/privacy) | [Support](https://airfliq.vercel.app/support) | [GitHub](https://github.com/cosmintrica/AirFliq)

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

Reset the three macOS onboarding permissions and the development-only local
trial fallback with:

```bash
./reset-permissions.sh
```

## Monetization

The Mac App Store build lets the user explicitly start a free 7-day full-access
trial. It never renews and never charges automatically. A non-consumable
Lifetime Pro purchase keeps the complete app unlocked at the storefront's
localized one-time price through RevenueCat. There is no send counter. The Mac
App Store release is in progress; production purchase verification remains part
of the release checklist. See `docs/APP-STORE.md` for the App Store Connect and
RevenueCat checklist.

## Website

The landing page is in `website/` and includes product, privacy and support
pages. The production site is <https://airfliq.vercel.app>.

## Verification

GitHub Actions rebuilds the universal Mac app and validates the landing page on
every push and pull request. The App Store screenshots in
`marketing/app-store/final/` are rendered at 2880 by 1800 pixels from the
matching AirFliq source artwork.

AirDrop is a trademark of Apple Inc. AirFliq is an independent product and is
not affiliated with Apple.
