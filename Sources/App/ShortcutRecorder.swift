import AppKit
import Carbon.HIToolbox
import SwiftUI

@MainActor
final class ShortcutCaptureSession: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var guidance = "Record your own combination"

    private var monitor: Any?

    func toggle(onCapture: @escaping (Shortcut) -> Bool) {
        if isRecording {
            stop()
        } else {
            start(onCapture: onCapture)
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        isRecording = false
        guidance = "Record your own combination"
        ShortcutManager.shared.resumeAfterRecording()
    }

    private func start(onCapture: @escaping (Shortcut) -> Bool) {
        stop()
        ShortcutManager.shared.pauseForRecording()
        guidance = "Press your shortcut now"
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, isRecording else { return event }
            if event.keyCode == UInt16(kVK_Escape) {
                stop()
                return nil
            }
            guard let shortcut = Shortcut.from(event: event) else {
                guidance = "Use two modifiers, or an F-key"
                NSSound.beep()
                return nil
            }
            guard onCapture(shortcut) else {
                guidance = "That combination is already used"
                return nil
            }
            stop()
            return nil
        }
    }
}

struct AirFliqShortcutRecorder: View {
    let current: Shortcut
    let onCapture: (Shortcut) -> Bool

    @StateObject private var session = ShortcutCaptureSession()
    @State private var hovered = false

    var body: some View {
        Button {
            session.toggle(onCapture: onCapture)
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(session.isRecording
                              ? Color.airFliqBlue.opacity(0.22)
                              : Color.white.opacity(0.06))
                    Image(systemName: session.isRecording ? "keyboard.badge.ellipsis" : "keyboard")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(session.isRecording ? Color.airFliqCyan : .secondary)
                }
                .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 1) {
                    Text(session.isRecording ? session.guidance : "Custom shortcut")
                        .font(.system(size: 11.5, weight: .semibold))
                    Text(session.isRecording ? "Escape cancels" : "Any safe global combination")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(session.isRecording ? "LISTENING" : current.name)
                    .font(.system(size: session.isRecording ? 8.5 : 10.5,
                                  weight: .bold,
                                  design: .monospaced))
                    .tracking(session.isRecording ? 0.8 : 0)
                    .foregroundStyle(session.isRecording ? Color.airFliqCyan : .primary)
                    .padding(.horizontal, 9)
                    .frame(height: 25)
                    .background(Color.white.opacity(0.07), in: Capsule())
            }
            .padding(.horizontal, 11)
            .frame(height: 48)
            .background(Color.white.opacity(hovered ? 0.085 : 0.045), in:
                            RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(session.isRecording ? Color.airFliqCyan.opacity(0.68)
                                                : Color.white.opacity(hovered ? 0.16 : 0.07),
                            style: StrokeStyle(lineWidth: session.isRecording ? 1.4 : 1,
                                               dash: session.isRecording ? [5, 4] : []))
            }
            .shadow(color: session.isRecording ? Color.airFliqBlue.opacity(0.28) : .clear,
                    radius: 14)
        }
        .buttonStyle(.plain)
        .onHover { value in
            withAnimation(.easeOut(duration: 0.2)) { hovered = value }
        }
        .onDisappear { session.stop() }
        .animation(.spring(response: 0.42, dampingFraction: 0.78), value: session.isRecording)
    }
}
