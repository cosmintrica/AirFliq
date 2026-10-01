import Cocoa
import FinderSync

@objc(FinderSyncExt)
final class FinderSyncExt: FIFinderSync {

    override init() {
        super.init()
        // Observe the whole volume so the item shows up wherever you right-click.
        FIFinderSyncController.default().directoryURLs = [
            URL(fileURLWithPath: "/"),
            URL(fileURLWithPath: "/Volumes"),
        ]
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        let menu = NSMenu(title: "")
        guard menuKind == .contextualMenuForItems else { return menu }

        let count = FIFinderSyncController.default().selectedItemURLs()?.count ?? 0
        guard count > 0 else { return menu }

        let title = count == 1 ? "Send with AirFliq" : "Send \(count) items with AirFliq"
        let item = NSMenuItem(title: title, action: #selector(airDropSelection(_:)), keyEquivalent: "")
        item.target = self
        item.image = AirDropIcon.appIcon(size: 16)
        item.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold),
            .foregroundColor: NSColor.controlAccentColor,
        ])
        menu.addItem(item)
        return menu
    }

    @objc private func airDropSelection(_ sender: AnyObject?) {
        guard let urls = FIFinderSyncController.default().selectedItemURLs(), !urls.isEmpty else { return }
        guard let request = FinderSendRequest.encode(urls) else { return }

        // Resolve the host app from this extension bundle.
        let appURL = Bundle.main.bundleURL
            .deletingLastPathComponent()   // PlugIns
            .deletingLastPathComponent()   // Contents
            .deletingLastPathComponent()   // AirFliq.app

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open([request], withApplicationAt: appURL, configuration: configuration) { _, error in
            if let error {
                NSLog("[AirFliq] could not launch the host app: \(error)")
            }
        }
    }
}
