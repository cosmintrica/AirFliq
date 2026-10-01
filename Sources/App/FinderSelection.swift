#if !MAC_APP_STORE
import Foundation

enum FinderSelection {

    /// Reads the current Finder selection over Apple Events.
    static func current() -> [URL] {
        let source = """
        tell application "Finder"
            set theSelection to selection as alias list
            set paths to {}
            repeat with anItem in theSelection
                set end of paths to POSIX path of (anItem as text)
            end repeat
            return paths
        end tell
        """

        guard let script = NSAppleScript(source: source) else { return [] }

        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)

        if let error {
            NSLog("[AirFliq] Apple Event error: \(error)")
            return []
        }

        let count = result.numberOfItems
        guard count > 0 else { return [] }

        return (1...count).compactMap { index in
            guard let path = result.atIndex(index)?.stringValue, !path.isEmpty else { return nil }
            return URL(fileURLWithPath: path)
        }
    }
}

#endif
