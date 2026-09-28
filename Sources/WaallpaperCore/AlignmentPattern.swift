import CoreGraphics
import Foundation

/// A shared world-space pattern for comparing physical monitor size and seam alignment.
public enum AlignmentPattern {
    public static func render(
        display: DisplayDescriptor,
        geometry: WallpaperGeometry,
        maxPixelDimension: Int? = nil
    ) throws -> CGImage {
        guard geometry.displays.contains(display) else { throw WallpaperError.displayNotInLayout }
        var width = display.pixelWidth
        var height = display.pixelHeight
        if let limit = maxPixelDimension {
            guard limit > 0 else { throw PatternError.invalidPreviewSize }
            let factor = min(1, Double(limit) / Double(max(width, height)))
            width = max(1, Int((Double(width) * factor).rounded()))
            height = max(1, Int((Double(height) * factor).rounded()))
        }
        try WallpaperRenderLimits.validate(width: width, height: height)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else {
            throw WallpaperError.imageRenderFailed
        }

        let frame = geometry.normalizedFrame(for: display)
        let canvas = geometry.canvasSize
        // Draw directly in the shared top-left world coordinates, then crop to this display.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: CGFloat(width) / frame.width, y: -CGFloat(height) / frame.height)
        context.translateBy(x: -frame.minX, y: -frame.minY)
        context.clip(to: frame)
        context.setFillColor(color(0.025, 0.045, 0.075))
        context.fill(frame)
        context.setShouldAntialias(true)
        context.setLineCap(.butt)

        // Ordinary layouts use 150-point squares and 600-point major lines. Keep
        // unusually large arrangements bounded to at most about 80 lines per axis.
        let expansion = max(0, ceil(log2(max(canvas.width, canvas.height) / 12_000)))
        let unit = pow(2, expansion)
        let spacing = 150 * unit
        for index in Int(floor(frame.minX / spacing))...Int(ceil(frame.maxX / spacing)) {
            let x = CGFloat(index) * spacing
            let major = index % 4 == 0
            context.setStrokeColor(major ? color(0.33, 0.49, 0.57) : color(0.15, 0.27, 0.34))
            context.setLineWidth((major ? 2 : 1) * unit)
            line(context, from: CGPoint(x: x, y: frame.minY), to: CGPoint(x: x, y: frame.maxY))
        }
        for index in Int(floor(frame.minY / spacing))...Int(ceil(frame.maxY / spacing)) {
            let y = CGFloat(index) * spacing
            let major = index % 4 == 0
            context.setStrokeColor(major ? color(0.33, 0.49, 0.57) : color(0.15, 0.27, 0.34))
            context.setLineWidth((major ? 2 : 1) * unit)
            line(context, from: CGPoint(x: frame.minX, y: y), to: CGPoint(x: frame.maxX, y: y))
        }

        context.setLineWidth(3 * unit)
        context.setStrokeColor(color(0.12, 0.88, 1))
        if (frame.minY...frame.maxY).contains(canvas.height / 2) {
            line(context, from: CGPoint(x: frame.minX, y: canvas.height / 2),
                 to: CGPoint(x: frame.maxX, y: canvas.height / 2))
        }
        context.setStrokeColor(color(1, 0.23, 0.65))
        if (frame.minX...frame.maxX).contains(canvas.width / 2) {
            line(context, from: CGPoint(x: canvas.width / 2, y: frame.minY),
                 to: CGPoint(x: canvas.width / 2, y: frame.maxY))
        }

        // Clip the diagonal mathematically so even a large gap between monitors does
        // not ask Core Graphics to draw a path far outside this small output buffer.
        // Include the stroke beyond the crop: ending a butt-capped path exactly at
        // a display edge cuts off part of the diagonal and creates a false seam.
        let diagonalPadding = 3 * unit + max(frame.width / CGFloat(width), frame.height / CGFloat(height))
        let diagonalBounds = frame.insetBy(dx: -diagonalPadding, dy: -diagonalPadding)
        let start = max(0, diagonalBounds.minX / canvas.width, diagonalBounds.minY / canvas.height)
        let end = min(1, diagonalBounds.maxX / canvas.width, diagonalBounds.maxY / canvas.height)
        if start <= end {
            context.setStrokeColor(color(1, 0.69, 0.22))
            line(context, from: CGPoint(x: start * canvas.width, y: start * canvas.height),
                 to: CGPoint(x: end * canvas.width, y: end * canvas.height))
        }
        guard let result = context.makeImage() else { throw WallpaperError.imageRenderFailed }
        return result
    }

    private static func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> CGColor {
        CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [red, green, blue, 1])!
    }

    private static func line(_ context: CGContext, from start: CGPoint, to end: CGPoint) {
        context.beginPath()
        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()
    }

    private enum PatternError: AppLocalizableError {
        case invalidPreviewSize

        func localizedDescription(language: AppLanguage) -> String {
            AppLocalization.text("alignment.error.previewSize", language: language)
        }
    }
}
