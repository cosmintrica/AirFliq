import Cocoa

@MainActor
enum AirDrop {
    private static var sessions: [SharingSession] = []
#if MAC_APP_STORE
    static let readyInstructions = "Use your shortcut to choose files, or send a Finder selection with right-click or drag-and-drop."
    static let sendActionTitle = "Choose files to send…"
    static let sendActionDetail = "Choose files, then open AirDrop"
#else
    static let readyInstructions = "Select a file. Use your shortcut, right-click, or simply drag. The native AirDrop panel appears instantly."
    static let sendActionTitle = "Send Finder selection"
    static let sendActionDetail = "Open native AirDrop now"
#endif

    static func send(_ urls: [URL], allowPermissionPrompt: Bool = true,
                     hasResolvedAccess: Bool = false) {
        send(urls, allowPermissionPrompt: allowPermissionPrompt,
             hasResolvedAccess: hasResolvedAccess,
             accessLease: SecurityScopedAccessLease(urls: urls))
    }

    private static func send(_ urls: [URL], allowPermissionPrompt: Bool,
                             hasResolvedAccess: Bool,
                             accessLease: SecurityScopedAccessLease) {
        let unique = Dictionary(urls.filter(\.isFileURL).map { ($0.standardizedFileURL.path, $0) }, uniquingKeysWith: { a, _ in a }).map(\.value)
        guard !unique.isEmpty else { Toast.show("Nothing to send", subtitle: "Select files in Finder first."); return }

        if !hasResolvedAccess {
            Monetization.shared.resolveSendAccess { canSend in
                if canSend {
                    send(unique, allowPermissionPrompt: allowPermissionPrompt,
                         hasResolvedAccess: true, accessLease: accessLease)
                } else {
                    PaywallWindowController.shared.present()
                }
            }
            return
        }

        // In the App Sandbox, FileManager can report an item outside the
        // user's selected folders as both unreadable and nonexistent. Treat
        // unreadable URLs as an access request first, then distinguish a truly
        // missing item after the user has had a chance to grant its folder.
        Permissions.restoreFolderAccess()
        accessLease.retainAccess(to: Permissions.authorizedFolders(for: unique))
        let blocked = unique.filter {
            !FileManager.default.isReadableFile(atPath: $0.path)
        }
        if allowPermissionPrompt, !blocked.isEmpty {
            Permissions.requestAccess(to: blocked, attachedTo: NSApp.keyWindow) { granted in
                if granted {
                    send(unique, allowPermissionPrompt: false,
                         hasResolvedAccess: true, accessLease: accessLease)
                }
            }
            return
        }
        if let missing = unique.first(where: { !FileManager.default.fileExists(atPath: $0.path) }) {
            Toast.show("That item is no longer available", subtitle: "\(missing.lastPathComponent) may have been moved or deleted."); return
        }
        guard blocked.isEmpty else { Toast.show("Folder access is still missing", subtitle: "Choose the folder that contains this item."); return }
        for url in unique {
            if let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]), values.isUbiquitousItem == true, values.ubiquitousItemDownloadingStatus != .current {
                try? FileManager.default.startDownloadingUbiquitousItem(at: url)
                Toast.show("Downloading \(url.lastPathComponent) from iCloud", subtitle: "Try again when the download is complete."); return
            }
        }
        guard let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: unique) else {
            Toast.show("These items cannot be sent", subtitle: "Try Finder's Share menu instead."); return
        }
        let session = SharingSession(service: service, items: unique,
                                     accessLease: accessLease,
                                     recoverAccess: { error in
            guard allowPermissionPrompt, FileAccessFailure.isPermissionError(error) else { return false }
            Permissions.requestAccess(to: unique, attachedTo: NSApp.keyWindow,
                                      forceAuthorization: true) { granted in
                guard granted else { return }
                send(unique, allowPermissionPrompt: false,
                     hasResolvedAccess: true, accessLease: accessLease)
            }
            return true
        }) { finished in
            sessions.removeAll { $0 === finished }
        }
        sessions.append(session)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { session.start() }
    }

    /// Every global/menu invocation in the sandbox starts with an explicit
    /// user selection. Retain a single panel so repeated shortcuts refocus it.
#if MAC_APP_STORE
    private static var filePicker: NSOpenPanel?
#endif

    static func chooseAndSend() {
#if MAC_APP_STORE
        if let filePicker {
            NSApp.activate(ignoringOtherApps: true)
            filePicker.makeKeyAndOrderFront(nil)
            return
        }
        let panel = NSOpenPanel()
        panel.title = "Send with AirFliq"
        panel.message = "Choose files or folders to share with AirDrop."
        panel.prompt = "Send with AirDrop"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        filePicker = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { response in
            filePicker = nil
            guard response == .OK else { return }
            // Acquire security scope inside the completion handler, before
            // asynchronous purchase checks or the native AirDrop handoff.
            send(panel.urls)
        }
#else
        guard Permissions.automationState() != .denied else { Toast.show("Finder access is off", subtitle: "Open Setup & Permissions and grant Finder access."); return }
        let urls = FinderSelection.current()
        guard !urls.isEmpty else { Toast.show("Nothing selected", subtitle: "Select one or more items in Finder first."); return }
        send(urls)
#endif
    }
}

/// Keeps drag-and-drop security scope alive until the native share service has
/// either completed or been cancelled. Creating it synchronously is important:
/// the transient sandbox grant can disappear as soon as performDragOperation
/// returns.
private final class SecurityScopedAccessLease {
    private var accessedURLs: [URL] = []

    init(urls: [URL]) {
        retainAccess(to: urls)
    }

    func retainAccess(to urls: [URL]) {
        for url in urls where !accessedURLs.contains(where: {
            $0.standardizedFileURL == url.standardizedFileURL
        }) {
            if url.startAccessingSecurityScopedResource() { accessedURLs.append(url) }
        }
    }

    deinit {
        for url in accessedURLs {
            url.stopAccessingSecurityScopedResource()
        }
    }
}

private final class SharingSession: NSObject, NSSharingServiceDelegate {
    let service: NSSharingService
    let items: [URL]
    let accessLease: SecurityScopedAccessLease
    let recoverAccess: (Error) -> Bool
    let finish: (SharingSession) -> Void
    init(service: NSSharingService, items: [URL],
         accessLease: SecurityScopedAccessLease,
         recoverAccess: @escaping (Error) -> Bool,
         finish: @escaping (SharingSession) -> Void) {
        self.service = service
        self.items = items
        self.accessLease = accessLease
        self.recoverAccess = recoverAccess
        self.finish = finish
    }
    func start() { service.delegate = self; service.perform(withItems: items) }
    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        // AppKit reports cancellation through didFailToShareItems with
        // NSUserCancelledError. `recipients` is an input used to preconfigure
        // some sharing services, not the result of the AirDrop picker, so it
        // must not gate successful feedback here.
        NotificationCenter.default.post(name: .airFliqSendSucceeded, object: nil)
        let access = Monetization.shared
        Toast.show("Sent with AirFliq",
                   subtitle: access.isPro
                       ? "Lifetime Pro is active."
                       : "Full trial active. \(access.trialStatusText).")
        finish(self)
    }
    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) {
        if recoverAccess(error) {
            finish(self)
            return
        }
        if (error as NSError).code != NSUserCancelledError { Toast.show("Send did not finish", subtitle: error.localizedDescription) }
        finish(self)
    }
}
