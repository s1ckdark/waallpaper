import Foundation

public enum DisplayLayoutMode: String, Codable, CaseIterable {
    case system, manual
}

/// Manual corrections to a display's logical footprint; output pixel dimensions stay unchanged.
public struct DisplayCalibration: Codable, Equatable {
    public static let scaleRange: ClosedRange<Double> = 0.25...4
    public static let offsetRange: ClosedRange<Double> = -10_000...10_000

    /// Uniform scale around the display's top-left corner.
    public var scale: Double
    /// Logical points; positive values move the display right.
    public var offsetX: Double
    /// Logical points; positive values move the display down.
    public var offsetY: Double
    /// A captured macOS frame that keeps manual placement independent of later system changes.
    /// Nil keeps the calibration relative to the display's current system arrangement.
    public var referenceFrame: CGRect?

    public init(scale: Double = 1, offsetX: Double = 0, offsetY: Double = 0, referenceFrame: CGRect? = nil) {
        self.scale = scale
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.referenceFrame = referenceFrame
    }

    /// The frame used to position and size the display's logical footprint.
    public func baseFrame(for display: DisplayDescriptor) -> CGRect {
        referenceFrame ?? display.frame
    }

    /// Check decoded settings before restoring them. Geometry also validates applied records.
    public var isValid: Bool {
        scale.isFinite && Self.scaleRange.contains(scale)
            && offsetX.isFinite && Self.offsetRange.contains(offsetX)
            && offsetY.isFinite && Self.offsetRange.contains(offsetY)
            && (referenceFrame.map(Self.isValidFrame) ?? true)
    }

    static func isValidFrame(_ frame: CGRect) -> Bool {
        !frame.isNull && !frame.isInfinite
            && frame.origin.x.isFinite && frame.origin.y.isFinite
            && frame.size.width.isFinite && frame.size.height.isFinite
            && frame.size.width > 0 && frame.size.height > 0
            && frame.maxX.isFinite && frame.maxY.isFinite
    }
}
