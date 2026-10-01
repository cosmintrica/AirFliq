import AppKit
import StoreKit
import SwiftUI

/// Why the offer is on screen. A send that exhausted today's free allowance
/// gets copy that explains the refill instead of a generic sales pitch.
@MainActor
final class PaywallPresentation: ObservableObject {
    enum Reason: Equatable {
        case browse
        case dailyLimitReached
    }

    @Published var reason: Reason = .browse
    weak var window: NSWindow?
}

@MainActor
final class PaywallWindowController: NSWindowController {
    static let shared = PaywallWindowController()

    private let presentation = PaywallPresentation()

    private convenience init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 660),
                              styleMask: [.titled, .closable, .fullSizeContentView],
                              backing: .buffered,
                              defer: false)
        window.title = "AirFliq Pro"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.center()
        self.init(window: window)
        presentation.window = window

        let host = NSHostingView(rootView: AirFliqPaywallView(model: .shared,
                                                              presentation: presentation))
        host.frame = window.contentView?.bounds ?? .zero
        host.autoresizingMask = [.width, .height]
        // StoreKit's AppKit redemption sheet on macOS 15-26 needs a view
        // controller. Wrapping the existing host keeps its exact layout.
        let controller = NSViewController()
        controller.view = host
        window.contentViewController = controller
        window.setContentSize(NSSize(width: 540, height: 660))
    }

    func present(reason: PaywallPresentation.Reason = .browse) {
        guard let window else { return }
        presentation.reason = reason
        Monetization.shared.refresh()
        window.center()
        window.alphaValue = 0
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Motion.reduceMotion ? 0 : 0.44
            context.timingFunction = Motion.easeOut
            window.animator().alphaValue = 1
        }
    }
}

private struct AirFliqPaywallView: View {
    @ObservedObject var model: Monetization
    @ObservedObject var presentation: PaywallPresentation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var entered = false
    @State private var isStartingTrial = false
    @State private var isPurchasing = false
    @State private var isRestoring = false
    @State private var isRedeeming = false
    @State private var statusMessage: String?
    @State private var statusKind: StatusKind = .neutral
    @State private var successPulse = false

    private enum StatusKind {
        case neutral
        case success
        case warning
    }

    var body: some View {
        ZStack {
            AirFliqFlightField(intensity: model.isPro ? 1.25 : 0.95)

            VStack(spacing: 0) {
                header
                    .opacity(entered ? 1 : 0)
                    .offset(y: entered ? 0 : -10)

                HStack(spacing: 28) {
                    ProOrbit(isPro: model.isPro,
                             successPulse: successPulse)
                        .frame(width: 164, height: 164)

                    VStack(alignment: .leading, spacing: 0) {
                        Text(model.isPro ? "LIFETIME UNLOCKED" : "AIRFLIQ PRO")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .tracking(1.8)
                            .foregroundStyle(model.isPro ? Color.airFliqGreen : .airFliqCyan)

                        Text(heroTitle)
                            .font(.system(size: 31, weight: .bold, design: .rounded))
                            .tracking(-0.55)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 8)
                            .contentTransition(.opacity)

                        Text(heroDescription)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 9)
                            .contentTransition(.opacity)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .animation(.spring(response: 0.55, dampingFraction: 0.86), value: heroTitle)
                }
                .padding(.top, 18)
                .opacity(entered ? 1 : 0)
                .scaleEffect(entered ? 1 : 0.94)
                .blur(radius: entered || reduceMotion ? 0 : 8)

                VStack(spacing: 12) {
                    HStack(alignment: .top, spacing: 10) {
                        PaywallFeature(symbol: "paperplane.fill",
                                       title: "Unlimited sends",
                                       detail: "No daily limit")
                        PaywallFeature(symbol: "point.3.connected.trianglepath.dotted",
                                       title: "Every route",
                                       detail: "Right-click, drag, shortcut")
                        PaywallFeature(symbol: "infinity",
                                       title: "Lifetime",
                                       detail: "No subscription")
                    }

                    usage

                    if !model.isTrialStarted && !model.isPro {
                        trialDisclosure
                    }
                }
                .padding(16)
                .background {
                    AirFliqGlassSurface(accent: model.isPro ? .airFliqGreen : .airFliqViolet,
                                       hovered: false)
                }
                .padding(.top, 15)
                .opacity(entered ? 1 : 0)
                .offset(y: entered ? 0 : 14)

                VStack(spacing: 10) {
                    if !model.isTrialStarted && !model.isPro {
                        startTrialButton
                    }
                    purchaseButton
                }
                .padding(.top, 17)
                .opacity(entered ? 1 : 0)
                .offset(y: entered ? 0 : 18)

                status
                    .padding(.top, 9)

                HStack(spacing: 14) {
                    Button(action: restore) {
                        HStack(spacing: 7) {
                            if isRestoring {
                                AirFliqCometLoader(color: .airFliqCyan)
                                    .frame(width: 15, height: 15)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                            }
                            Text("Restore Purchase")
                        }
                    }
                    .buttonStyle(AirFliqTextButtonStyle())
                    .disabled(!model.isConfigured || isBusy)

                    if OfferCodeRedemption.isSupported && !model.isPro {
                        Circle()
                            .fill(Color.white.opacity(0.16))
                            .frame(width: 3, height: 3)

                        Button(action: redeemCode) {
                            HStack(spacing: 7) {
                                if isRedeeming {
                                    AirFliqCometLoader(color: .airFliqCyan)
                                        .frame(width: 15, height: 15)
                                } else {
                                    Image(systemName: "ticket")
                                }
                                Text("Redeem Code")
                            }
                        }
                        .buttonStyle(AirFliqTextButtonStyle())
                        .disabled(!model.isConfigured || isBusy)
                    }

                }
                .padding(.top, 5)
                .opacity(entered ? 1 : 0)
            }
            .padding(.horizontal, 30)
            .padding(.top, 24)
            .padding(.bottom, 20)
        }
        .background(.ultraThinMaterial)
        .frame(width: 540, height: 660)
        .onAppear {
            if !isBusy { statusMessage = nil; statusKind = .neutral }
            model.refresh()
            entered = false
            withAnimation(.spring(response: 0.88, dampingFraction: 0.82)) {
                entered = true
            }
        }
        .onChange(of: model.isPro) { isPro in
            guard isPro else { return }
            withAnimation(.spring(response: 0.72, dampingFraction: 0.66)) {
                successPulse.toggle()
            }
        }
        .onChange(of: model.isTrialStarted) { started in
            guard started, !model.isPro else { return }
            withAnimation(.spring(response: 0.72, dampingFraction: 0.66)) {
                successPulse.toggle()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: AirDropIcon.appIcon(size: 80))
                .resizable()
                .frame(width: 38, height: 38)
                .shadow(color: .airFliqBlue.opacity(0.48), radius: 10)

            VStack(alignment: .leading, spacing: 1) {
                Text("AIRFLIQ")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .tracking(1.8)
                Text("Select. Fliq. Sent.")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(headerStatus)
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .tracking(0.7)
                .foregroundStyle(headerStatusColor)
                .padding(.horizontal, 11)
                .frame(height: 27)
                .background(Color.white.opacity(0.055), in: Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.09), lineWidth: 1))
                .contentTransition(.opacity)
                .animation(.easeOut(duration: 0.3), value: headerStatus)
        }
    }

    @ViewBuilder
    private var usage: some View {
        if model.isPro || model.isTrialActive {
            unlimitedUsage
        } else {
            freeUsage
        }
    }

    private var unlimitedUsage: some View {
        VStack(spacing: 8) {
            HStack {
                Text(model.isPro ? "LIFETIME ACCESS" : "UNLIMITED TRIAL")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .tracking(0.65)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(model.isPro
                     ? "UNLIMITED"
                     : "\(model.trialRemainingShortText.uppercased())")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(model.isPro ? Color.airFliqGreen : .secondary)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.075))
                    Capsule()
                        .fill(LinearGradient(colors: model.isPro
                                             ? [.airFliqGreen, .airFliqCyan]
                                             : [.airFliqCyan, .airFliqBlue, .airFliqViolet],
                                             startPoint: .leading,
                                             endPoint: .trailing))
                        .frame(width: proxy.size.width * (entered ? unlimitedProgress : 0))
                        .shadow(color: (model.isPro ? Color.airFliqGreen : .airFliqBlue)
                            .opacity(0.55), radius: 7)
                        .animation(.spring(response: 1.1, dampingFraction: 0.86).delay(0.25),
                                   value: entered)
                }
            }
            .frame(height: 7)
        }
    }

    /// Five segments, one per free send. Lit segments are the sends still
    /// available today, so the meter drains as the user sends.
    private var freeUsage: some View {
        VStack(spacing: 8) {
            HStack {
                Text("FREE SENDS TODAY")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .tracking(0.65)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(model.freeSendsRemainingToday == 0
                     ? "REFILLS TOMORROW"
                     : "\(model.freeSendsRemainingToday) OF \(Monetization.freeDailySendLimit) LEFT")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(model.freeSendsRemainingToday == 0 ? Color.orange : .secondary)
            }

            HStack(spacing: 6) {
                ForEach(0..<Monetization.freeDailySendLimit, id: \.self) { index in
                    let lit = index < model.freeSendsRemainingToday
                    Capsule()
                        .fill(lit
                              ? AnyShapeStyle(LinearGradient(colors: [.airFliqCyan, .airFliqBlue,
                                                                      .airFliqViolet],
                                                             startPoint: .leading,
                                                             endPoint: .trailing))
                              : AnyShapeStyle(Color.white.opacity(0.075)))
                        .frame(height: 7)
                        .shadow(color: lit ? Color.airFliqBlue.opacity(0.55) : .clear, radius: 6)
                        .scaleEffect(x: entered ? 1 : 0.2, y: 1, anchor: .leading)
                        .opacity(entered ? 1 : 0)
                        .animation(.spring(response: 0.6, dampingFraction: 0.78)
                            .delay(0.22 + Double(index) * 0.06), value: entered)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: lit)
                }
            }
        }
    }

    private var trialDisclosure: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "calendar.badge.checkmark")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.airFliqCyan)
                .frame(width: 30, height: 30)
                .background(Color.airFliqCyan.opacity(0.10), in: Circle())
                .overlay(Circle().stroke(Color.airFliqCyan.opacity(0.18), lineWidth: 1))

            VStack(alignment: .leading, spacing: 4) {
                Text("7-day unlimited trial")
                    .font(.system(size: 11, weight: .bold, design: .rounded))

                Text("Unlimited sending from every route for 7 days. When it ends, you keep \(Monetization.freeDailySendLimit) free sends per day; unlimited sending then needs Lifetime Pro.")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineSpacing(1.5)
                    .fixedSize(horizontal: false, vertical: true)

                Text("No automatic renewal or charge. \(lifetimeDisclosure)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.76))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, 11)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.09))
                .frame(height: 1)
        }
    }

    private var startTrialButton: some View {
        Button(action: startTrial) {
            HStack(spacing: 10) {
                if isStartingTrial {
                    AirFliqCometLoader(color: .white)
                        .frame(width: 19, height: 19)
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .bold))
                }
                Text(isStartingTrial ? "Confirming with the App Store" : "Start free 7-day trial")
                    .font(.system(size: 14, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
        }
        .buttonStyle(AirFliqPrimaryButtonStyle(accent: .airFliqViolet))
        .disabled(!canStartTrial)
        .opacity(canStartTrial ? 1 : 0.58)
        .accessibilityHint("Starts seven days of unlimited sending after App Store confirmation. It does not renew and does not charge you.")
    }

    private var purchaseButton: some View {
        Button(action: purchase) {
            HStack(spacing: 10) {
                if isPurchasing {
                    AirFliqCometLoader(color: .white)
                        .frame(width: 19, height: 19)
                } else {
                    Image(systemName: model.isPro ? "checkmark.seal.fill" : "infinity")
                        .font(.system(size: 14, weight: .bold))
                }
                Text(purchaseTitle)
                    .font(.system(size: 14, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
        }
        .buttonStyle(PaywallPurchaseButtonStyle(
            accent: model.isPro ? .airFliqGreen : .airFliqBlue,
            prominent: model.isTrialStarted || model.isPro
        ))
        .disabled(!canPurchase)
        .opacity(canPurchase || model.isPro ? 1 : 0.58)
    }

    private var status: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
                .shadow(color: statusColor.opacity(0.65), radius: 5)
            Text(resolvedStatus)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .contentTransition(.opacity)
        }
        .frame(maxWidth: .infinity, minHeight: 28)
        .animation(.easeOut(duration: 0.25), value: resolvedStatus)
    }

    private var isBusy: Bool { isStartingTrial || isPurchasing || isRestoring || isRedeeming }
    private var isMarketingCapture: Bool {
#if AIRFLIQ_MARKETING_CAPTURE
        true
#elseif DEBUG
        ProcessInfo.processInfo.environment["AIRFLIQ_CAPTURE_MODE"] == "paywall"
#else
        false
#endif
    }
    private var canStartTrial: Bool {
        !model.isPro && !model.isTrialStarted && !isBusy
            && (isMarketingCapture || (model.isConfigured && model.trialProduct != nil))
    }
    private var canPurchase: Bool {
        !model.isPro && !isBusy
            && (isMarketingCapture || (model.isConfigured && model.lifetimeProduct != nil))
    }
    private var unlimitedProgress: CGFloat {
        if model.isPro { return 1 }
        return CGFloat(max(0.04, 1 - model.trialProgress))
    }
    private var limitReached: Bool {
        presentation.reason == .dailyLimitReached && !model.canSend
    }
    private var heroTitle: String {
        if model.isPro { return "Every flight is yours." }
        if model.isTrialActive { return "Seven days. Every flight." }
        if limitReached { return "That's today's \(Monetization.freeDailySendLimit)." }
        if model.isTrialExpired { return "Keep every flight." }
        return "Send without limits."
    }
    private var heroDescription: String {
        if model.isPro { return "AirFliq Pro is active on this Apple Account. Send as much as you like." }
        if model.isTrialActive {
            return "Unlimited sending is on during your trial. Keep it forever with one purchase."
        }
        if limitReached {
            return model.isTrialStarted
                ? "Your free sends refill tomorrow. Unlock Lifetime Pro to keep sending right now."
                : "Your free sends refill tomorrow. Start the free 7-day trial or unlock Lifetime Pro to keep sending now."
        }
        if model.isTrialExpired {
            return "Your trial has ended and you are back to \(Monetization.freeDailySendLimit) free sends a day. Unlock unlimited sending forever with one purchase."
        }
        return "You get \(Monetization.freeDailySendLimit) free sends every day. Try unlimited sending free for 7 days, or keep it forever with one purchase."
    }
    private var headerStatus: String {
        if model.isPro { return "PRO ACTIVE" }
        if model.isTrialActive { return "UNLIMITED TRIAL" }
        return model.freeSendsRemainingToday == 0
            ? "FREE  •  REFILLS TOMORROW"
            : "FREE  •  \(model.freeSendsRemainingToday) LEFT TODAY"
    }
    private var headerStatusColor: Color {
        if model.isPro { return .airFliqGreen }
        if model.isTrialActive { return .airFliqCyan }
        return model.freeSendsRemainingToday == 0 ? .orange : .secondary
    }
    private var lifetimeDisclosure: String {
        if let price = model.localizedLifetimePrice {
            return "Lifetime Pro costs \(price) once."
        }
        if isMarketingCapture {
            return "Lifetime Pro costs $4.99 once."
        }
        return "The localized one-time Lifetime Pro price appears when the App Store finishes loading."
    }
    private var purchaseTitle: String {
        if model.isPro { return "Lifetime Pro is active" }
        if isPurchasing { return "Connecting to the App Store" }
        if isMarketingCapture { return "Unlock Lifetime Pro for $4.99" }
        return model.localizedLifetimePrice.map { "Unlock Lifetime Pro for \($0)" }
            ?? "Unlock Lifetime Pro"
    }
    private var statusColor: Color {
        if isMarketingCapture { return .airFliqCyan }
        switch statusKind {
        case .neutral:
            if !model.isTrialStarted,
               case .failed = model.trialStoreState {
                return .orange
            }
            return model.isPro ? .airFliqGreen : .airFliqCyan
        case .success: return .airFliqGreen
        case .warning: return .orange
        }
    }
    private var resolvedStatus: String {
        if let statusMessage { return statusMessage }
        if model.isPro { return "Unlimited sending is synced with RevenueCat." }
        if isMarketingCapture {
            return "The trial waits for your App Store confirmation and never renews."
        }
        if !model.isTrialStarted {
            switch model.trialStoreState {
            case .notConfigured:
                return "Trial activation is available in the Mac App Store build."
            case .loading:
                return "Loading the free App Store trial..."
            case .ready:
                return "The trial waits for your confirmation and never renews."
            case .failed(let message):
                return message
            }
        }
        switch model.storeState {
        case .notConfigured:
            return model.isTrialExpired
                ? "Purchases are enabled in the Mac App Store build."
                : model.trialStatusText
        case .loading:
            return "Loading your localized App Store price..."
        case .ready:
            return model.isTrialExpired
                ? "Your trial is complete. Lifetime Pro is ready."
                : model.trialStatusText
        case .failed(let message):
            return message
        }
    }

    private func startTrial() {
        guard canStartTrial else { return }
        isStartingTrial = true
        statusKind = .neutral
        statusMessage = "Opening the free App Store trial confirmation..."
        model.startTrial { outcome in
            isStartingTrial = false
            switch outcome {
            case .trialStarted, .trialRestored:
                statusKind = .success
                statusMessage = "Your 7-day unlimited trial is active. Nothing will renew or charge automatically."
            case .cancelled:
                statusKind = .neutral
                statusMessage = "Trial start cancelled. Your 7 days have not started."
            case .trialExpired:
                statusKind = .warning
                statusMessage = "This Apple Account has already used the 7-day trial."
            case .failed(let message):
                statusKind = .warning
                statusMessage = message
            case .purchased, .restored, .nothingToRestore:
                break
            }
        }
    }

    private func purchase() {
        guard canPurchase else { return }
        isPurchasing = true
        statusKind = .neutral
        statusMessage = "Opening the secure App Store purchase sheet..."
        model.purchase { outcome in
            isPurchasing = false
            switch outcome {
            case .purchased:
                statusKind = .success
                statusMessage = "Lifetime Pro unlocked."
            case .cancelled:
                statusKind = .neutral
                statusMessage = "Purchase cancelled. Nothing was charged."
            case .failed(let message):
                statusKind = .warning
                statusMessage = message
            case .restored, .nothingToRestore:
                break
            case .trialStarted, .trialRestored, .trialExpired:
                break
            }
        }
    }

    private func restore() {
        guard model.isConfigured, !isBusy else { return }
        isRestoring = true
        statusKind = .neutral
        statusMessage = "Checking this Apple Account..."
        model.restore { outcome in
            isRestoring = false
            switch outcome {
            case .restored, .purchased:
                statusKind = .success
                statusMessage = "Lifetime Pro restored."
            case .nothingToRestore:
                statusKind = .neutral
                statusMessage = "No Lifetime Pro or 7-day Trial was found for this Apple Account."
            case .trialRestored:
                statusKind = .success
                statusMessage = "Your active 7-day trial was restored."
            case .trialExpired:
                statusKind = .neutral
                statusMessage = "Your 7-day trial was restored, but it has ended."
            case .failed(let message):
                statusKind = .warning
                statusMessage = message
            case .cancelled:
                statusKind = .neutral
                statusMessage = "Restore cancelled."
            case .trialStarted:
                statusKind = .success
                statusMessage = "Your 7-day trial is active."
            }
        }
    }

    private func redeemCode() {
        guard model.isConfigured, !isBusy, let window = presentation.window else { return }
        isRedeeming = true
        statusKind = .neutral
        statusMessage = "Opening App Store code redemption..."
        Task { @MainActor in
            do {
                try await OfferCodeRedemption.present(from: window)
            } catch {
                isRedeeming = false
                if OfferCodeRedemption.isCancellation(error) {
                    statusKind = .neutral
                    statusMessage = "Code redemption closed. Nothing changed."
                } else {
                    statusKind = .warning
                    statusMessage = error.localizedDescription
                }
                return
            }
            statusMessage = "Confirming your code with the App Store..."
            model.syncAfterOfferCodeRedemption { outcome in
                isRedeeming = false
                switch outcome {
                case .purchased, .restored:
                    statusKind = .success
                    statusMessage = "Code redeemed. Lifetime Pro is active."
                case .failed(let message):
                    statusKind = .warning
                    statusMessage = message
                default:
                    statusKind = .neutral
                    statusMessage = "No redeemed code was found yet. If you just redeemed one, choose Restore Purchase in a moment."
                }
            }
        }
    }
}

/// StoreKit's native offer-code sheet. Offer codes unlock Lifetime Pro for free
/// (for example for contest judges); RevenueCat then syncs the transaction.
@MainActor
enum OfferCodeRedemption {
    static var isSupported: Bool {
        if #available(macOS 15.0, *) { return true }
        return false
    }

    static func present(from window: NSWindow) async throws {
        if #available(macOS 27.0, *) {
            _ = try await AppStore.presentOfferCodeRedeemSheet(from: window)
        } else if #available(macOS 15.0, *) {
            guard let controller = window.contentViewController else { return }
            try await AppStore.presentOfferCodeRedeemSheet(from: controller)
        }
    }

    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let storeError = error as? StoreKitError, case .userCancelled = storeError {
            return true
        }
        return (error as NSError).code == NSUserCancelledError
    }
}

private struct PaywallFeature: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .center, spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(LinearGradient(colors: [.airFliqCyan, .airFliqViolet],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing))
                .frame(maxWidth: .infinity, minHeight: 18, alignment: .center)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
            Text(detail)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }
}

private struct PaywallPurchaseButtonStyle: ButtonStyle {
    let accent: Color
    let prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(prominent ? Color.white : Color.white.opacity(0.86))
            .background {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(
                        prominent
                            ? AnyShapeStyle(LinearGradient(colors: [accent.opacity(0.98),
                                                                    .airFliqBlue,
                                                                    .airFliqViolet.opacity(0.92)],
                                                           startPoint: .leading,
                                                           endPoint: .trailing))
                            : AnyShapeStyle(Color.white.opacity(configuration.isPressed ? 0.08 : 0.045))
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(prominent ? Color.white.opacity(0.14) : accent.opacity(0.28),
                            lineWidth: 1)
            }
            .shadow(color: prominent ? accent.opacity(0.26) : .clear,
                    radius: prominent ? 10 : 0,
                    y: prominent ? 3 : 0)
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .animation(.spring(response: 0.32, dampingFraction: 0.78),
                       value: configuration.isPressed)
    }
}

private struct ProOrbit: View {
    let isPro: Bool
    let successPulse: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var burst: CGFloat = 1

    private var accent: Color { isPro ? .airFliqGreen : .airFliqCyan }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: reduceMotion)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .stroke(index == 1 ? Color.airFliqViolet.opacity(0.28)
                                           : Color.airFliqBlue.opacity(0.20),
                                style: StrokeStyle(lineWidth: 1,
                                                   dash: [3 + CGFloat(index), 7]))
                        .frame(width: 104 + CGFloat(index) * 23,
                               height: 104 + CGFloat(index) * 23)
                        .rotationEffect(.degrees(time * Double(index.isMultiple(of: 2) ? 12 : -9)))
                }

                // A comet that keeps circling the offer: motion that reads as
                // "in flight" without competing with the copy beside it.
                Circle()
                    .trim(from: 0, to: 0.26)
                    .stroke(AngularGradient(colors: [accent.opacity(0), accent.opacity(0.95)],
                                            center: .center,
                                            startAngle: .degrees(0),
                                            endAngle: .degrees(94)),
                            style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                    .frame(width: 127, height: 127)
                    .rotationEffect(.degrees(time * 64))
                    .shadow(color: accent.opacity(0.8), radius: 5)

                Canvas { context, size in
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    for index in 0..<9 {
                        let speed = 0.28 + Double(index % 3) * 0.11
                        let angle = time * speed + Double(index) * (.pi * 2 / 9)
                        let radius = 56 + CGFloat(index % 3) * 11
                        let twinkle = 0.35 + 0.35 * (1 + sin(time * 2.1 + Double(index))) / 2
                        let point = CGPoint(x: center.x + CGFloat(cos(angle)) * radius,
                                            y: center.y + CGFloat(sin(angle)) * radius)
                        let side: CGFloat = index.isMultiple(of: 3) ? 3.2 : 2.2
                        context.fill(Path(ellipseIn: CGRect(x: point.x - side / 2,
                                                            y: point.y - side / 2,
                                                            width: side, height: side)),
                                     with: .color(accent.opacity(twinkle)))
                    }
                }

                Circle()
                    .fill(RadialGradient(colors: [accent.opacity(0.34), Color.clear],
                                         center: .center, startRadius: 0, endRadius: 62))
                    .frame(width: 128, height: 128)
                    .scaleEffect(1 + 0.04 * sin(time * 1.6))

                Circle()
                    .fill(Color.black.opacity(0.32))
                    .frame(width: 88, height: 88)
                    .overlay(Circle().stroke(accent.opacity(0.52), lineWidth: 1.2))

                Image(systemName: isPro ? "checkmark" : "infinity")
                    .font(.system(size: isPro ? 34 : 39, weight: .bold))
                    .foregroundStyle(LinearGradient(colors: isPro
                                                    ? [.white, .airFliqGreen]
                                                    : [.white, .airFliqCyan, .airFliqViolet],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing))
                    .scaleEffect(successPulse ? 1.08 : 1)
            }
        }
        .overlay {
            ZStack {
                ForEach(0..<2, id: \.self) { ring in
                    Circle()
                        .stroke(accent.opacity(0.9), lineWidth: 2 - CGFloat(ring) * 0.8)
                        .frame(width: 92, height: 92)
                        .scaleEffect(0.9 + burst * (1.0 + CGFloat(ring) * 0.35))
                        .opacity(Double(1 - burst) * 0.85)
                }
            }
            .allowsHitTesting(false)
        }
        .onChange(of: successPulse) { _ in
            guard !reduceMotion else { return }
            burst = 0
            withAnimation(.easeOut(duration: 1.1)) { burst = 1 }
        }
    }
}
