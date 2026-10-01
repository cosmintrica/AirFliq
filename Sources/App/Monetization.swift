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

/// Five completed sends per local calendar day are free forever, without a
/// trial. Only a share that AirDrop reports as completed is counted, so
/// cancelling the native panel never consumes the allowance.
struct FreeSendAllowance {
    static let dailyLimit = 5
    static let dayKey = "airfliq.free.day.v1"
    static let countKey = "airfliq.free.sends.v1"

    var defaults: UserDefaults = .standard
    var calendar: Calendar = .current

    func used(on date: Date = Date()) -> Int {
        guard defaults.string(forKey: Self.dayKey) == dayStamp(date) else { return 0 }
        return min(Self.dailyLimit, max(0, defaults.integer(forKey: Self.countKey)))
    }

    @discardableResult
    func recordSend(on date: Date = Date()) -> Int {
        let total = min(Self.dailyLimit, used(on: date) + 1)
        defaults.set(dayStamp(date), forKey: Self.dayKey)
        defaults.set(total, forKey: Self.countKey)
        return total
    }

    private func dayStamp(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d",
                      parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

@MainActor
final class Monetization: NSObject, @preconcurrency PurchasesDelegate, ObservableObject {
    static let shared = Monetization()
    static let trialDuration: TimeInterval = 7 * 24 * 60 * 60
    static let freeDailySendLimit = FreeSendAllowance.dailyLimit
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
    @Published private(set) var lifetimeProduct: StoreProduct?
    @Published private(set) var isConfigured = false
    @Published private(set) var storeState: StoreState = .notConfigured
    @Published private(set) var trialStoreState: StoreState = .notConfigured
    @Published private(set) var trialStartedAt: Date?
    @Published private(set) var trialReferenceDate: Date
    @Published private(set) var freeSendsUsedToday: Int
    private let freeAllowance: FreeSendAllowance
    private var usesVerifiedTrialClock = false
    private var validatedTrialProduct: StoreProduct?

    /// Injectable requests exercise the real catalog state machine without a
    /// StoreKit account. They never configure purchases or grant an entitlement.
    @MainActor struct CatalogRequests {
        var products: @MainActor (@escaping @MainActor ([StoreProduct]) -> Void) -> Void
        var offering: @MainActor (@escaping @MainActor (Package?) -> Void) -> Void
        var schedule: @MainActor (TimeInterval, @escaping @MainActor () -> Void) -> Void

        static var live: CatalogRequests {
            let trialID = Monetization.trialProductID
            let lifetimeID = Monetization.lifetimeProductID
            return CatalogRequests(
                products: { completion in
                    Purchases.shared.getProducts([trialID, lifetimeID]) { products in
                        Task { @MainActor in completion(products) }
                    }
                },
                offering: { completion in
                    Purchases.shared.getOfferings { offerings, _ in
                        let package = offerings?.current?.availablePackages.first {
                            $0.storeProduct.productIdentifier == lifetimeID
                        }
                        Task { @MainActor in completion(package) }
                    }
                },
                schedule: { delay, action in
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { action() }
                }
            )
        }
    }

    private let catalogRequests: CatalogRequests
    private var catalogGeneration = 0
    private var catalogInFlight = false
    private var productsReturned = false
    private var offeringReturned = false
    private var catalogRetryIndex = 0
    private static let catalogRetryDelays: [TimeInterval] = [1, 3, 8]

    private override convenience init() {
        self.init(catalogRequests: .live)
    }

    init(catalogRequests: CatalogRequests,
         freeAllowance: FreeSendAllowance = FreeSendAllowance()) {
        self.catalogRequests = catalogRequests
        self.freeAllowance = freeAllowance
        freeSendsUsedToday = freeAllowance.used()
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
        return "\(trialRemainingShortText) in your trial"
    }

    /// "6 days left" or "5 hours left", for compact trial status.
    var trialRemainingShortText: String {
        if trialRemainingTime < 24 * 60 * 60 {
            let hours = max(1, Int(ceil(trialRemainingTime / (60 * 60))))
            return hours == 1 ? "1 hour left" : "\(hours) hours left"
        }
        return trialDaysRemaining == 1 ? "1 day left" : "\(trialDaysRemaining) days left"
    }

    /// Pro, an active trial, or local QA. The free allowance is not unlimited.
    var hasUnlimitedSending: Bool { Self.isLocalTransferTest || isPro || isTrialActive }
    var freeSendsRemainingToday: Int {
        max(0, Self.freeDailySendLimit - freeSendsUsedToday)
    }
    var canSend: Bool { hasUnlimitedSending || freeSendsRemainingToday > 0 }

    var freeAllowanceText: String {
        switch freeSendsRemainingToday {
        case 0: return "Free sends refill tomorrow"
        case 1: return "1 free send left today"
        case let left: return "\(left) of \(Self.freeDailySendLimit) free sends left today"
        }
    }

    /// One line describing what the user can do right now.
    var accessStatusText: String {
        if Self.isLocalTransferTest { return Self.localTransferTestMessage }
        if isPro { return "Pro  •  Lifetime" }
        if isTrialActive { return "Unlimited trial  •  \(trialRemainingShortText)" }
        return freeAllowanceText
    }

    var setupSummary: String {
        if Self.isLocalTransferTest { return Self.localTransferTestMessage }
        if isPro { return "Lifetime Pro  •  Unlimited sending" }
        if isTrialActive { return "Unlimited trial  •  \(trialRemainingShortText)" }
        return "Free: \(Self.freeDailySendLimit) sends a day  •  Unlimited with Pro"
    }

    /// Never invent a storefront price. RevenueCat supplies the localized
    /// amount once StoreKit has loaded the product for the current account.
    var price: String { lifetimeProduct?.localizedPriceString ?? "one purchase" }
    var localizedLifetimePrice: String? { lifetimeProduct?.localizedPriceString }

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
        refreshCatalog()
    }

    func refresh() {
        refreshTrialClock()
        refreshFreeAllowance()
        guard isConfigured else { return }
        refreshCustomerInfo(fetchPolicy: .fetchCurrent)
        if lifetimeProduct == nil || validatedTrialProduct == nil { refreshCatalog() }
    }

    /// Counts a completed free send. Pro, an active trial and local QA are
    /// unlimited and never consume the daily allowance.
    func recordSuccessfulSend() {
        refreshTrialClock()
        refreshFreeAllowance()
        guard !hasUnlimitedSending else { return }
        freeSendsUsedToday = freeAllowance.recordSend()
        notifyChanged()
    }

    /// The allowance refills at local midnight; re-read it whenever the app
    /// becomes active or is about to send.
    func refreshFreeAllowance() {
        let used = freeAllowance.used()
        guard used != freeSendsUsedToday else { return }
        freeSendsUsedToday = used
        notifyChanged()
    }

    /// An offer code redeemed through the App Store creates a normal StoreKit
    /// transaction. Sync it to RevenueCat so the Pro entitlement appears now.
    func syncAfterOfferCodeRedemption(completion: @escaping (PurchaseOutcome) -> Void) {
        guard isConfigured, !Self.isLocalTransferTest else {
            completion(.failed("Codes can be redeemed in the Mac App Store build."))
            return
        }
        Purchases.shared.syncPurchases { [weak self] info, error in
            guard let self else { return }
            apply(info)
            if isPro {
                completion(.purchased)
            } else if let error {
                completion(.failed(error.localizedDescription))
            } else {
                completion(.nothingToRestore)
            }
        }
    }

    func resolveSendAccess(completion: @escaping (Bool) -> Void) {
        refreshTrialClock()
        refreshFreeAllowance()
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
            refreshCatalog()
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
        guard let lifetimeProduct else {
            refreshCatalog()
            completion(.failed("The Lifetime product is still loading. Please try again."))
            return
        }
        if let configurationError = Self.lifetimeConfigurationError(for: lifetimeProduct) {
            self.package = nil
            self.lifetimeProduct = nil
            storeState = .failed(configurationError)
            updateTrialReadiness()
            notifyChanged()
            completion(.failed(configurationError))
            return
        }

        let completed: PurchaseCompletedBlock = { [weak self] _, info, error, cancelled in
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
        if let package,
           package.storeProduct == lifetimeProduct {
            Purchases.shared.purchase(package: package, completion: completed)
        } else {
            Purchases.shared.purchase(product: lifetimeProduct, completion: completed)
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
#if DEBUG
        if capturesOwnedState { isPro = true }
#endif

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

    /// StoreKit products are the authority for availability and localized prices.
    /// The optional RevenueCat offering supplies package attribution only; a
    /// missing offering must not disable a valid App Store purchase or trial.
    func refreshCatalog(resetRetryBudget: Bool = true) {
        guard !catalogInFlight else { return }
        if resetRetryBudget { catalogRetryIndex = 0 }
        catalogGeneration += 1
        let generation = catalogGeneration
        catalogInFlight = true
        productsReturned = false
        offeringReturned = false
        if lifetimeProduct == nil { storeState = .loading }
        if trialProduct == nil { trialStoreState = .loading }
        notifyChanged()

        catalogRequests.products { [weak self] products in
            guard let self, catalogInFlight, catalogGeneration == generation else { return }
            productsReturned = true
            if let product = products.first(where: { $0.productIdentifier == Self.lifetimeProductID }) {
                if let error = Self.lifetimeConfigurationError(for: product) {
                    lifetimeProduct = nil
                    package = nil
                    storeState = .failed(error)
                } else {
                    lifetimeProduct = product
                    storeState = .ready
                }
            } else if lifetimeProduct == nil {
                storeState = .failed("The Lifetime product could not be loaded from the App Store. Reopen this window to try again.")
            }
            if let product = products.first(where: { $0.productIdentifier == Self.trialProductID }) {
                if let error = Self.trialConfigurationError(for: product) {
                    validatedTrialProduct = nil
                    trialProduct = nil
                    trialStoreState = .failed(error)
                } else {
                    validatedTrialProduct = product
                }
            } else if validatedTrialProduct == nil {
                trialStoreState = .failed("The free 7-day Trial could not be loaded from the App Store. Reopen this window to try again.")
            }
            updateTrialReadiness()
            notifyChanged()
            finishCatalogRequest(generation: generation)
        }
        catalogRequests.offering { [weak self] offeredPackage in
            guard let self, catalogInFlight, catalogGeneration == generation else { return }
            offeringReturned = true
            if let offeredPackage,
               Self.lifetimeConfigurationError(for: offeredPackage.storeProduct) == nil {
                package = offeredPackage
                // A valid product obtained by RevenueCat's offering is also
                // usable when the independent product request is transiently empty.
                if lifetimeProduct == nil {
                    lifetimeProduct = offeredPackage.storeProduct
                    storeState = .ready
                }
            }
            // An offering failure must never erase a valid direct product.
            updateTrialReadiness()
            notifyChanged()
            finishCatalogRequest(generation: generation)
        }
        catalogRequests.schedule(20) { [weak self] in
            guard let self, catalogInFlight, catalogGeneration == generation else { return }
            if lifetimeProduct == nil {
                storeState = .failed("The App Store is taking longer than expected. Reopen this window to try again.")
            }
            if validatedTrialProduct == nil {
                trialStoreState = .failed("The free 7-day Trial is taking longer than expected to load.")
            }
            updateTrialReadiness()
            notifyChanged()
            finishCatalogRequest(generation: generation, timedOut: true)
        }
    }

    private func finishCatalogRequest(generation: Int, timedOut: Bool = false) {
        guard timedOut || (productsReturned && offeringReturned) else { return }
        catalogInFlight = false
        guard lifetimeProduct == nil || validatedTrialProduct == nil,
              catalogRetryIndex < Self.catalogRetryDelays.count else { return }
        let delay = Self.catalogRetryDelays[catalogRetryIndex]
        catalogRetryIndex += 1
        catalogRequests.schedule(delay) { [weak self] in
            guard let self, catalogGeneration == generation, !catalogInFlight else { return }
            refreshCatalog(resetRetryBudget: false)
        }
    }

    /// Apple requires the downstream full-unlock charge to be disclosed before
    /// a time-based trial starts. Publishing trialProduct only after the exact
    /// Lifetime product and its localized price are ready keeps the Paywall's
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
        guard product.productIdentifier == trialProductID,
              product.productType == .nonConsumable else {
            return "The 7-day Trial must be configured as a non-consumable App Store product."
        }
        guard product.price == Decimal.zero else {
            return "The 7-day Trial is not configured as free in this storefront."
        }
        return nil
    }

    private static func lifetimeConfigurationError(for product: StoreProduct) -> String? {
        guard product.productIdentifier == lifetimeProductID,
              product.productType == .nonConsumable,
              product.price > Decimal.zero,
              !product.localizedPriceString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
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

#if DEBUG
    /// Design captures only: show the owned state without a purchase.
    /// RevenueCat updates cannot clear it while the capture runs.
    private var capturesOwnedState = false

    func showOwnedStateForCapture() {
        capturesOwnedState = true
        isPro = true
        notifyChanged()
    }
#endif

    private func notifyChanged() {
        NotificationCenter.default.post(name: .airFliqAccessChanged, object: nil)
    }
}
