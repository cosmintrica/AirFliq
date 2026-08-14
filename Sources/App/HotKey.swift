import AppKit
import Carbon.HIToolbox

/// Global hotkey via Carbon. Unlike an NSEvent global monitor, this needs no
/// Accessibility permission.
final class HotKey {

    private static var handlerInstalled = false
    private static var callbacks: [UInt32: () -> Void] = [:]
    private static var nextID: UInt32 = 1

    private let id: UInt32
    // Carbon exposes this registration as an opaque C pointer with no Sendable
    // annotation. It is owned by this instance, assigned on the main actor and
    // touched once more only during that same instance's teardown.
    nonisolated(unsafe) private var ref: EventHotKeyRef?

    init?(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        HotKey.installHandlerIfNeeded()

        id = HotKey.nextID
        HotKey.nextID += 1
        HotKey.callbacks[id] = action

        let hotKeyID = EventHotKeyID(signature: OSType(0x41445250), id: id) // 'ADRP'
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr else {
            HotKey.callbacks[id] = nil
            return nil
        }
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        let callbackID = id
        Task { @MainActor in
            HotKey.callbacks[callbackID] = nil
        }
    }

    private static func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            guard let event else { return noErr }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event,
                                           EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID),
                                           nil,
                                           MemoryLayout<EventHotKeyID>.size,
                                           nil,
                                           &hotKeyID)
            guard status == noErr else { return noErr }
            let id = hotKeyID.id
            Task { @MainActor in
                HotKey.callbacks[id]?()
            }
            return noErr
        }, 1, &spec, nil, nil)
    }
}

// MARK: - Shortcut model

struct Shortcut: Equatable, Identifiable {
    var id: String { "\(keyCode)-\(modifiers)" }
    let name: String
    let keyCode: UInt32
    let modifiers: UInt32

    static let presets: [Shortcut] = [
        Shortcut(name: "⌃⌥A",  keyCode: UInt32(kVK_ANSI_A),  modifiers: UInt32(controlKey | optionKey)),
        Shortcut(name: "⌃⌥D",  keyCode: UInt32(kVK_ANSI_D),  modifiers: UInt32(controlKey | optionKey)),
        Shortcut(name: "⌃⌥Space", keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | optionKey)),
        Shortcut(name: "⌃⇧Space", keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | shiftKey)),
        Shortcut(name: "⌘⇧D", keyCode: UInt32(kVK_ANSI_D), modifiers: UInt32(cmdKey | shiftKey)),
        Shortcut(name: "⌘⌥⇧A", keyCode: UInt32(kVK_ANSI_A),  modifiers: UInt32(cmdKey | optionKey | shiftKey)),
        Shortcut(name: "F13",  keyCode: UInt32(kVK_F13),     modifiers: 0),
        Shortcut(name: "F14",  keyCode: UInt32(kVK_F14),     modifiers: 0),
    ]

    private static let nameKey = "shortcutName"
    private static let keyCodeKey = "shortcutKeyCode.v2"
    private static let modifiersKey = "shortcutModifiers.v2"
    private static let configuredKey = "shortcutConfigured.v2"

    static var current: Shortcut {
        get {
            let defaults = UserDefaults.standard
            if defaults.object(forKey: keyCodeKey) != nil,
               defaults.object(forKey: modifiersKey) != nil {
                let keyCode = UInt32(defaults.integer(forKey: keyCodeKey))
                let modifiers = UInt32(defaults.integer(forKey: modifiersKey))
                let storedName = defaults.string(forKey: nameKey)
                return Shortcut(name: storedName ?? displayName(keyCode: keyCode,
                                                                 modifiers: modifiers),
                                keyCode: keyCode,
                                modifiers: modifiers)
            }
            let stored = defaults.string(forKey: nameKey)
            return presets.first { $0.name == stored } ?? presets[0]
        }
        set {
            let defaults = UserDefaults.standard
            defaults.set(newValue.name, forKey: nameKey)
            defaults.set(Int(newValue.keyCode), forKey: keyCodeKey)
            defaults.set(Int(newValue.modifiers), forKey: modifiersKey)
        }
    }

    static var hasConfigured: Bool {
        get { UserDefaults.standard.bool(forKey: configuredKey) }
        set { UserDefaults.standard.set(newValue, forKey: configuredKey) }
    }

    static func from(event: NSEvent) -> Shortcut? {
        let keyCode = UInt32(event.keyCode)
        let modifiers = carbonModifiers(from: event.modifierFlags)
        guard isAllowed(keyCode: keyCode, modifiers: modifiers) else { return nil }
        return Shortcut(name: displayName(keyCode: keyCode,
                                          modifiers: modifiers,
                                          characters: event.charactersIgnoringModifiers),
                        keyCode: keyCode,
                        modifiers: modifiers)
    }

    static func isAllowed(keyCode: UInt32, modifiers: UInt32) -> Bool {
        if functionKeys.contains(keyCode) { return true }
        let modifierCount = [cmdKey, optionKey, controlKey, shiftKey]
            .filter { modifiers & UInt32($0) != 0 }
            .count
        let hasCommandModifier = modifiers & UInt32(cmdKey | optionKey | controlKey) != 0
        return modifierCount >= 2 && hasCommandModifier
    }

    static func displayName(keyCode: UInt32, modifiers: UInt32,
                            characters: String? = nil) -> String {
        var result = ""
        if modifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        result += keyLabel(keyCode: keyCode, characters: characters)
        return result
    }

    private static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        let flags = flags.intersection(.deviceIndependentFlagsMask)
        var value: UInt32 = 0
        if flags.contains(.command) { value |= UInt32(cmdKey) }
        if flags.contains(.option) { value |= UInt32(optionKey) }
        if flags.contains(.control) { value |= UInt32(controlKey) }
        if flags.contains(.shift) { value |= UInt32(shiftKey) }
        return value
    }

    private static func keyLabel(keyCode: UInt32, characters: String?) -> String {
        let labels: [UInt32: String] = [
            UInt32(kVK_Space): "Space", UInt32(kVK_Return): "Return",
            UInt32(kVK_Tab): "Tab", UInt32(kVK_Delete): "Delete",
            UInt32(kVK_ForwardDelete): "Forward Delete",
            UInt32(kVK_LeftArrow): "←", UInt32(kVK_RightArrow): "→",
            UInt32(kVK_UpArrow): "↑", UInt32(kVK_DownArrow): "↓",
            UInt32(kVK_Home): "Home", UInt32(kVK_End): "End",
            UInt32(kVK_PageUp): "Page Up", UInt32(kVK_PageDown): "Page Down",
            UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2", UInt32(kVK_F3): "F3",
            UInt32(kVK_F4): "F4", UInt32(kVK_F5): "F5", UInt32(kVK_F6): "F6",
            UInt32(kVK_F7): "F7", UInt32(kVK_F8): "F8", UInt32(kVK_F9): "F9",
            UInt32(kVK_F10): "F10", UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12",
            UInt32(kVK_F13): "F13", UInt32(kVK_F14): "F14", UInt32(kVK_F15): "F15",
            UInt32(kVK_F16): "F16", UInt32(kVK_F17): "F17", UInt32(kVK_F18): "F18",
            UInt32(kVK_F19): "F19", UInt32(kVK_F20): "F20",
        ]
        if let label = labels[keyCode] { return label }
        let value = characters?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value!.uppercased() : "Key \(keyCode)"
    }

    private static let functionKeys: Set<UInt32> = [
        UInt32(kVK_F1), UInt32(kVK_F2), UInt32(kVK_F3), UInt32(kVK_F4),
        UInt32(kVK_F5), UInt32(kVK_F6), UInt32(kVK_F7), UInt32(kVK_F8),
        UInt32(kVK_F9), UInt32(kVK_F10), UInt32(kVK_F11), UInt32(kVK_F12),
        UInt32(kVK_F13), UInt32(kVK_F14), UInt32(kVK_F15), UInt32(kVK_F16),
        UInt32(kVK_F17), UInt32(kVK_F18), UInt32(kVK_F19), UInt32(kVK_F20),
    ]
}

// MARK: - Registration

@MainActor
final class ShortcutManager {
    static let shared = ShortcutManager()

    private var hotKey: HotKey?

    private init() {}

    func start() {
        guard hotKey == nil else { return }
        _ = apply(Shortcut.current, announcesResult: false)
    }

    func pauseForRecording() {
        hotKey = nil
    }

    func resumeAfterRecording() {
        start()
    }

    @discardableResult
    func apply(_ shortcut: Shortcut, announcesResult: Bool = true) -> Bool {
        if shortcut == Shortcut.current, hotKey != nil { return true }

        // Register before releasing the existing shortcut. A collision must
        // never leave the user without their previous working gesture.
        guard let candidate = HotKey(keyCode: shortcut.keyCode,
                                     modifiers: shortcut.modifiers,
                                     action: { AirDrop.sendFinderSelection() }) else {
            if announcesResult {
                Toast.show("That shortcut is already in use",
                           subtitle: "Your previous AirFliq shortcut is still active.",
                           kind: .warning)
            }
            return false
        }

        hotKey = candidate
        Shortcut.current = shortcut
        if announcesResult {
            Toast.show("Shortcut ready",
                       subtitle: "Press \(shortcut.name) from anywhere.",
                       kind: .success)
        }
        return true
    }
}
