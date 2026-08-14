import AppKit
import Combine
import RevenueCat

extension Notification.Name {
    static let airFliqAccessChanged = Notification.Name("airfliq.access.changed")
    static let airFliqSendSucceeded = Notification.Name("airfliq.send.succeeded")
}

@MainActor
final class Monetization: NSObject, @preconcurrency PurchasesDelegate, ObservableObject {
    static let shared = Monetization()
    static let trialDuration: TimeInterval = 7 * 24 * 60 * 60
    static let entitlementID = "Pro"
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

    private let trialStartedAt: Date
    @Published private(set) var isPro = false
    @Published private(set) var package: Package?
    @Published private(set) var isConfigured = false
    @Published private(set) var storeState: StoreState = .notConfigured
    @Published private(set) var trialReferenceDate: Date

    private override init() {
        let trial = TrialPersistence.currentState()
        trialStartedAt = trial.startedAt
        trialReferenceDate = trial.referenceDate
        super.init()
    }

    var trialEndDate: Date { trialStartedAt.addingTimeInterval(Self.trialDuration) }
    var trialRemainingTime: TimeInterval {
        max(0, trialEndDate.timeIntervalSince(trialReferenceDate))
    }
    var trialDaysRemaining: Int {
        guard trialRemainingTime > 0 else { return 0 }
        return max(1, Int(ceil(trialRemainingTime / (24 * 60 * 60))))
    }
    var trialProgress: Double {
        min(1, max(0, trialReferenceDate.timeIntervalSince(trialStartedAt)
                   / Self.trialDuration))
    }
    var isTrialExpired: Bool { trialRemainingTime <= 0 }
    var trialStatusText: String {
        if isTrialExpired { return "Trial ended" }
        if trialRemainingTime < 24 * 60 * 60 {
            let hours = max(1, Int(ceil(trialRemainingTime / (60 * 60))))
            return hours == 1 ? "1 hour left in your trial"
                              : "\(hours) hours left in your trial"
        }
        return trialDaysRemaining == 1 ? "1 day left in your trial"
                                       : "\(trialDaysRemaining) days left in your trial"
    }
    var canSend: Bool { isPro || !isTrialExpired }
    var price: String { package?.localizedPriceString ?? "$4.99" }

    func configure() {
        refreshTrialClock()
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
        refreshTrialClock()
        guard isConfigured else { return }
        refreshCustomerInfo(fetchPolicy: .fetchCurrent)
        if package == nil { refreshOfferings() }
    }

    func resolveSendAccess(completion: @escaping (Bool) -> Void) {
        refreshTrialClock()
        guard !isPro, isTrialExpired, isConfigured else {
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

    private func refreshTrialClock() {
        trialReferenceDate = TrialPersistence.currentState().referenceDate
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
