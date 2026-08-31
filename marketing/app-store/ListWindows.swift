import CoreGraphics
import Foundation

let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
    as? [[String: Any]] ?? []

let rows = windows.compactMap { item -> [String: Any]? in
    guard
        let owner = item[kCGWindowOwnerName as String] as? String,
        owner == "AirFliq",
        let number = item[kCGWindowNumber as String] as? Int
    else { return nil }

    return [
        "id": number,
        "owner": owner,
        "name": item[kCGWindowName as String] as? String ?? "",
        "layer": item[kCGWindowLayer as String] as? Int ?? 0,
        "bounds": item[kCGWindowBounds as String] as? [String: Any] ?? [:]
    ]
}

let data = try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys])
FileHandle.standardOutput.write(data)
FileHandle.standardOutput.write(Data("\n".utf8))
