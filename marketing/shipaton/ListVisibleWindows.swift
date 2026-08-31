import CoreGraphics
import Foundation

let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
    as? [[String: Any]] ?? []

for item in windows {
    let owner = item[kCGWindowOwnerName as String] as? String ?? ""
    let name = item[kCGWindowName as String] as? String ?? ""
    let number = item[kCGWindowNumber as String] as? Int ?? 0
    let layer = item[kCGWindowLayer as String] as? Int ?? 0
    let bounds = item[kCGWindowBounds as String] as? [String: Any] ?? [:]
    guard layer == 0, !owner.isEmpty else { continue }
    print("\(number)\t\(owner)\t\(name)\t\(bounds)")
}
