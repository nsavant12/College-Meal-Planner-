import AppKit
import ImageIO
import UniformTypeIdentifiers

// A reproducible, original vector drawing. Run from the repository root:
// swift scripts/generate-app-icon.swift
let size = 1024
guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                              bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
    fatalError("Could not create icon bitmap")
}
let graphics = NSGraphicsContext(cgContext: context, flipped: false)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphics
graphics.imageInterpolation = .high
let dark = NSColor(srgbRed: 0.06, green: 0.31, blue: 0.27, alpha: 1)
let cream = NSColor(srgbRed: 0.99, green: 0.96, blue: 0.87, alpha: 1)
let lime = NSColor(srgbRed: 0.78, green: 0.87, blue: 0.43, alpha: 1)
dark.setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: size, height: size)).fill()
cream.setFill()
NSBezierPath(ovalIn: NSRect(x: 268, y: 214, width: 564, height: 596)).fill()
dark.withAlphaComponent(0.12).setStroke()
let rim = NSBezierPath(ovalIn: NSRect(x: 312, y: 260, width: 476, height: 504))
rim.lineWidth = 6
rim.stroke()

func line(_ points: [NSPoint], color: NSColor, width: CGFloat) {
    let path = NSBezierPath()
    path.move(to: points[0])
    for point in points.dropFirst() { path.line(to: point) }
    path.lineWidth = width
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    color.setStroke()
    path.stroke()
}
// Fork silhouette.
line([NSPoint(x: 186, y: 238), NSPoint(x: 186, y: 627)], color: cream, width: 28)
line([NSPoint(x: 130, y: 770), NSPoint(x: 130, y: 646), NSPoint(x: 186, y: 610),
      NSPoint(x: 242, y: 646), NSPoint(x: 242, y: 770)], color: cream, width: 23)
line([NSPoint(x: 186, y: 770), NSPoint(x: 186, y: 642)], color: cream, width: 23)

// Two leaves on a single stem in the center of the plate.
let upperLeaf = NSBezierPath()
upperLeaf.move(to: NSPoint(x: 527, y: 486))
upperLeaf.curve(to: NSPoint(x: 700, y: 682), controlPoint1: NSPoint(x: 489, y: 641), controlPoint2: NSPoint(x: 608, y: 711))
upperLeaf.curve(to: NSPoint(x: 527, y: 486), controlPoint1: NSPoint(x: 722, y: 555), controlPoint2: NSPoint(x: 624, y: 482))
dark.setFill()
upperLeaf.fill()
let lowerLeaf = NSBezierPath()
lowerLeaf.move(to: NSPoint(x: 529, y: 457))
lowerLeaf.curve(to: NSPoint(x: 398, y: 588), controlPoint1: NSPoint(x: 413, y: 441), controlPoint2: NSPoint(x: 372, y: 518))
lowerLeaf.curve(to: NSPoint(x: 529, y: 457), controlPoint1: NSPoint(x: 503, y: 611), controlPoint2: NSPoint(x: 558, y: 540))
lime.setFill()
lowerLeaf.fill()
line([NSPoint(x: 502, y: 365), NSPoint(x: 535, y: 498), NSPoint(x: 635, y: 618)], color: dark, width: 20)
NSGraphicsContext.restoreGraphicsState()

let output = "Recipe Maker/Recipe Maker/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
guard let image = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: output) as CFURL,
                                                        UTType.png.identifier as CFString, 1, nil) else {
    fatalError("Could not encode PNG")
}
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("Could not save PNG") }
print("Generated \(output)")
