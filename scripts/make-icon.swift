// Renders the 1024×1024 app icon master from full-bleed artwork.
//
//   swift scripts/make-icon.swift <artwork.png> <output.png>
//
// The artwork is clipped to the macOS icon shape here, not by the image model, so the
// shape, grid and shadow stay exact no matter how the artwork was produced.
import AppKit

enum IconGrid {
    static let canvas: CGFloat = 1024
    /// macOS icon body: 824 pt centered on the 1024 pt canvas.
    static let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    static let cornerRadius: CGFloat = 185
}

enum IconError: Error, CustomStringConvertible {
    case usage
    case unreadableArtwork(String)
    case encodingFailed

    var description: String {
        switch self {
        case .usage: "usage: swift make-icon.swift <artwork.png> <output.png>"
        case .unreadableArtwork(let path): "Could not read artwork at \(path)"
        case .encodingFailed: "Could not encode the icon as PNG"
        }
    }
}

func renderIcon(artwork: NSImage) -> NSImage {
    NSImage(size: NSSize(width: IconGrid.canvas, height: IconGrid.canvas), flipped: false) { _ in
        let shape = NSBezierPath(roundedRect: IconGrid.body, xRadius: IconGrid.cornerRadius, yRadius: IconGrid.cornerRadius)

        // Drop shadow, drawn under the body.
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = .black.withAlphaComponent(0.28)
        shadow.shadowBlurRadius = 22
        shadow.shadowOffset = NSSize(width: 0, height: -9)
        shadow.set()
        NSColor.black.setFill()
        shape.fill()
        NSGraphicsContext.restoreGraphicsState()

        // Artwork, aspect-filled into the body and clipped to the shape.
        NSGraphicsContext.saveGraphicsState()
        shape.addClip()
        artwork.draw(in: IconGrid.body, from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()

        // A faint bright rim, like light catching the edge of a material.
        NSColor.white.withAlphaComponent(0.18).setStroke()
        let rim = NSBezierPath(
            roundedRect: IconGrid.body.insetBy(dx: 1, dy: 1),
            xRadius: IconGrid.cornerRadius - 1,
            yRadius: IconGrid.cornerRadius - 1
        )
        rim.lineWidth = 2
        rim.stroke()
        return true
    }
}

func pngData(of image: NSImage) throws -> Data {
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:])
    else { throw IconError.encodingFailed }
    return png
}

do {
    let arguments = CommandLine.arguments.dropFirst()
    guard arguments.count == 2, let input = arguments.first, let output = arguments.last else { throw IconError.usage }
    guard let artwork = NSImage(contentsOfFile: input) else { throw IconError.unreadableArtwork(input) }
    try pngData(of: renderIcon(artwork: artwork)).write(to: URL(filePath: output))
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}
