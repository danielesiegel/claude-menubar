#!/usr/bin/swift
import AppKit
import Foundation

// Claude orange color
let claudeOrange = NSColor(red: 217/255, green: 119/255, blue: 87/255, alpha: 1.0)
let white = NSColor.white

// Icon sizes for macOS
let sizes: [(size: Int, scale: Int, name: String)] = [
    (16, 1, "icon_16x16.png"),
    (16, 2, "icon_16x16@2x.png"),
    (32, 1, "icon_32x32.png"),
    (32, 2, "icon_32x32@2x.png"),
    (128, 1, "icon_128x128.png"),
    (128, 2, "icon_128x128@2x.png"),
    (256, 1, "icon_256x256.png"),
    (256, 2, "icon_256x256@2x.png"),
    (512, 1, "icon_512x512.png"),
    (512, 2, "icon_512x512@2x.png"),
]

func createIcon(size: Int, scale: Int) -> NSImage {
    let pixelSize = size * scale
    let image = NSImage(size: NSSize(width: pixelSize, height: pixelSize))

    image.lockFocus()

    // Draw rounded rectangle background
    let rect = NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize)
    let cornerRadius = CGFloat(pixelSize) * 0.22 // macOS style corners
    let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
    claudeOrange.setFill()
    path.fill()

    // Draw the brain SF Symbol
    if let symbolImage = NSImage(systemSymbolName: "brain.head.profile", accessibilityDescription: nil) {
        let config = NSImage.SymbolConfiguration(pointSize: CGFloat(pixelSize) * 0.55, weight: .medium)
        let configuredImage = symbolImage.withSymbolConfiguration(config)!

        // Create a tinted version
        let tintedImage = NSImage(size: configuredImage.size)
        tintedImage.lockFocus()
        white.set()
        let imageRect = NSRect(origin: .zero, size: configuredImage.size)
        configuredImage.draw(in: imageRect)
        imageRect.fill(using: .sourceAtop)
        tintedImage.unlockFocus()

        // Center the symbol
        let symbolSize = tintedImage.size
        let x = (CGFloat(pixelSize) - symbolSize.width) / 2
        let y = (CGFloat(pixelSize) - symbolSize.height) / 2

        tintedImage.draw(in: NSRect(x: x, y: y, width: symbolSize.width, height: symbolSize.height),
                         from: NSRect(origin: .zero, size: symbolSize),
                         operation: .sourceOver,
                         fraction: 1.0)
    }

    image.unlockFocus()
    return image
}

func saveImage(_ image: NSImage, to path: String) {
    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:]) else {
        print("Failed to create PNG for \(path)")
        return
    }

    do {
        try pngData.write(to: URL(fileURLWithPath: path))
        print("Created: \(path)")
    } catch {
        print("Error saving \(path): \(error)")
    }
}

// Main
let scriptPath = CommandLine.arguments[0]
let scriptDir = (scriptPath as NSString).deletingLastPathComponent
let baseDir = scriptDir.isEmpty ? "." : scriptDir

let iconsetDir = "\(baseDir)/ClaudeMenuBar/ClaudeMenuBar/Assets.xcassets/AppIcon.appiconset"

// Create directory if needed
try? FileManager.default.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

// Generate all icon sizes
for (size, scale, name) in sizes {
    let image = createIcon(size: size, scale: scale)
    let path = "\(iconsetDir)/\(name)"
    saveImage(image, to: path)
}

// Also create 1024x1024 for the iconset
let largeIcon = createIcon(size: 512, scale: 2)
saveImage(largeIcon, to: "\(iconsetDir)/icon_1024x1024.png")

// Create iconset for .icns generation
let iconsetTmp = "/tmp/ClaudeMenuBar.iconset"
try? FileManager.default.removeItem(atPath: iconsetTmp)
try? FileManager.default.createDirectory(atPath: iconsetTmp, withIntermediateDirectories: true)

// Copy with correct names for iconutil
let iconutilSizes: [(size: Int, scale: Int, name: String)] = [
    (16, 1, "icon_16x16.png"),
    (16, 2, "icon_16x16@2x.png"),
    (32, 1, "icon_32x32.png"),
    (32, 2, "icon_32x32@2x.png"),
    (128, 1, "icon_128x128.png"),
    (128, 2, "icon_128x128@2x.png"),
    (256, 1, "icon_256x256.png"),
    (256, 2, "icon_256x256@2x.png"),
    (512, 1, "icon_512x512.png"),
    (512, 2, "icon_512x512@2x.png"),
]

for (size, scale, name) in iconutilSizes {
    let image = createIcon(size: size, scale: scale)
    saveImage(image, to: "\(iconsetTmp)/\(name)")
}

// Generate .icns
let icnsPath = "\(baseDir)/ClaudeMenuBar.icns"
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconsetTmp, "-o", icnsPath]
try? task.run()
task.waitUntilExit()

if task.terminationStatus == 0 {
    print("Created: \(icnsPath)")
} else {
    print("Failed to create .icns")
}

// Cleanup
try? FileManager.default.removeItem(atPath: iconsetTmp)

print("\nDone! Icon files generated.")
