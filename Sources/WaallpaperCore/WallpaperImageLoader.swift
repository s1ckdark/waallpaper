import CoreGraphics
import Foundation
import ImageIO

public enum WallpaperImageLoader {
    /// ImageIO applies EXIF rotation/mirroring during a bounded decode of the first image.
    public static func load(url: URL) throws -> CGImage {
        guard url.isFileURL,
              let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let sourceWidth = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let sourceHeight = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              sourceWidth.isFinite, sourceHeight.isFinite, sourceWidth > 0, sourceHeight > 0 else {
            throw WallpaperError.imageDecodeFailed
        }

        let shortToLongRatio = min(sourceWidth, sourceHeight) / max(sourceWidth, sourceHeight)
        let pixelBudgetDimension = sqrt(Double(WallpaperRenderLimits.maximumPixels) / shortToLongRatio)
        let maxDimension = Int(min(Double(WallpaperRenderLimits.maximumDimension), pixelBudgetDimension).rounded(.down))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw WallpaperError.imageDecodeFailed
        }
        try WallpaperRenderLimits.validate(width: image.width, height: image.height)
        return image
    }
}
