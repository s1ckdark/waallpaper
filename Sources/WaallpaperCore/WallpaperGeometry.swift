import Foundation

/// A display's system arrangement is measured in points, independently of its output pixels.
public struct DisplayDescriptor: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let frame: CGRect
    public let pixelWidth: Int
    public let pixelHeight: Int

    public init(id: String, name: String, frame: CGRect, pixelWidth: Int, pixelHeight: Int) {
        self.id = id
        self.name = name
        self.frame = frame
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }
}

public struct WallpaperPlacement: Equatable {
    public var zoom: Double
    public var horizontalOffset: Double
    public var verticalOffset: Double

    /// Offsets select the visible crop: -1 aligns the leading/top edge, +1 the trailing/bottom edge.
    public init(zoom: Double = 1, horizontalOffset: Double = 0, verticalOffset: Double = 0) {
        self.zoom = zoom
        self.horizontalOffset = horizontalOffset
        self.verticalOffset = verticalOffset
    }
}

public enum WallpaperError: AppLocalizableError, Equatable {
    case invalidGeometry(String)
    case outputTooLarge
    case displayNotInLayout
    case imageSizeMismatch
    case imageDecodeFailed
    case imageRenderFailed

    public func localizedDescription(language: AppLanguage) -> String {
        switch self {
        case .invalidGeometry(let reason):
            return AppLocalization.text("error_invalid_geometry", language: language,
                                        arguments: [AppLocalization.text(reason, language: language)])
        case .outputTooLarge: return AppLocalization.text("error_output_too_large", language: language)
        case .displayNotInLayout: return AppLocalization.text("error_display_changed", language: language)
        case .imageSizeMismatch: return AppLocalization.text("error_image_size_changed", language: language)
        case .imageDecodeFailed: return AppLocalization.text("error_image_decode", language: language)
        case .imageRenderFailed: return AppLocalization.text("error_image_render", language: language)
        }
    }
}

/// Layout coordinates have their origin at the top-left of the displays' bounding rectangle.
/// Empty space between displays remains part of the canvas, so images stay continuous.
public struct WallpaperGeometry {
    public let canvasSize: CGSize
    public let imageRect: CGRect
    public let imageSize: CGSize
    public let displays: [DisplayDescriptor]
    private let desktopBounds: CGRect
    private let effectiveFrames: [String: CGRect]

    public init(
        displays: [DisplayDescriptor],
        imageSize: CGSize,
        placement: WallpaperPlacement = .init(),
        calibrations: [String: DisplayCalibration] = [:]
    ) throws {
        guard !displays.isEmpty else {
            throw WallpaperError.invalidGeometry("geometry_no_displays")
        }
        guard Set(displays.map(\.id)).count == displays.count else {
            throw WallpaperError.invalidGeometry("geometry_duplicate")
        }
        guard imageSize.width.isFinite, imageSize.height.isFinite,
              imageSize.width > 0, imageSize.height > 0 else {
            throw WallpaperError.invalidGeometry("geometry_image_size")
        }
        guard placement.zoom.isFinite, placement.zoom >= 1,
              placement.horizontalOffset.isFinite, (-1...1).contains(placement.horizontalOffset),
              placement.verticalOffset.isFinite, (-1...1).contains(placement.verticalOffset) else {
            throw WallpaperError.invalidGeometry("geometry_placement")
        }
        var effectiveFrames: [String: CGRect] = [:]
        var bounds = CGRect.null
        for display in displays {
            let frame = display.frame
            guard frame.origin.x.isFinite, frame.origin.y.isFinite,
                  frame.size.width.isFinite, frame.size.height.isFinite,
                  frame.size.width > 0, frame.size.height > 0,
                  frame.maxX.isFinite, frame.maxY.isFinite,
                  display.pixelWidth > 0, display.pixelHeight > 0 else {
                throw WallpaperError.invalidGeometry("geometry_display_size")
            }
            try WallpaperRenderLimits.validate(width: display.pixelWidth, height: display.pixelHeight)

            let calibration = calibrations[display.id] ?? .init()
            guard calibration.isValid else {
                throw WallpaperError.invalidGeometry("geometry_calibration")
            }
            let baseFrame = calibration.baseFrame(for: display)
            // Preserve the base frame exactly when no correction is needed.
            let effectiveFrame: CGRect
            if calibration.scale == 1, calibration.offsetX == 0, calibration.offsetY == 0 {
                effectiveFrame = baseFrame
            } else {
                effectiveFrame = CGRect(
                    x: baseFrame.minX + calibration.offsetX,
                    y: baseFrame.maxY - calibration.offsetY - baseFrame.height * calibration.scale,
                    width: baseFrame.width * calibration.scale,
                    height: baseFrame.height * calibration.scale
                )
            }
            guard effectiveFrame.origin.x.isFinite, effectiveFrame.origin.y.isFinite,
                  effectiveFrame.width.isFinite, effectiveFrame.height.isFinite,
                  effectiveFrame.width > 0, effectiveFrame.height > 0,
                  effectiveFrame.maxX.isFinite, effectiveFrame.maxY.isFinite else {
                throw WallpaperError.invalidGeometry("geometry_calibrated_frame")
            }
            effectiveFrames[display.id] = effectiveFrame
            bounds = bounds.union(effectiveFrame)
        }
        guard bounds.width.isFinite, bounds.height.isFinite, bounds.width > 0, bounds.height > 0 else {
            throw WallpaperError.invalidGeometry("geometry_bounds")
        }
        let scale = max(bounds.width / imageSize.width, bounds.height / imageSize.height) * placement.zoom
        let width = imageSize.width * scale
        let height = imageSize.height * scale
        guard scale.isFinite, width.isFinite, height.isFinite, width > 0, height > 0 else {
            throw WallpaperError.invalidGeometry("geometry_zoom")
        }
        let overflowX = max(0, width - bounds.width)
        let overflowY = max(0, height - bounds.height)
        self.canvasSize = bounds.size
        self.imageRect = CGRect(
            x: -overflowX * ((placement.horizontalOffset + 1) / 2),
            y: -overflowY * ((placement.verticalOffset + 1) / 2),
            width: width,
            height: height
        )
        self.imageSize = imageSize
        self.displays = displays
        self.desktopBounds = bounds
        self.effectiveFrames = effectiveFrames
    }

    public func normalizedFrame(for display: DisplayDescriptor) -> CGRect {
        let frame = effectiveFrames[display.id] ?? display.frame
        return CGRect(
            x: frame.minX - desktopBounds.minX,
            y: desktopBounds.maxY - frame.maxY,
            width: frame.width,
            height: frame.height
        )
    }
}

enum WallpaperRenderLimits {
    static let maximumDimension = 16_384
    static let maximumPixels = 100_000_000

    static func validate(width: Int, height: Int) throws {
        guard width > 0, height > 0,
              width <= maximumDimension, height <= maximumDimension,
              width <= maximumPixels / height else {
            throw WallpaperError.outputTooLarge
        }
    }
}
