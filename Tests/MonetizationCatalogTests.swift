import Foundation
import RevenueCat

/// Exercises the production catalog with controlled SDK callbacks and time.
/// No SDK configuration, network requests, billing or entitlement changes occur.
@main struct MonetizationCatalogTests {
    @MainActor final class Requests {
        var products: [@MainActor ([StoreProduct]) -> Void] = []
        var offerings: [@MainActor (Package?) -> Void] = []
        var scheduled: [(TimeInterval, @MainActor () -> Void)] = []
        var client: Monetization.CatalogRequests {
            .init(products: { self.products.append($0) },
                  offering: { self.offerings.append($0) },
                  schedule: { self.scheduled.append(($0, $1)) })
        }
        func fire(_ delay: TimeInterval) {
            guard let index = scheduled.firstIndex(where: { $0.0 == delay }) else {
                preconditionFailure("Expected scheduled callback after \(delay)s")
            }
            scheduled.remove(at: index).1()
        }
    }

    @MainActor static func product(_ id: String, price: Decimal,
                                  type: StoreProduct.ProductType = .nonConsumable,
                                  localized: String = "4,99 €") -> StoreProduct {
        TestStoreProduct(localizedTitle: "Catalog fixture", price: price,
                         currencyCode: "EUR", localizedPriceString: localized,
                         productIdentifier: id, productType: type,
                         localizedDescription: "Catalog fixture", locale: Locale(identifier: "ro_RO"))
            .toStoreProduct()
    }
    @MainActor static var lifetime: StoreProduct {
        product(Monetization.lifetimeProductID, price: Decimal(string: "4.99")!)
    }
    @MainActor static var trial: StoreProduct {
        product(Monetization.trialProductID, price: .zero, localized: "Gratis")
    }
    @MainActor static var package: Package {
        Package(identifier: "$rc_lifetime", packageType: .lifetime, storeProduct: lifetime,
                presentedOfferingContext: PresentedOfferingContext(offeringIdentifier: "airfliq"),
                webCheckoutUrl: nil)
    }
    @MainActor static func assertReady(_ model: Monetization) {
        precondition(model.storeState == .ready && model.trialStoreState == .ready)
        precondition(model.lifetimeProduct != nil && model.trialProduct != nil)
        precondition(model.localizedLifetimePrice == "4,99 €")
        precondition(!model.isConfigured && !model.isPro && !model.isTrialStarted && !model.hasUnlimitedSending,
                     "Loading products must never authorize a transfer or invent a trial")
    }
    @MainActor static func main() {
        do {
            // Five completed sends per local day, then a refill at midnight.
            let suite = "com.cosmintrica.airfliq.free-allowance-tests"
            let defaults = UserDefaults(suiteName: suite)!
            defaults.removePersistentDomain(forName: suite)
            defer { defaults.removePersistentDomain(forName: suite) }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "Europe/Bucharest")!
            let allowance = FreeSendAllowance(defaults: defaults, calendar: calendar)
            let morning = ISO8601DateFormatter().date(from: "2026-10-01T06:00:00Z")!
            let lateNight = ISO8601DateFormatter().date(from: "2026-10-01T20:59:00Z")!
            let nextDay = ISO8601DateFormatter().date(from: "2026-10-01T21:01:00Z")!
            precondition(allowance.used(on: morning) == 0)
            for expected in 1...7 {
                precondition(allowance.recordSend(on: morning) == min(expected, 5))
            }
            precondition(allowance.used(on: lateNight) == 5, "Still the same local day")
            precondition(allowance.used(on: nextDay) == 0, "Refills after local midnight")
            precondition(allowance.recordSend(on: nextDay) == 1)

            let access = Monetization(catalogRequests: Requests().client,
                                      freeAllowance: FreeSendAllowance(defaults: defaults,
                                                                       calendar: calendar))
            defaults.removePersistentDomain(forName: suite)
            access.refreshFreeAllowance()
            precondition(access.canSend && !access.hasUnlimitedSending
                         && access.freeSendsRemainingToday == 5)
            for _ in 0..<5 { access.recordSuccessfulSend() }
            precondition(!access.canSend && access.freeSendsRemainingToday == 0,
                         "The sixth send today needs the trial or Pro")
            print("PASS: five free sends per local day, counted only on completion")
        }

        for offeringFirst in [false, true] {
            let requests = Requests()
            let access = Monetization(catalogRequests: requests.client)
            access.refreshCatalog()
            access.refreshCatalog()
            precondition(requests.products.count == 1 && requests.offerings.count == 1,
                         "Repeated refreshes must coalesce")
            if offeringFirst { requests.offerings[0](nil) }
            requests.products[0]([trial, lifetime])
            assertReady(access)
            if !offeringFirst { requests.offerings[0](nil) }
            assertReady(access)
            precondition(access.package == nil, "Direct products must work with no current offering")
            requests.fire(20)
            assertReady(access)
        }
        print("PASS: valid direct products work in both callback orders, despite missing offering")

        do {
            let requests = Requests(), access: Monetization
            access = Monetization(catalogRequests: requests.client)
            access.refreshCatalog()
            requests.products[0]([trial])
            precondition(access.trialProduct == nil, "Do not start trial before localized Lifetime disclosure")
            requests.offerings[0](package)
            assertReady(access)
        }
        print("PASS: valid offering product recovers incomplete direct product response")

        do {
            let requests = Requests(), access: Monetization
            access = Monetization(catalogRequests: requests.client)
            access.refreshCatalog()
            requests.products[0]([])
            requests.offerings[0](nil)
            precondition(access.trialProduct == nil && access.lifetimeProduct == nil && !access.hasUnlimitedSending)
            requests.fire(1)
            precondition(requests.products.count == 2)
            requests.products[1]([trial, lifetime])
            requests.offerings[1](nil)
            assertReady(access)
            requests.products[0]([])
            requests.offerings[0](nil)
            assertReady(access)
        }
        print("PASS: both products initially empty retry and recover; obsolete callbacks cannot erase readiness")

        do {
            let requests = Requests(), access: Monetization
            access = Monetization(catalogRequests: requests.client)
            access.refreshCatalog()
            requests.fire(20)
            requests.fire(1)
            requests.products[0]([trial, lifetime])
            precondition(access.lifetimeProduct == nil, "Timed-out callback belongs to old generation")
            requests.products[1]([trial, lifetime])
            requests.offerings[1](nil)
            assertReady(access)
        }
        print("PASS: missing callbacks time out and retry without accepting obsolete results")

        do {
            let requests = Requests(), access: Monetization
            access = Monetization(catalogRequests: requests.client)
            access.refreshCatalog()
            for attempt in 0..<4 {
                requests.products[attempt]([])
                requests.offerings[attempt](nil)
                if attempt < 3 { requests.fire([1.0, 3.0, 8.0][attempt]) }
            }
            precondition(requests.products.count == 4)
            precondition(!requests.scheduled.contains(where: { $0.0 < 20 }), "Retries must be bounded")
            precondition(access.localizedLifetimePrice == nil && access.trialProduct == nil && !access.hasUnlimitedSending)
            access.refreshCatalog()
            precondition(requests.products.count == 5, "Reopening the paywall allows a fresh retry budget")
            requests.products[4]([trial, lifetime])
            requests.offerings[4](nil)
            assertReady(access)
        }
        print("PASS: persistent failures stop after bounded retries and explicit retry recovers")

        for badTrial in [product(Monetization.trialProductID, price: 1),
                         product(Monetization.trialProductID, price: 0, type: .consumable),
                         product("unrelated.trial", price: 0)] {
            let requests = Requests(), access: Monetization
            access = Monetization(catalogRequests: requests.client)
            access.refreshCatalog()
            requests.products[0]([badTrial, lifetime])
            requests.offerings[0](nil)
            precondition(access.trialProduct == nil && access.lifetimeProduct != nil && !access.hasUnlimitedSending)
        }
        print("PASS: paid, consumable and wrong-identifier trial products are rejected")

        for badLifetime in [product(Monetization.lifetimeProductID, price: 0),
                            product(Monetization.lifetimeProductID, price: 5, type: .consumable),
                            product("unrelated.lifetime", price: 5),
                            product(Monetization.lifetimeProductID, price: 5, localized: " ")] {
            let requests = Requests(), access: Monetization
            access = Monetization(catalogRequests: requests.client)
            access.refreshCatalog()
            requests.products[0]([trial, badLifetime])
            let invalid = Package(identifier: "$rc_lifetime", packageType: .lifetime,
                                  storeProduct: badLifetime,
                                  presentedOfferingContext: PresentedOfferingContext(offeringIdentifier: "airfliq"),
                                  webCheckoutUrl: nil)
            requests.offerings[0](invalid)
            precondition(access.lifetimeProduct == nil && access.trialProduct == nil && !access.hasUnlimitedSending)
        }
        print("PASS: free, consumable, wrong-identifier and unpriced Lifetime products cannot unlock either action")
    }
}
