#!/usr/bin/env swift
import AppKit

let outPath = CommandLine.arguments.dropFirst().first ?? "icon.png"

let size = CGSize(width: 1024, height: 1024)
let image = NSImage(size: size, flipped: false) { rect in
    // Rounded gradient background — Apple-style "squircle" with corner radius ~22% of side.
    let bgPath = NSBezierPath(roundedRect: rect, xRadius: 230, yRadius: 230)
    NSGradient(colors: [
        NSColor(srgbRed: 0.30, green: 0.58, blue: 1.00, alpha: 1),
        NSColor(srgbRed: 0.08, green: 0.20, blue: 0.55, alpha: 1)
    ])!.draw(in: bgPath, angle: -90)

    // Subtle inner highlight for a glassy feel.
    let highlight = NSBezierPath(roundedRect: rect.insetBy(dx: 28, dy: 28),
                                 xRadius: 205, yRadius: 205)
    NSColor.white.withAlphaComponent(0.06).setFill()
    highlight.fill()

    // White stopwatch glyph, centered, ~60% of the canvas.
    let config = NSImage.SymbolConfiguration(pointSize: 620, weight: .regular)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    if let symbol = NSImage(systemSymbolName: "stopwatch.fill",
                            accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let s = symbol.size
        let origin = NSPoint(x: (rect.width  - s.width)  / 2,
                             y: (rect.height - s.height) / 2 - 6) // nudge up slightly
        symbol.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1)
    }

    return true
}

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("png encoding failed\n".utf8))
    exit(1)
}

try png.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath)")
