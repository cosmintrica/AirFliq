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
    #if !MAC_APP_STORE
    private static let hasRequestedAutomationKey =
        "airfliq.onboarding.didRequestFinderAutomation.v1"
    #endif
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

    #if !MAC_APP_STORE
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

    #endif

    /// The original setup has one selection step. In the store build it is
    /// an explanation of explicit file selection, not an Automation grant.
    nonisolated static func selectionSetupState() -> PermissionState {
#if MAC_APP_STORE
        // The system picker is usable immediately; reading an explanation is
        // not a prerequisite or a permission grant.
        .granted
#else
        automationState()
#endif
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
                             completion: @escaping (PermissionState, Bool) -> Void) {
        if selectedFolderCount > 0 {
            presentFolderManagement(attachedTo: parentWindow, completion: completion)
        } else {
            presentFolderPicker(attachedTo: parentWindow, completion: completion)
        }
    }

    private static var accessRequests: [FolderAccessRequest] = []
    private static var accessPanel: NSOpenPanel?
    private static var accessRequestIsRunning = false

    /// Reactivate persisted grants before testing a file, including sends that
    /// arrive before onboarding has ever been opened in this process.
    static func restoreFolderAccess() {
        activateFolderAccess(resolveFolderBookmarks().urls)
    }

    static func authorizedFolders(for urls: [URL]) -> [URL] {
        resolveFolderBookmarks().urls.filter { folder in
            urls.contains { FolderAccessRequest.contains(folder, item: $0) }
        }
    }

    static func requestAccess(to urls: [URL], attachedTo parentWindow: NSWindow?,
                              forceAuthorization: Bool = false,
                              completion: @escaping (Bool) -> Void) {
        restoreFolderAccess()
        let request = FolderAccessRequest(
            urls: urls, forceAuthorization: forceAuthorization,
            isReadable: { FileManager.default.isReadableFile(atPath: $0.path) },
            fileExists: { FileManager.default.fileExists(atPath: $0.path) },
            reportUnavailable: { url in
                Toast.show("That item is no longer available",
                           subtitle: "\(url.lastPathComponent) may have been moved or deleted.")
            },
            chooseFolder: { folder, _, retry, selected in
                let panel = NSOpenPanel()
                accessPanel = panel
                panel.title = "Allow AirFliq to send these files"
                let name = folderDisplayName(folder)
                panel.message = retry
                    ? "Access is still missing. Choose \(name), or a folder containing it, to continue your transfer."
                    : "Allow access to \(name) to continue this transfer. AirFliq will remember the folder and resume automatically."
                panel.prompt = "Allow & Continue"
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                panel.allowsMultipleSelection = false
                panel.canCreateDirectories = false
                panel.resolvesAliases = true
                panel.directoryURL = folder
                NSApp.activate(ignoringOtherApps: true)
                // A standalone asynchronous panel avoids stacking a new sheet
                // onto an alert or share sheet that has not finished closing.
                panel.begin { response in
                    accessPanel = nil
                    let url = response == .OK ? panel.url : nil
                    DispatchQueue.main.async { selected(url) }
                }
            },
            rememberFolder: { folder in
                if !saveFolderAccess([folder], replacing: false) {
                    Toast.show("Folder access could not be saved",
                               subtitle: "This transfer can continue. You may need to allow the folder again next time.")
                }
            },
            completion: { granted in
                accessRequests.removeFirst()
                accessRequestIsRunning = false
                completion(granted)
                // Schedule after completion so another request enqueued by a
                // resumed send is processed in the same single-file queue.
                DispatchQueue.main.async { startNextAccessRequest() }
            })
        accessRequests.append(request)
        DispatchQueue.main.async { startNextAccessRequest() }
    }

    private static func startNextAccessRequest() {
        guard !accessRequestIsRunning, let request = accessRequests.first else { return }
        accessRequestIsRunning = true
        request.start()
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
                presentFolderPicker(attachedTo: parentWindow) { _, _ in }
            } else if response == .alertSecondButtonReturn {
                openFilesSettings()
            }
        }
    }

    private static func presentFolderManagement(
        attachedTo parentWindow: NSWindow?,
        completion: @escaping (PermissionState, Bool) -> Void
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
                completion(.unknown, false)
            default:
                completion(filesState(), false)
            }
        }
    }

    private static func presentFolderPicker(
        attachedTo parentWindow: NSWindow?,
        completion: @escaping (PermissionState, Bool) -> Void
    ) {
        let panel = warmedFolderPanel ?? makeFolderPanel()
        warmedFolderPanel = panel

        let handler: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK else {
                completion(filesState(), false)
                return
            }
            saveFolderAccess(panel.urls, replacing: true)
            completion(filesState(), true)
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

    @discardableResult
    private static func saveFolderAccess(_ urls: [URL], replacing: Bool) -> Bool {
        var bookmarks = replacing ? [] : (UserDefaults.standard.array(forKey: folderBookmarksKey) as? [Data] ?? [])
        var savedAll = true
        for url in urls {
            do {
                let bookmark = try url.bookmarkData(
                    options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                    includingResourceValuesForKeys: nil, relativeTo: nil)
                // Keep existing grants, even temporarily unresolvable ones.
                bookmarks.removeAll { data in
                    var stale = false
                    let saved = try? URL(resolvingBookmarkData: data,
                                         options: [.withSecurityScope, .withoutUI],
                                         relativeTo: nil, bookmarkDataIsStale: &stale)
                    return saved?.standardizedFileURL == url.standardizedFileURL
                }
                bookmarks.append(bookmark)
            } catch {
                savedAll = false
            }
        }
        UserDefaults.standard.set(bookmarks, forKey: folderBookmarksKey)
        let resolved = resolveFolderBookmarks().urls
        // Preserve the live panel grant even if persistence fails, so the
        // current transfer still has access. Reconcile without closing grants
        // that another in-flight transfer is currently using.
        let accessible = Dictionary((resolved + urls).map {
            ($0.standardizedFileURL.path, $0)
        }, uniquingKeysWith: { first, _ in first }).map(\.value)
        activateFolderAccess(accessible)
        return savedAll
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
               let replacement = try? url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
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

    /// Last known Finder extension state, refreshed off the main thread. The
    /// menu uses it to offer the right-click route without blocking.
    private(set) static var cachedFinderExtensionEnabled: Bool?

    static func refreshFinderExtensionCache() {
        Task {
            let state = await Task.detached(priority: .utility) {
                finderExtensionState()
            }.value
            cachedFinderExtensionEnabled = state == .granted
        }
    }

    /// Opens System Settings at the Finder extension switch. On macOS 15.2
    /// and later Apple's API presents the File Providers sheet with AirFliq's
    /// switch directly (verified on macOS 27). macOS 15.0 and 15.1 lacked that
    /// sheet, so they open Login Items & Extensions instead.
    static func openExtensionSettings() {
        if #available(macOS 15.2, *) {
            FIFinderSyncController.showExtensionManagementInterface()
            return
        }
        if #available(macOS 15.0, *),
           let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"),
           NSWorkspace.shared.open(url) {
            return
        }
        FIFinderSyncController.showExtensionManagementInterface()
    }

    #if !MAC_APP_STORE
    static func openAutomationSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!
        NSWorkspace.shared.open(url)
    }

    #endif

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
