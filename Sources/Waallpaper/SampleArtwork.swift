import AppKit

enum SampleArtwork {
    /// A code-drawn sample so the app is useful before a photo is selected.
    static func make() -> CGImage? {
        let width = 6400, height = 2800
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.scaleBy(x: CGFloat(width) / 1600, y: CGFloat(height) / 700)
        let colors = [color(0x233451), color(0xC17981), color(0xF6B783)] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.6, 1]) {
            context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 700), end: .zero, options: [])
        }
        context.setFillColor(color(0xFFE0AA))
        context.fillEllipse(in: CGRect(x: 1015, y: 290, width: 200, height: 200))
        mountain(context, points: [(-40, 230), (80, 330), (210, 250), (420, 470), (550, 320), (690, 410),
                                  (870, 255), (1040, 340), (1190, 250), (1380, 390), (1660, 200)], fill: 0x626080)
        mountain(context, points: [(-40, 160), (160, 250), (340, 150), (550, 300), (760, 200), (970, 270),
                                  (1140, 160), (1400, 260), (1660, 160)], fill: 0x3C4C68)
        mountain(context, points: [(-40, 60), (210, 150), (440, 80), (640, 160), (880, 100), (1150, 180),
                                  (1360, 70), (1660, 150)], fill: 0x23384C)
        return context.makeImage()
    }

    private static func mountain(_ context: CGContext, points: [(CGFloat, CGFloat)], fill: UInt32) {
        context.beginPath()
        context.move(to: CGPoint(x: -40, y: 0))
        for point in points { context.addLine(to: CGPoint(x: point.0, y: point.1)) }
        context.addLine(to: CGPoint(x: 1660, y: 0))
        context.closePath()
        context.setFillColor(color(fill))
        context.fillPath()
    }

    private static func color(_ value: UInt32) -> CGColor {
        CGColor(srgbRed: CGFloat((value >> 16) & 255) / 255,
                green: CGFloat((value >> 8) & 255) / 255,
                blue: CGFloat(value & 255) / 255, alpha: 1)
    }
}
