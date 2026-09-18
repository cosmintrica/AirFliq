import AppKit
import SwiftUI

@MainActor
final class PaywallWindowController: NSWindowController {
    static let shared = PaywallWindowController()

    private convenience init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 630),
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

        let host = NSHostingView(rootView: AirFliqPaywallView(model: .shared))
        host.frame = window.contentView?.bounds ?? .zero
        host.autoresizingMask = [.width, .height]
        window.contentView = host
    }

    func present() {
        guard let window else { return }
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var entered = false
    @State private var isStartingTrial = false
    @State private var isPurchasing = false
    @State private var isRestoring = false
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

                        Text(heroDescription)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 9)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.top, 18)
                .opacity(entered ? 1 : 0)
                .scaleEffect(entered ? 1 : 0.94)

                VStack(spacing: 12) {
                    HStack(alignment: .top, spacing: 10) {
                        PaywallFeature(symbol: "paperplane.fill",
                                       title: "Unlimited sends",
                                       detail: "No counter after Pro")
                        PaywallFeature(symbol: "folder.badge.plus",
                                       title: "Smart folder access",
                                       detail: "Ask only when needed")
                        PaywallFeature(symbol: "infinity",
                                       title: "Lifetime",
                                       detail: "No subscription")
                    }

                    if model.isTrialStarted || model.isPro {
                        freeUsage
                    } else {
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

                HStack(spacing: 16) {
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

                    Circle()
                        .fill(Color.white.opacity(0.16))
                        .frame(width: 3, height: 3)

                    Text("App Store purchases restore on this Apple Account")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 5)
                .opacity(entered ? 1 : 0)
            }
            .padding(.horizontal, 30)
            .padding(.top, 24)
            .padding(.bottom, 20)
        }
        .background(.ultraThinMaterial)
        .frame(width: 540, height: 630)
        .onAppear {
            model.refresh()
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
                .foregroundStyle(model.isPro
                                 ? Color.airFliqGreen
                                 : (model.isTrialExpired ? Color.orange : .secondary))
                .padding(.horizontal, 11)
                .frame(height: 27)
                .background(Color.white.opacity(0.055), in: Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.09), lineWidth: 1))
        }
    }

    private var freeUsage: some View {
        VStack(spacing: 8) {
            HStack {
                Text(model.isPro ? "LIFETIME ACCESS" : "FULL ACCESS TRIAL")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .tracking(0.65)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(model.isPro
                     ? "UNLIMITED"
                     : (model.isTrialExpired
                        ? "ENDED"
                        : "\(model.trialDaysRemaining) DAYS LEFT"))
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(model.isPro
                                     ? Color.airFliqGreen
                                     : (model.isTrialExpired ? Color.orange : .secondary))
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
                        .frame(width: proxy.size.width * usageProgress)
                        .shadow(color: (model.isPro ? Color.airFliqGreen : .airFliqBlue)
                            .opacity(0.55), radius: 7)
                }
            }
            .frame(height: 7)
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
                Text("7-day full trial")
                    .font(.system(size: 11, weight: .bold, design: .rounded))

                Text("After day 7, file sharing, shortcuts, right-click, menu bar and drag-to-send stop sending until Lifetime Pro is unlocked.")
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
        .accessibilityHint("Starts seven days of full access after App Store confirmation. It does not renew and does not charge you.")
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
        }
        .frame(maxWidth: .infinity, minHeight: 28)
    }

    private var isBusy: Bool { isStartingTrial || isPurchasing || isRestoring }
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
            && (isMarketingCapture || (model.isConfigured && model.package != nil))
    }
    private var usageProgress: CGFloat {
        if model.isPro { return 1 }
        return CGFloat(model.trialProgress)
    }
    private var heroTitle: String {
        if model.isPro { return "Every flight is yours." }
        if !model.isTrialStarted { return "Seven days. Your choice." }
        return model.isTrialExpired ? "Keep AirFliq moving." : "Seven days. Every flight."
    }
    private var heroDescription: String {
        if model.isPro { return "AirFliq Pro is active on this Apple Account." }
        if !model.isTrialStarted {
            return "Try every AirFliq send flow, then decide if Lifetime Pro is right for you."
        }
        if model.isTrialExpired {
            return "Your full trial has ended. Unlock AirFliq forever with one purchase."
        }
        return "Every feature is open during your 7-day trial. Keep full access forever with one purchase."
    }
    private var headerStatus: String {
        if model.isPro { return "PRO ACTIVE" }
        if !model.isTrialStarted { return "TRIAL READY" }
        return model.isTrialExpired ? "TRIAL ENDED" : "7-DAY FULL TRIAL"
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
                statusMessage = "Your 7-day trial is active. Nothing will renew or charge automatically."
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

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
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
                        .rotationEffect(.degrees(reduceMotion ? 0
                            : time * Double(index.isMultiple(of: 2) ? 12 : -9)))
                }

                Circle()
                    .fill(RadialGradient(colors: [
                        (isPro ? Color.airFliqGreen : .airFliqBlue).opacity(0.34),
                        Color.clear
                    ], center: .center, startRadius: 0, endRadius: 62))
                    .frame(width: 128, height: 128)

                Circle()
                    .fill(Color.black.opacity(0.32))
                    .frame(width: 88, height: 88)
                    .overlay(Circle().stroke((isPro ? Color.airFliqGreen : .airFliqCyan)
                        .opacity(0.52), lineWidth: 1.2))

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
    }
}
