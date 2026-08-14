import AppKit
import SwiftUI

@MainActor
final class AboutWindowController: NSWindowController {
    static let shared = AboutWindowController()

    private convenience init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 410),
                              styleMask: [.titled, .closable, .fullSizeContentView],
                              backing: .buffered,
                              defer: false)
        window.title = "About AirFliq"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.center()
        self.init(window: window)

        let host = NSHostingView(rootView: AirFliqAboutView())
        host.frame = window.contentView?.bounds ?? .zero
        host.autoresizingMask = [.width, .height]
        window.contentView = host
    }

    func present() {
        guard let window else { return }
        window.alphaValue = 0
        window.center()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Motion.reduceMotion ? 0 : 0.42
            context.timingFunction = Motion.easeOut
            window.animator().alphaValue = 1
        }
    }
}

private struct AirFliqAboutView: View {
    @State private var entered = false

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    var body: some View {
        ZStack {
            AirFliqFlightField(intensity: 0.9)

            VStack(spacing: 0) {
                ZStack {
                    TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
                        let time = timeline.date.timeIntervalSinceReferenceDate
                        ForEach(0..<3, id: \.self) { index in
                            Circle()
                                .stroke(index == 1 ? Color.airFliqViolet.opacity(0.24)
                                                   : Color.airFliqBlue.opacity(0.18),
                                        style: StrokeStyle(lineWidth: 1,
                                                           dash: [3 + CGFloat(index), 7]))
                                .frame(width: 112 + CGFloat(index) * 25,
                                       height: 112 + CGFloat(index) * 25)
                                .rotationEffect(.degrees(time * Double(index.isMultiple(of: 2) ? 10 : -8)))
                        }
                    }

                    Image(nsImage: AirDropIcon.appIcon(size: 180))
                        .resizable()
                        .frame(width: 102, height: 102)
                        .shadow(color: .airFliqBlue.opacity(0.48), radius: 24, y: 8)
                }
                .frame(height: 164)
                .scaleEffect(entered ? 1 : 0.78)
                .opacity(entered ? 1 : 0)

                Text("AIRFLIQ")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .tracking(3.2)

                Text("Select. Fliq. Sent.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)

                HStack(spacing: 9) {
                    AboutCapsule(text: "VERSION \(version)")
                    AboutCapsule(text: "BUILD \(build)")
                    AboutCapsule(text: "UNIVERSAL")
                }
                .padding(.top, 20)

                HStack(spacing: 10) {
                    Button {
                        NSWorkspace.shared.open(URL(string: "https://github.com/cosmintrica/AirFliq")!)
                    } label: {
                        Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                    }
                    .buttonStyle(AirFliqPrimaryButtonStyle(accent: .airFliqBlue))

                    Text("Made by Cosmin Trica")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
                .padding(.top, 22)
            }
            .padding(.horizontal, 44)
            .padding(.top, 22)
            .padding(.bottom, 28)
        }
        .background(.ultraThinMaterial)
        .frame(width: 500, height: 410)
        .onAppear {
            withAnimation(.spring(response: 0.86, dampingFraction: 0.78)) { entered = true }
        }
    }
}

private struct AboutCapsule: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .tracking(0.55)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(Color.white.opacity(0.055), in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.09), lineWidth: 1))
    }
}
