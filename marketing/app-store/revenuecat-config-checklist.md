# AirFliq RevenueCat and App Store Connect configuration

Complete this checklist before uploading the first production build.

## App Store Connect

- [ ] App bundle ID is `com.cosmintrica.airfliq`.
- [ ] Create a Non-Consumable IAP named exactly `7-day Trial`.
- [ ] Trial product ID is `com.cosmintrica.airfliq.trial7day`.
- [ ] Trial price is Price Tier 0.
- [ ] Trial is cleared for sale in every AirFliq storefront.
- [ ] Lifetime Pro is a separate paid Non-Consumable with product ID
  `com.cosmintrica.airfliq.lifetime`.
- [ ] Lifetime Pro is cleared for sale in every AirFliq storefront.
- [ ] Both IAPs have review screenshots and descriptions.

## RevenueCat

- [ ] Import both App Store products into the AirFliq project.
- [ ] Attach only `com.cosmintrica.airfliq.lifetime` to entitlement `Pro`.
- [ ] Do not attach `com.cosmintrica.airfliq.trial7day` to any entitlement.
- [ ] Keep Lifetime Pro in the current `airfliq` offering.
- [ ] The app fetches `com.cosmintrica.airfliq.trial7day` directly with
  `Purchases.getProducts`, so the trial does not need an offering package.
- [ ] Production Apple public SDK key is injected by the release build secret.
- [ ] App Store Connect In-App Purchase key is active in RevenueCat.

## Sandbox acceptance test

- [ ] A fresh sandbox account has no access before pressing Start free 7-day
  trial.
- [ ] Cancelling the App Store sheet leaves the trial unstarted.
- [ ] Confirming the free IAP creates a RevenueCat non-subscription transaction.
- [ ] The trial UI refuses any StoreKit product that is not both zero-priced and
  Non-Consumable.
- [ ] Only an App Store or Mac App Store transaction purchase date starts exactly
  seven elapsed days of access.
- [ ] RevenueCat `CustomerInfo.requestDate`, not the local Mac clock, determines
  whether the seven days have expired.
- [ ] Relaunch and Restore Purchase recover the original purchase date.
- [ ] After expiry, every send entry point opens the Lifetime Pro paywall.
- [ ] The Lifetime button shows the sandbox storefront's localized price.
- [ ] Purchasing Lifetime Pro activates entitlement `Pro` and restores on a
  second install using the same sandbox Apple Account.
