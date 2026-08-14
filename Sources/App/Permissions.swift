import AppKit
import Carbon
import FinderSync
nonisolated enum PermissionState: Equatable, Sendable {
    case granted
    case denied
    case unknown
}

/// Everything AirFliq needs macOS to allow, in one place.
///
@MainActor
enum Permissions {

    nonisolated static let extensionIdentifier = "com.cosmintrica.airfliq.finder"

    private static let hasRunSetupKey = "hasRunSetup"
    private static let hasRequestedAutomationKey =
        "airfliq.onboarding.didRequestFinderAutomation.v1"
    private static let hasRequestedFinderExtensionKey =
        "airfliq.onboarding.didRequestFinderExtension.v1"
    private static let folderBookmarksKey = "selectedFolderBookmarks"
    private static var activeFolderURLs: [URL] = []
    private static var warmedFolderPanel: NSOpenPanel?

    /// NSOpenPanel performs service discovery the first time it is created.
    /// Preparing it while the user is on the Finder step removes that work
    /// from the Choose click without requesting or reading anything.
    static func prewarmFolderPicker() {
        guard warmedFolderPanel == nil else { return }
        warmedFolderPanel = makeFolderPanel()
    }

    static var hasRunSetup: Bool {
        get { UserDefaults.standard.bool(forKey: hasRunSetupKey) }
        set { UserDefaults.standard.set(newValue, forKey: hasRunSetupKey) }
    }

    static var hasRequestedFinderExtension: Bool {
        get { UserDefaults.standard.bool(forKey: hasRequestedFinderExtensionKey) }
        set { UserDefaults.standard.set(newValue, forKey: hasRequestedFinderExtensionKey) }
    }

    static var hasRequestedAutomation: Bool {
        get { UserDefaults.standard.bool(forKey: hasRequestedAutomationKey) }
        set { UserDefaults.standard.set(newValue, forKey: hasRequestedAutomationKey) }
    }

    // MARK: - Automation (Apple Events → Finder)

    /// Reading the Finder selection goes through Apple Events, which macOS gates
    /// behind the Automation privacy setting.
    nonisolated static func automationState(askUser: Bool = false) -> PermissionState {
        guard let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.finder").aeDesc else {
            return .unknown
        }
        let status = AEDeterminePermissionToAutomateTarget(target, typeWildCard, typeWildCard, askUser)
        switch status {
        case noErr:
            return .granted
        case OSStatus(-1744):   // errAEEventWouldRequireUserConsent
            return .unknown
        default:
            return .denied
        }
    }

    /// Blocks while the system alert is up, so never call this on the main thread.
    static func requestAutomation(completion: @escaping (PermissionState) -> Void) {
        hasRequestedAutomation = true
        Task {
            let state = await Task.detached(priority: .userInitiated) {
                automationState(askUser: true)
            }.value
            completion(state)
        }
    }

    // MARK: - User-selected folders

    /// Access is based only on folders the user explicitly chose in NSOpenPanel.
    /// AirFliq never probes Desktop, Documents or Downloads on its own.
    static func filesState() -> PermissionState {
        let resolution = resolveFolderBookmarks()
        guard resolution.totalCount > 0 else { return .unknown }
        guard resolution.urls.count == resolution.totalCount else { return .denied }

        activateFolderAccess(resolution.urls)
        return resolution.urls.allSatisfy {
            FileManager.default.isReadableFile(atPath: $0.path)
        } ? .granted : .denied
    }

    static var selectedFolderCount: Int {
        resolveFolderBookmarks().urls.count
    }

    static var folderAccessDescription: String {
        let resolution = resolveFolderBookmarks()
        guard resolution.totalCount > 0 else {
            return "Choose only the folders you want AirFliq to access."
        }
        guard resolution.urls.count == resolution.totalCount else {
            return "Some selected folders are unavailable. Choose them again."
        }

        let names = resolution.urls.map(folderDisplayName)
        if names.count <= 2 {
            return "Access: \(names.joined(separator: ", ")). Use Manage to change it."
        }
        return "Access: \(names.prefix(2).joined(separator: ", ")) and \(names.count - 2) more."
    }

    static func requestFiles(attachedTo parentWindow: NSWindow?,
                             completion: @escaping (PermissionState) -> Void) {
        if selectedFolderCount > 0 {
            presentFolderManagement(attachedTo: parentWindow, completion: completion)
        } else {
            presentFolderPicker(attachedTo: parentWindow, completion: completion)
        }
    }

    /// When a send reaches a folder outside the user's current choices, explain
    /// the exact missing scope and let the user choose it. Nothing is granted
    /// automatically and existing folder choices are preserved.
    static func requestAccess(to urls: [URL], attachedTo parentWindow: NSWindow?,
                              completion: @escaping (Bool) -> Void) {
        let folders = Array(Set(urls.map {
            var isDirectory: ObjCBool = false
            FileManager.default.fileExists(atPath: $0.path, isDirectory: &isDirectory)
            return (isDirectory.boolValue ? $0 : $0.deletingLastPathComponent()).standardizedFileURL
        })).sorted { $0.path < $1.path }
        guard let first = folders.first else { completion(false); return }

        let alert = NSAlert()
        alert.messageText = folders.count == 1
            ? "Allow access to \(folderDisplayName(first))?"
            : "Allow access to these folders?"
        alert.informativeText = folders.count == 1
            ? "AirFliq cannot read the selected item yet. Choose \(folderDisplayName(first)), or a parent folder, to continue this send."
            : "AirFliq cannot read some selected items yet. Choose their folders, or a shared parent folder, to continue this send."
        alert.addButton(withTitle: folders.count == 1 ? "Choose Folder" : "Choose Folders")
        alert.addButton(withTitle: "Cancel")
        present(alert, attachedTo: parentWindow) { response in
            guard response == .alertFirstButtonReturn else { completion(false); return }
            let panel = NSOpenPanel()
            panel.title = "Choose access for AirFliq"
            panel.message = "Only the folders you choose will be saved."
            panel.prompt = "Allow Access"
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.allowsMultipleSelection = folders.count > 1
            panel.canCreateDirectories = false
            panel.resolvesAliases = true
            panel.directoryURL = first.deletingLastPathComponent()
            let handler: (NSApplication.ModalResponse) -> Void = { result in
                guard result == .OK else { completion(false); return }
                saveFolderAccess(panel.urls, replacing: false)
                completion(urls.allSatisfy { FileManager.default.isReadableFile(atPath: $0.path) })
            }
            present(panel, attachedTo: parentWindow, completion: handler)
        }
    }

    static func showFilesAccessHelp(attachedTo parentWindow: NSWindow?) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Selected folder access is missing"
        alert.informativeText =
            "AirFliq only uses folders you choose. Select the unavailable folder again, " +
            "or review AirFliq under Privacy & Security > Files & Folders."
        alert.addButton(withTitle: "Choose Folders")
        alert.addButton(withTitle: "Open Files & Folders")
        alert.addButton(withTitle: "Cancel")

        present(alert, attachedTo: parentWindow) { response in
            if response == .alertFirstButtonReturn {
                presentFolderPicker(attachedTo: parentWindow) { _ in }
            } else if response == .alertSecondButtonReturn {
                openFilesSettings()
            }
        }
    }

    private static func presentFolderManagement(
        attachedTo parentWindow: NSWindow?,
        completion: @escaping (PermissionState) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = "Manage folder access"
        alert.informativeText =
            "\(folderAccessDescription)\n\nChoosing again replaces the current list. " +
            "AirFliq never requests other folders automatically."
        alert.addButton(withTitle: "Choose Folders")
        alert.addButton(withTitle: "Remove Access")
        alert.addButton(withTitle: "Cancel")

        present(alert, attachedTo: parentWindow) { response in
            switch response {
            case .alertFirstButtonReturn:
                // Let the first sheet finish its dismissal before attaching the
                // picker. Starting two sheets in the same run-loop turn makes
                // AppKit visibly stall and sometimes drops keyboard focus.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                    presentFolderPicker(attachedTo: parentWindow, completion: completion)
                }
            case .alertSecondButtonReturn:
                clearFolderAccess()
                completion(.unknown)
            default:
                completion(filesState())
            }
        }
    }

    private static func presentFolderPicker(
        attachedTo parentWindow: NSWindow?,
        completion: @escaping (PermissionState) -> Void
    ) {
        let panel = warmedFolderPanel ?? makeFolderPanel()
        warmedFolderPanel = panel

        let handler: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK else {
                completion(filesState())
                return
            }
            saveFolderAccess(panel.urls, replacing: true)
            completion(filesState())
        }

        NSApp.activate(ignoringOtherApps: true)
        if let parentWindow, let screen = parentWindow.screen {
            let visible = screen.visibleFrame
            let origin = NSPoint(
                x: min(max(parentWindow.frame.midX - panel.frame.width / 2,
                           visible.minX + 18), visible.maxX - panel.frame.width - 18),
                y: min(max(parentWindow.frame.midY - panel.frame.height / 2,
                           visible.minY + 18), visible.maxY - panel.frame.height - 18)
            )
            panel.setFrameOrigin(origin)
        }
        // A standalone asynchronous panel keeps the animated onboarding view
        // alive. A sheet pauses and snapshots parts of the parent window,
        // which looked like a temporary application freeze.
        panel.begin(completionHandler: handler)
    }

    private static func makeFolderPanel() -> NSOpenPanel {
        let panel = NSOpenPanel()
        panel.title = "Choose folders for AirFliq"
        panel.message =
            "Choose only the folders AirFliq may use. Hold Command to select more than one."
        panel.prompt = "Allow Selected Folders"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        panel.resolvesAliases = true
        return panel
    }

    private static func saveFolderAccess(_ urls: [URL], replacing: Bool) {
        var selected = replacing ? [] : resolveFolderBookmarks().urls
        selected.append(contentsOf: urls)
        let unique = Dictionary(selected.map { ($0.standardizedFileURL.path, $0.standardizedFileURL) }, uniquingKeysWith: { first, _ in first }).map(\.value)
        let bookmarks = unique.compactMap {
            try? $0.bookmarkData(options: .withSecurityScope,
                                 includingResourceValuesForKeys: nil,
                                 relativeTo: nil)
        }
        clearActiveFolderAccess()
        UserDefaults.standard.set(bookmarks, forKey: folderBookmarksKey)
        activateFolderAccess(unique)
    }

    private static func clearFolderAccess() {
        clearActiveFolderAccess()
        UserDefaults.standard.removeObject(forKey: folderBookmarksKey)
    }

    private static func resolveFolderBookmarks() -> (urls: [URL], totalCount: Int) {
        let bookmarks = UserDefaults.standard.array(forKey: folderBookmarksKey) as? [Data] ?? []
        var resolved: [URL] = []
        var refreshed: [Data] = []
        var changed = false

        for bookmark in bookmarks {
            var stale = false
            guard let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) else {
                refreshed.append(bookmark)
                continue
            }

            resolved.append(url)
            if stale,
               let replacement = try? url.bookmarkData(options: .withSecurityScope,
                                                       includingResourceValuesForKeys: nil,
                                                       relativeTo: nil) {
                refreshed.append(replacement)
                changed = true
            } else {
                refreshed.append(bookmark)
            }
        }

        if changed {
            UserDefaults.standard.set(refreshed, forKey: folderBookmarksKey)
        }
        return (resolved, bookmarks.count)
    }

    private static func activateFolderAccess(_ urls: [URL]) {
        let activePaths = Set(activeFolderURLs.map(\.standardizedFileURL.path))
        let newPaths = Set(urls.map(\.standardizedFileURL.path))

        for url in activeFolderURLs where !newPaths.contains(url.standardizedFileURL.path) {
            url.stopAccessingSecurityScopedResource()
        }

        for url in urls where !activePaths.contains(url.standardizedFileURL.path) {
            _ = url.startAccessingSecurityScopedResource()
        }
        activeFolderURLs = urls
    }

    private static func clearActiveFolderAccess() {
        for url in activeFolderURLs {
            url.stopAccessingSecurityScopedResource()
        }
        activeFolderURLs.removeAll()
    }

    private static func folderDisplayName(_ url: URL) -> String {
        if url.standardizedFileURL == FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL {
            return "Home"
        }
        return url.lastPathComponent
    }

    private static func present(_ alert: NSAlert, attachedTo parentWindow: NSWindow?,
                                completion: @escaping (NSApplication.ModalResponse) -> Void) {
        if let parentWindow {
            alert.beginSheetModal(for: parentWindow, completionHandler: completion)
        } else {
            completion(alert.runModal())
        }
    }

    private static func present(_ panel: NSOpenPanel, attachedTo parentWindow: NSWindow?,
                                completion: @escaping (NSApplication.ModalResponse) -> Void) {
        NSApp.activate(ignoringOtherApps: true)
        if let parentWindow {
            parentWindow.orderFrontRegardless()
            parentWindow.makeKey()
            panel.beginSheetModal(for: parentWindow, completionHandler: completion)
        } else {
            panel.begin(completionHandler: completion)
        }
    }

    // MARK: - Finder extension

    nonisolated static func finderExtensionState() -> PermissionState {
#if MAC_APP_STORE
        FIFinderSyncController.isExtensionEnabled ? .granted : .denied
#else
        // FinderSync's convenience property can stay false for an ad-hoc app
        // launched outside /Applications even after PluginKit has enabled its
        // embedded extension. PluginKit is the source Finder itself uses for
        // local builds, so read the enabled marker from that registry too.
        let registry = run("/usr/bin/pluginkit", [
            "-m", "-A", "-D", "-v", "-i", extensionIdentifier,
        ])
        let registeredAsEnabled = registry.split(separator: "\n").contains { line in
            let value = line.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.hasPrefix("+") && value.contains(extensionIdentifier)
        }
        return registeredAsEnabled || FIFinderSyncController.isExtensionEnabled
            ? .granted : .denied
#endif
    }

    /// Registers and enables the extension without sending the user to System
    /// Settings. `pluginkit` is a user-level tool - no admin rights involved.
    nonisolated static func enableFinderExtension() -> PermissionState {
#if MAC_APP_STORE
        // Sandboxed Mac App Store builds must use Apple's management UI. The
        // caller presents that UI when this state still needs attention.
        return finderExtensionState()
#else
        let appexPath = Bundle.main.bundleURL
            .appendingPathComponent("Contents/PlugIns/AirFliqFinder.appex")
            .path
        _ = run("/usr/bin/pluginkit", ["-a", appexPath])
        _ = run("/usr/bin/pluginkit", ["-e", "use", "-i", extensionIdentifier])

        // PluginKit updates its registry asynchronously. A single immediate
        // query can report the old value and make setup appear to reset.
        for attempt in 0..<8 {
            let state = finderExtensionState()
            if state == .granted { return state }
            if attempt < 7 {
                Thread.sleep(forTimeInterval: 0.16)
            }
        }
        return finderExtensionState()
#endif
    }

    static func openExtensionSettings() {
        FIFinderSyncController.showExtensionManagementInterface()
    }

    static func openAutomationSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!
        NSWorkspace.shared.open(url)
    }

    static func openFilesSettings() {
        let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders")!
        NSWorkspace.shared.open(url)
    }

    // MARK: - Process helper

#if !MAC_APP_STORE
    @discardableResult
    nonisolated private static func run(_ launchPath: String, _ arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            NSLog("[AirFliq] failed to run \(launchPath): \(error)")
            return ""
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }
#endif
}
