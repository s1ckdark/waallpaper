import CoreGraphics
import Foundation

public enum WallpaperRenderer {
    /// Renders directly into one display-sized buffer; no giant desktop bitmap is allocated.
    /// The optional limit keeps previews inexpensive without changing the crop geometry.
    public static func render(
        image: CGImage,
        display: DisplayDescriptor,
        geometry: WallpaperGeometry,
        maxPixelDimension: Int? = nil
    ) throws -> CGImage {
        guard geometry.displays.contains(display) else { throw WallpaperError.displayNotInLayout }
        guard geometry.imageSize == CGSize(width: image.width, height: image.height) else {
            throw WallpaperError.imageSizeMismatch
        }
        try WallpaperRenderLimits.validate(width: image.width, height: image.height)

        var width = display.pixelWidth
        var height = display.pixelHeight
        if let limit = maxPixelDimension {
            guard limit > 0 else { throw WallpaperError.invalidGeometry("geometry_preview_size") }
            let factor = min(1, Double(limit) / Double(max(width, height)))
            width = max(1, Int((Double(width) * factor).rounded()))
            height = max(1, Int((Double(height) * factor).rounded()))
        }
        try WallpaperRenderLimits.validate(width: width, height: height)

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
              ) else {
            throw WallpaperError.imageRenderFailed
        }

        // Flatten transparency consistently for the desktop rather than depending on wallpaper options.
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .high

        let frame = geometry.normalizedFrame(for: display)
        let scaleX = CGFloat(width) / frame.width
        let scaleY = CGFloat(height) / frame.height
        // Core Graphics drawing uses a bottom-left origin. Convert the top-left geometry once here.
        let drawRect = CGRect(
            x: (geometry.imageRect.minX - frame.minX) * scaleX,
            y: (frame.maxY - geometry.imageRect.maxY) * scaleY,
            width: geometry.imageRect.width * scaleX,
            height: geometry.imageRect.height * scaleY
        )
        guard drawRect.origin.x.isFinite, drawRect.origin.y.isFinite,
              drawRect.width.isFinite, drawRect.height.isFinite,
              abs(drawRect.origin.x) <= 1_000_000_000, abs(drawRect.origin.y) <= 1_000_000_000,
              drawRect.width <= 1_000_000_000, drawRect.height <= 1_000_000_000 else {
            throw WallpaperError.invalidGeometry("geometry_render_zoom")
        }
        context.draw(image, in: drawRect)
        guard let result = context.makeImage() else { throw WallpaperError.imageRenderFailed }
        return result
    }
}
