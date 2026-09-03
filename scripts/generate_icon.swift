import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let svgURL = root.appendingPathComponent("assets/LiveflowIcon.svg")
let png1024URL = root.appendingPathComponent("assets/LiveflowIcon-1024.png")
let iconsetDir = root.appendingPathComponent("native/LiveflowIcon.iconset")
let icnsURL = root.appendingPathComponent("native/LiveflowIcon.icns")

guard let svgImage = NSImage(contentsOf: svgURL) else {
    print("Error: Failed to load SVG from \(svgURL.path)")
    exit(1)
}

try? FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

func renderImage(size: Int) -> Data? {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )
    guard let rep = rep else { return nil }
    rep.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current = context
    context?.imageInterpolation = .high

    svgImage.draw(
        in: NSRect(x: 0, y: 0, width: size, height: size),
        from: NSRect(origin: .zero, size: svgImage.size),
        operation: .copy,
        fraction: 1.0
    )

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

// 1. Save 1024 PNG
if let data1024 = renderImage(size: 1024) {
    try? data1024.write(to: png1024URL)
    print("Saved 1024x1024 master PNG to \(png1024URL.path)")
}

// 2. Generate iconset
let sizes: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (name, px) in sizes {
    let destURL = iconsetDir.appendingPathComponent(name)
    if let data = renderImage(size: px) {
        try? data.write(to: destURL)
    }
}
print("Generated all iconset sizes in \(iconsetDir.path)")

// 3. Run iconutil
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetDir.path, "-o", icnsURL.path]
try process.run()
process.waitUntilExit()

if process.terminationStatus == 0 {
    print("Successfully generated ICNS at: \(icnsURL.path)")
} else {
    print("Error: iconutil exited with status \(process.terminationStatus)")
    exit(2)
}
