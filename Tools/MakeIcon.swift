import Cocoa

// Renders AppIcon.iconset from the same code the app draws its icon with.
@main
struct MakeIcon {
    static let variants: [(name: String, size: Int)] = [
        ("icon_16x16", 16), ("icon_16x16@2x", 32),
        ("icon_32x32", 32), ("icon_32x32@2x", 64),
        ("icon_128x128", 128), ("icon_128x128@2x", 256),
        ("icon_256x256", 256), ("icon_256x256@2x", 512),
        ("icon_512x512", 512), ("icon_512x512@2x", 1024),
    ]

    static func main() {
        let outputDir = CommandLine.arguments.count > 1
            ? CommandLine.arguments[1]
            : "./AppIcon.iconset"
        try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

        for variant in variants {
            let image = AirDropIcon.appIcon(size: CGFloat(variant.size), inset: 0.09)
            guard let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { continue }
            let url = URL(fileURLWithPath: outputDir).appendingPathComponent("\(variant.name).png")
            try? png.write(to: url)
        }
    }
}
