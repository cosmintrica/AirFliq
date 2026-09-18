import AppKit
import Combine
import RevenueCat

#if AIRFLIQ_LOCAL_QA && !DEBUG
#error("AIRFLIQ_LOCAL_QA is forbidden in Release builds")
#endif

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
    static let trialProductID = "com.cosmintrica.airfliq.trial7day"

#if AIRFLIQ_LOCAL_QA && DEBUG
    static let isLocalTransferTest = true
#else
    static let isLocalTransferTest = false
#endif
    static var localTransferTestMessage: String {
#if AIRFLIQ_LOCAL_QA && DEBUG
        "Local transfer test (purchases disabled)"
#else
        ""
#endif
    }

    enum StoreState: Equatable {
        case notConfigured
        case loading
        case ready
        case failed(String)
    }

    enum PurchaseOutcome: Equatable {
        case purchased
        case trialStarted
        case cancelled
        case restored
        case trialRestored
        case trialExpired
        case nothingToRestore
        case failed(String)
    }

    @Published private(set) var isPro = false
    @Published private(set) var package: Package?
    @Published private(set) var trialProduct: StoreProduct?
    @Published private(set) var isConfigured = false
    @Published private(set) var storeState: StoreState = .notConfigured
    @Published private(set) var trialStoreState: StoreState = .notConfigured
    @Published private(set) var trialStartedAt: Date?
    @Published private(set) var trialReferenceDate: Date
    private var usesVerifiedTrialClock = false
    private var validatedTrialProduct: StoreProduct?

    private override init() {
#if MAC_APP_STORE
        trialStartedAt = nil
        trialReferenceDate = Date()
#else
        let trial = TrialPersistence.currentDevelopmentState()
        trialStartedAt = trial.startedAt
        trialReferenceDate = trial.referenceDate
#endif
        super.init()
    }

    var isTrialStarted: Bool { trialStartedAt != nil }
    var trialEndDate: Date? {
        trialStartedAt?.addingTimeInterval(Self.trialDuration)
    }
    var trialRemainingTime: TimeInterval {
        guard let trialEndDate else { return 0 }
        return max(0, trialEndDate.timeIntervalSince(trialReferenceDate))
    }
    var trialDaysRemaining: Int {
        guard trialRemainingTime > 0 else { return 0 }
        return max(1, Int(ceil(trialRemainingTime / (24 * 60 * 60))))
    }
    var trialProgress: Double {
        guard let trialStartedAt else { return 0 }
        return min(1, max(0, trialReferenceDate.timeIntervalSince(trialStartedAt)
                   / Self.trialDuration))
    }
    var isTrialExpired: Bool {
        isTrialStarted && trialRemainingTime <= 0
    }
    var isTrialActive: Bool {
        isTrialStarted && !isTrialExpired
    }
    var trialStatusText: String {
        if Self.isLocalTransferTest { return Self.localTransferTestMessage }
        guard isTrialStarted else { return "7-day trial ready to start" }
        if isTrialExpired { return "Trial ended" }
        if trialRemainingTime < 24 * 60 * 60 {
            let hours = max(1, Int(ceil(trialRemainingTime / (60 * 60))))
            return hours == 1 ? "1 hour left in your trial"
                              : "\(hours) hours left in your trial"
        }
        return trialDaysRemaining == 1 ? "1 day left in your trial"
                                       : "\(trialDaysRemaining) days left in your trial"
    }
    var canSend: Bool { Self.isLocalTransferTest || isPro || isTrialActive }

    var setupSummary: String {
        if Self.isLocalTransferTest { return Self.localTransferTestMessage }
        return package == nil
            ? "7-day trial available  •  Lifetime Pro"
            : "7-day trial available  •  Lifetime Pro \(price)"
    }

    /// Never invent a storefront price. RevenueCat supplies the localized
    /// amount once StoreKit has loaded the product for the current account.
    var price: String { package?.localizedPriceString ?? "one purchase" }
    var localizedLifetimePrice: String? { package?.localizedPriceString }

    func configure() {
        if Self.isLocalTransferTest {
            storeState = .failed(Self.localTransferTestMessage)
            trialStoreState = .failed(Self.localTransferTestMessage)
            notifyChanged()
            return
        }
        refreshTrialClock()
        guard !isConfigured else {
            refresh()
            return
        }
        guard let key = Bundle.main.object(forInfoDictionaryKey: "AirFliqRevenueCatAPIKey") as? String,
              !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            storeState = .notConfigured
            trialStoreState = .notConfigured
            notifyChanged()
            return
        }

        isConfigured = true
        storeState = .loading
        trialStoreState = .loading
        let purchases = Purchases.configure(withAPIKey: key)
        purchases.delegate = self
        apply(purchases.cachedCustomerInfo)
        notifyChanged()
        refreshCustomerInfo()
        refreshOfferings()
        refreshTrialProduct()
    }

    func refresh() {
        refreshTrialClock()
        guard isConfigured else { return }
        refreshCustomerInfo(fetchPolicy: .fetchCurrent)
        if package == nil { refreshOfferings() }
        if validatedTrialProduct == nil { refreshTrialProduct() }
    }

    func resolveSendAccess(completion: @escaping (Bool) -> Void) {
        refreshTrialClock()
        guard !canSend, isConfigured else {
            completion(canSend)
            return
        }

        // A send action must never wait on the network. RevenueCat's persisted
        // CustomerInfo is the synchronous authority, while a network refresh
        // prepares the next action without delaying the native AirDrop panel.
        apply(Purchases.shared.cachedCustomerInfo)
        completion(canSend)
        refreshCustomerInfo(fetchPolicy: .fetchCurrent)
    }

    func startTrial(completion: @escaping (PurchaseOutcome) -> Void) {
        guard !Self.isLocalTransferTest else {
            completion(.failed(Self.localTransferTestMessage)); return
        }
        guard !isPro, !isTrialStarted else {
            completion(isTrialActive ? .trialStarted : .trialExpired)
            return
        }
        guard isConfigured else {
            completion(.failed("The free trial is available in the Mac App Store build."))
            return
        }
        guard let trialProduct else {
            refreshTrialProduct()
            completion(.failed("The free 7-day Trial and localized Lifetime price are still loading. Please try again."))
            return
        }
        if let configurationError = Self.trialConfigurationError(for: trialProduct) {
            validatedTrialProduct = nil
            self.trialProduct = nil
            trialStoreState = .failed(configurationError)
            notifyChanged()
            completion(.failed(configurationError))
            return
        }

        Purchases.shared.purchase(product: trialProduct) { [weak self] _, info, error, cancelled in
            guard let self else { return }
            apply(info)
            if isTrialActive {
                completion(.trialStarted)
            } else if cancelled {
                completion(.cancelled)
            } else if let error {
                completion(.failed(error.localizedDescription))
            } else {
                completion(.failed("The App Store did not confirm the 7-day Trial. Please try again."))
            }
        }
    }

    func purchase(completion: @escaping (PurchaseOutcome) -> Void) {
        guard !Self.isLocalTransferTest else {
            completion(.failed(Self.localTransferTestMessage)); return
        }
        guard isConfigured else {
            completion(.failed("Purchases are available in the Mac App Store build."))
            return
        }
        guard let package else {
            refreshOfferings()
            completion(.failed("The Lifetime product is still loading. Please try again."))
            return
        }
        if let configurationError = Self.lifetimeConfigurationError(for: package) {
            self.package = nil
            storeState = .failed(configurationError)
            updateTrialReadiness()
            notifyChanged()
            completion(.failed(configurationError))
            return
        }

        Purchases.shared.purchase(package: package) { [weak self] _, info, error, cancelled in
            guard let self else { return }
            apply(info)
            if isPro {
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
        guard !Self.isLocalTransferTest else {
            completion(.failed(Self.localTransferTestMessage)); return
        }
        guard isConfigured else {
            completion(.failed("Purchases are available in the Mac App Store build."))
            return
        }

        Purchases.shared.restorePurchases { [weak self] info, error in
            guard let self else { return }
            apply(info)
            if let error {
                completion(.failed(error.localizedDescription))
            } else if isPro {
                completion(.restored)
            } else if isTrialActive {
                completion(.trialRestored)
            } else if isTrialExpired {
                completion(.trialExpired)
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

        // Guideline 3.1.1 requires a Price Tier 0 non-consumable trial. The
        // receipt-backed RevenueCat transaction, not a local preference, is the
        // App Store build's source of truth for when that trial began.
        // `nonSubscriptions` is the current RevenueCat SDK name for
        // CustomerInfo.nonSubscriptionTransactions.
        let verifiedTrialStart = info.nonSubscriptions
            .filter(Self.isVerifiedAppleTrialTransaction)
            .map(\.purchaseDate)
            .min()

#if MAC_APP_STORE
        let trial = TrialPersistence.verifiedState(
            startedAt: verifiedTrialStart,
            trustedReferenceDate: info.requestDate
        )
#else
        let trial: TrialPersistence.State
        if let verifiedTrialStart {
            usesVerifiedTrialClock = true
            trial = TrialPersistence.verifiedState(
                startedAt: verifiedTrialStart,
                trustedReferenceDate: info.requestDate
            )
        } else {
            usesVerifiedTrialClock = false
            trial = TrialPersistence.currentDevelopmentState()
        }
#endif
        trialStartedAt = trial.startedAt
        trialReferenceDate = trial.referenceDate
        notifyChanged()
    }

    private func refreshTrialClock() {
#if MAC_APP_STORE
        let trial = TrialPersistence.verifiedState(startedAt: trialStartedAt)
#else
        let trial = usesVerifiedTrialClock
            ? TrialPersistence.verifiedState(startedAt: trialStartedAt)
            : TrialPersistence.currentDevelopmentState()
#endif
        trialStartedAt = trial.startedAt
        trialReferenceDate = trial.referenceDate
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
                updateTrialReadiness()
                notifyChanged()
                return
            }

            guard let offering = offerings?.current else {
                package = nil
                storeState = .failed("No current RevenueCat offering is configured.")
                updateTrialReadiness()
                notifyChanged()
                return
            }

            package = offering.availablePackages.first {
                $0.storeProduct.productIdentifier == Self.lifetimeProductID
            }

            if let package,
               let configurationError = Self.lifetimeConfigurationError(for: package) {
                self.package = nil
                storeState = .failed(configurationError)
            } else if package != nil {
                storeState = .ready
            } else {
                storeState = .failed("The current offering has no Lifetime package.")
            }
            updateTrialReadiness()
            notifyChanged()
        }
    }

    private func refreshTrialProduct() {
        guard isConfigured else { return }
        trialStoreState = .loading
        notifyChanged()

        Purchases.shared.getProducts([Self.trialProductID]) { [weak self] products in
            guard let self else { return }
            guard let product = products.first(where: {
                $0.productIdentifier == Self.trialProductID
            }) else {
                validatedTrialProduct = nil
                trialProduct = nil
                trialStoreState = .failed("The free 7-day Trial product is unavailable in this storefront.")
                notifyChanged()
                return
            }

            if let configurationError = Self.trialConfigurationError(for: product) {
                validatedTrialProduct = nil
                trialProduct = nil
                trialStoreState = .failed(configurationError)
            } else {
                validatedTrialProduct = product
                updateTrialReadiness()
            }
            notifyChanged()
        }
    }

    /// Apple requires the downstream full-unlock charge to be disclosed before
    /// a time-based trial starts. Publishing trialProduct only after the exact
    /// Lifetime package and its localized price are ready keeps the Paywall's
    /// existing enablement rule compliant regardless of callback order.
    private func updateTrialReadiness() {
        guard let validatedTrialProduct else {
            trialProduct = nil
            return
        }
        guard localizedLifetimePrice != nil else {
            trialProduct = nil
            switch storeState {
            case .failed(let message):
                trialStoreState = .failed("The Lifetime price is unavailable. \(message)")
            case .notConfigured, .loading, .ready:
                trialStoreState = .loading
            }
            return
        }
        trialProduct = validatedTrialProduct
        trialStoreState = .ready
    }

    /// A trial described as free must never open a paid or renewable StoreKit
    /// product because of a dashboard configuration mistake.
    private static func trialConfigurationError(for product: StoreProduct) -> String? {
        guard product.productType == .nonConsumable else {
            return "The 7-day Trial must be configured as a non-consumable App Store product."
        }
        guard product.price == Decimal.zero else {
            return "The 7-day Trial is not configured as free in this storefront."
        }
        return nil
    }

    private static func lifetimeConfigurationError(for package: Package) -> String? {
        let product = package.storeProduct
        guard product.productIdentifier == lifetimeProductID,
              product.productType == .nonConsumable,
              product.price > Decimal.zero else {
            return "The Lifetime offering must contain the paid non-consumable AirFliq product."
        }
        return nil
    }

    private static func isVerifiedAppleTrialTransaction(
        _ transaction: NonSubscriptionTransaction
    ) -> Bool {
        guard transaction.productIdentifier == trialProductID else { return false }
        switch transaction.store {
        case .appStore, .macAppStore:
            return true
        default:
            return false
        }
    }

    private func notifyChanged() {
        NotificationCenter.default.post(name: .airFliqAccessChanged, object: nil)
    }
}
