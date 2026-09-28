import AppKit

let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        guard let context = NSGraphicsContext.current?.cgContext else { fatalError("Cannot create icon context") }
        context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        let background = CGPath(roundedRect: CGRect(x: 60, y: 60, width: 904, height: 904), cornerWidth: 202, cornerHeight: 202, transform: nil)
        context.addPath(background)
        context.setFillColor(CGColor(srgbRed: 0.10, green: 0.14, blue: 0.20, alpha: 1))
        context.fillPath()
        let screens = [CGRect(x: 170, y: 400, width: 290, height: 320), CGRect(x: 484, y: 294, width: 370, height: 426)]
        context.saveGState()
        for screen in screens { context.addPath(CGPath(roundedRect: screen, cornerWidth: 24, cornerHeight: 24, transform: nil)) }
        context.clip()
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
            CGColor(srgbRed: 0.98, green: 0.69, blue: 0.45, alpha: 1),
            CGColor(srgbRed: 0.64, green: 0.37, blue: 0.48, alpha: 1)
        ] as CFArray, locations: [0, 1])!
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 300), end: CGPoint(x: 0, y: 740), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        context.setFillColor(CGColor(srgbRed: 1, green: 0.88, blue: 0.65, alpha: 1))
        context.fillEllipse(in: CGRect(x: 640, y: 500, width: 120, height: 120))
        context.move(to: CGPoint(x: 120, y: 300))
        for point in [CGPoint(x: 280, y: 590), CGPoint(x: 500, y: 380), CGPoint(x: 610, y: 470), CGPoint(x: 900, y: 230), CGPoint(x: 120, y: 230)] { context.addLine(to: point) }
        context.closePath()
        context.setFillColor(CGColor(srgbRed: 0.19, green: 0.29, blue: 0.37, alpha: 1))
        context.fillPath()
        context.restoreGState()
        context.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.8))
        context.setLineWidth(9)
        for screen in screens {
            context.addPath(CGPath(roundedRect: screen, cornerWidth: 24, cornerHeight: 24, transform: nil))
            context.strokePath()
        }
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Cannot encode icon") }
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try png.write(to: folder.appendingPathComponent(name))
    }
}
