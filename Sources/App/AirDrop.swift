import Cocoa

@MainActor
enum AirDrop {
    private static var sessions: [SharingSession] = []

    static func send(_ urls: [URL], allowPermissionPrompt: Bool = true,
                     hasResolvedAccess: Bool = false) {
        let unique = Dictionary(urls.filter(\.isFileURL).map { ($0.standardizedFileURL.path, $0.standardizedFileURL) }, uniquingKeysWith: { a, _ in a }).map(\.value)
        guard !unique.isEmpty else { Toast.show("Nothing to send", subtitle: "Select files in Finder first."); return }

        if !hasResolvedAccess {
            Monetization.shared.resolveSendAccess { canSend in
                if canSend {
                    send(unique, allowPermissionPrompt: allowPermissionPrompt,
                         hasResolvedAccess: true)
                } else {
                    PaywallWindowController.shared.present()
                }
            }
            return
        }

        let blocked = unique.filter { FileManager.default.fileExists(atPath: $0.path) && !FileManager.default.isReadableFile(atPath: $0.path) }
        if allowPermissionPrompt, !blocked.isEmpty {
            Permissions.requestAccess(to: blocked, attachedTo: NSApp.keyWindow) { granted in
                if granted {
                    send(unique, allowPermissionPrompt: false, hasResolvedAccess: true)
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
        let session = SharingSession(service: service, items: unique) { finished in sessions.removeAll { $0 === finished } }
        sessions.append(session)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { session.start() }
    }

    static func sendFinderSelection() {
        guard Permissions.automationState() != .denied else { Toast.show("Finder access is off", subtitle: "Open Setup & Permissions and grant Finder access."); return }
        let urls = FinderSelection.current()
        guard !urls.isEmpty else { Toast.show("Nothing selected", subtitle: "Select one or more items in Finder first."); return }
        send(urls)
    }
}

private final class SharingSession: NSObject, NSSharingServiceDelegate {
    let service: NSSharingService
    let items: [URL]
    let finish: (SharingSession) -> Void
    init(service: NSSharingService, items: [URL], finish: @escaping (SharingSession) -> Void) { self.service = service; self.items = items; self.finish = finish }
    func start() { service.delegate = self; service.perform(withItems: items) }
    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        // sendViaAirDrop can finish handing the items to its system panel even
        // when that panel is dismissed without a device being chosen. A real
        // AirDrop has a recipient; an empty recipient list is a cancellation,
        // not a billable successful send.
        guard sharingService.recipients?.isEmpty == false else {
            finish(self)
            return
        }
        NotificationCenter.default.post(name: .airFliqSendSucceeded, object: nil)
        let access = Monetization.shared
        Toast.show("Sent with AirFliq",
                   subtitle: access.isPro
                       ? "Lifetime Pro is active."
                       : "Full trial active. \(access.trialStatusText).")
        finish(self)
    }
    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) {
        if (error as NSError).code != NSUserCancelledError { Toast.show("Send did not finish", subtitle: error.localizedDescription) }
        finish(self)
    }
}
