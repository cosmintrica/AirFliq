import AppKit
import Combine
import RevenueCat

extension Notification.Name {
    static let airFliqAccessChanged = Notification.Name("airfliq.access.changed")
    static let airFliqSendSucceeded = Notification.Name("airfliq.send.succeeded")
}

@MainActor
final class Monetization: NSObject, PurchasesDelegate, ObservableObject {
    static let shared = Monetization()
    static let freeSendLimit = 50
    static let entitlementID = "pro"
    static let lifetimeProductID = "com.cosmintrica.airfliq.lifetime"

    enum StoreState: Equatable {
        case notConfigured
        case loading
        case ready
        case failed(String)
    }

    enum PurchaseOutcome: Equatable {
        case purchased
        case cancelled
        case restored
        case nothingToRestore
        case failed(String)
    }

    private let sendCountKey = "airfliq.successfulSends.v1"
    @Published private(set) var isPro = false
    @Published private(set) var package: Package?
    @Published private(set) var isConfigured = false
    @Published private(set) var storeState: StoreState = .notConfigured
    @Published private(set) var sendCount = UserDefaults.standard.integer(
        forKey: "airfliq.successfulSends.v1"
    )

    var sendsRemaining: Int { max(0, Self.freeSendLimit - sendCount) }
    var canSend: Bool { isPro || sendsRemaining > 0 }
    var price: String { package?.localizedPriceString ?? "$4.99" }

    func configure() {
        guard !isConfigured else {
            refresh()
            return
        }
        guard let key = Bundle.main.object(forInfoDictionaryKey: "AirFliqRevenueCatAPIKey") as? String,
              !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            storeState = .notConfigured
            notifyChanged()
            return
        }

        isConfigured = true
        storeState = .loading
        let purchases = Purchases.configure(withAPIKey: key)
        purchases.delegate = self
        notifyChanged()
        refreshCustomerInfo()
        refreshOfferings()
    }

    func refresh() {
        guard isConfigured else { return }
        refreshCustomerInfo(fetchPolicy: .fetchCurrent)
        if package == nil { refreshOfferings() }
    }

    func resolveSendAccess(completion: @escaping (Bool) -> Void) {
        guard !isPro, sendsRemaining == 0, isConfigured else {
            completion(canSend)
            return
        }

        Purchases.shared.getCustomerInfo(fetchPolicy: .fetchCurrent) { [weak self] info, _ in
            guard let self else {
                completion(false)
                return
            }
            apply(info)
            completion(canSend)
        }
    }

    func recordSuccessfulSend() {
        guard !isPro else { return }
        sendCount = min(Self.freeSendLimit, sendCount + 1)
        UserDefaults.standard.set(sendCount, forKey: sendCountKey)
        NotificationCenter.default.post(name: .airFliqAccessChanged, object: nil)
    }

    func purchase(completion: @escaping (PurchaseOutcome) -> Void) {
        guard isConfigured else {
            completion(.failed("Purchases are available in the Mac App Store build."))
            return
        }
        guard let package else {
            refreshOfferings()
            completion(.failed("The Lifetime product is still loading. Please try again."))
            return
        }

        Purchases.shared.purchase(package: package) { [weak self] _, info, error, cancelled in
            self?.apply(info)
            if self?.isPro == true {
                completion(.purchased)
            } else if cancelled {
                completion(.cancelled)
            } else if let error {
                completion(.failed(error.localizedDescription))
            } else {
                completion(.failed("The purchase finished without unlocking AirFliq Pro. Try Restore Purchase."))
            }
        }
    }

    func restore(completion: @escaping (PurchaseOutcome) -> Void) {
        guard isConfigured else {
            completion(.failed("Purchases are available in the Mac App Store build."))
            return
        }

        Purchases.shared.restorePurchases { [weak self] info, error in
            self?.apply(info)
            if let error {
                completion(.failed(error.localizedDescription))
            } else if self?.isPro == true {
                completion(.restored)
            } else {
                completion(.nothingToRestore)
            }
        }
    }

    func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        apply(customerInfo)
    }

    private func apply(_ info: CustomerInfo?) {
        guard let info else { return }
        isPro = info.entitlements.active[Self.entitlementID] != nil
        notifyChanged()
    }

    private func refreshCustomerInfo(fetchPolicy: CacheFetchPolicy = .cachedOrFetched) {
        Purchases.shared.getCustomerInfo(fetchPolicy: fetchPolicy) { [weak self] info, _ in
            self?.apply(info)
        }
    }

    private func refreshOfferings() {
        guard isConfigured else { return }
        storeState = .loading
        notifyChanged()

        Purchases.shared.getOfferings { [weak self] offerings, error in
            guard let self else { return }

            if let error {
                package = nil
                storeState = .failed(error.localizedDescription)
                notifyChanged()
                return
            }

            guard let offering = offerings?.current else {
                package = nil
                storeState = .failed("No current RevenueCat offering is configured.")
                notifyChanged()
                return
            }

            package = offering.availablePackages.first {
                $0.storeProduct.productIdentifier == Self.lifetimeProductID
            } ?? offering.lifetime

            if package != nil {
                storeState = .ready
            } else {
                storeState = .failed("The current offering has no Lifetime package.")
            }
            notifyChanged()
        }
    }

    private func notifyChanged() {
        NotificationCenter.default.post(name: .airFliqAccessChanged, object: nil)
    }
}
