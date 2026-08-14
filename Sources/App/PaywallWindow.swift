import AppKit
import SwiftUI

@MainActor
final class PaywallWindowController: NSWindowController {
    static let shared = PaywallWindowController()

    private convenience init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 600),
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

                        Text(model.isPro ? "Every flight is yours." : "Send without limits.")
                            .font(.system(size: 31, weight: .bold, design: .rounded))
                            .tracking(-0.55)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 8)

                        Text(model.isPro
                             ? "AirFliq Pro is active on this Apple Account."
                             : "Your first 50 successful sends are free. Unlock every send after that with one purchase.")
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
                    HStack(spacing: 10) {
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

                    freeUsage
                }
                .padding(16)
                .background {
                    AirFliqGlassSurface(accent: model.isPro ? .airFliqGreen : .airFliqViolet,
                                       hovered: false)
                }
                .padding(.top, 15)
                .opacity(entered ? 1 : 0)
                .offset(y: entered ? 0 : 14)

                purchaseButton
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

                    Text("One purchase through the Mac App Store")
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
        .frame(width: 540, height: 600)
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

            Text(model.isPro ? "PRO ACTIVE" : "50 SENDS FREE")
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .tracking(0.7)
                .foregroundStyle(model.isPro ? Color.airFliqGreen : .secondary)
                .padding(.horizontal, 11)
                .frame(height: 27)
                .background(Color.white.opacity(0.055), in: Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.09), lineWidth: 1))
        }
    }

    private var freeUsage: some View {
        VStack(spacing: 8) {
            HStack {
                Text(model.isPro ? "LIFETIME ACCESS" : "FREE FLIGHT PATH")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .tracking(0.65)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(model.isPro
                     ? "UNLIMITED"
                     : "\(model.sendCount) / \(Monetization.freeSendLimit) USED")
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
                        .frame(width: proxy.size.width * usageProgress)
                        .shadow(color: (model.isPro ? Color.airFliqGreen : .airFliqBlue)
                            .opacity(0.55), radius: 7)
                }
            }
            .frame(height: 7)
        }
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
        .buttonStyle(AirFliqPrimaryButtonStyle(accent: model.isPro ? .airFliqGreen : .airFliqBlue))
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

    private var isBusy: Bool { isPurchasing || isRestoring }
    private var canPurchase: Bool {
        !model.isPro && !isBusy && model.isConfigured && model.package != nil
    }
    private var usageProgress: CGFloat {
        if model.isPro { return 1 }
        return min(1, CGFloat(model.sendCount) / CGFloat(Monetization.freeSendLimit))
    }
    private var purchaseTitle: String {
        if model.isPro { return "Lifetime Pro is active" }
        if isPurchasing { return "Connecting to the App Store" }
        return "Unlock forever for \(model.price)"
    }
    private var statusColor: Color {
        switch statusKind {
        case .neutral: return model.isPro ? .airFliqGreen : .airFliqCyan
        case .success: return .airFliqGreen
        case .warning: return .orange
        }
    }
    private var resolvedStatus: String {
        if let statusMessage { return statusMessage }
        if model.isPro { return "Unlimited sending is synced with RevenueCat." }
        switch model.storeState {
        case .notConfigured:
            return "Purchases are enabled in the Mac App Store build."
        case .loading:
            return "Loading your localized App Store price..."
        case .ready:
            return "\(model.sendsRemaining) successful sends remain before Pro."
        case .failed(let message):
            return message
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
                statusMessage = "No Lifetime Pro purchase was found for this Apple Account."
            case .failed(let message):
                statusKind = .warning
                statusMessage = message
            case .cancelled:
                statusKind = .neutral
                statusMessage = "Restore cancelled."
            }
        }
    }
}

private struct PaywallFeature: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(LinearGradient(colors: [.airFliqCyan, .airFliqViolet],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing))
                .frame(height: 18)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
            Text(detail)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
