import AppKit
import Foundation

// Generates raster fallbacks for pre-iOS 13 RetroLive targets. These images are
// intended only for the Apple-platform apps in this repository.
let icons: [(fileName: String, symbolName: String)] = [
    ("RLVFlashAuto", "bolt.badge.a.fill"),
    ("RLVFlashOn", "bolt.fill"),
    ("RLVFlashOff", "bolt.slash.fill"),
    ("RLVSwitchCamera", "arrow.triangle.2.circlepath"),
    ("RLVTransfer", "square.and.arrow.up"),
    ("RLVLiveEffect", "livephoto")
]

let outputDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("legacy-camera/RetroLiveCamera/Resources/InterfaceIcons", isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

for icon in icons {
    for scale in 1...3 {
        let logicalSize: CGFloat = 24
        let pixelSize = logicalSize * CGFloat(scale)
        // Leave a small optical margin so wide/tall symbols are not clipped by
        // the fixed 24-point fallback canvas.
        let pointConfiguration = NSImage.SymbolConfiguration(pointSize: 18 * CGFloat(scale), weight: .semibold)
        let colorConfiguration = NSImage.SymbolConfiguration(paletteColors: [.white, .white, .white])
        guard let base = NSImage(systemSymbolName: icon.symbolName, accessibilityDescription: nil),
              let symbol = base.withSymbolConfiguration(pointConfiguration.applying(colorConfiguration)) else {
            fatalError("SF Symbol is unavailable: \(icon.symbolName)")
        }

        let canvas = NSImage(size: NSSize(width: pixelSize, height: pixelSize), flipped: false) { rect in
            let symbolSize = symbol.size
            let drawRect = NSRect(
                x: rect.midX - symbolSize.width / 2,
                y: rect.midY - symbolSize.height / 2,
                width: symbolSize.width,
                height: symbolSize.height
            )
            symbol.draw(in: drawRect)
            return true
        }
        guard let tiff = canvas.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            fatalError("Could not render \(icon.symbolName)")
        }
        let suffix = scale == 1 ? "" : "@\(scale)x"
        try png.write(to: outputDirectory.appendingPathComponent("\(icon.fileName)\(suffix).png"))
    }
}
