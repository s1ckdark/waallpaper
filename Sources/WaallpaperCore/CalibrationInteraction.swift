import Foundation

public extension DisplayCalibration {
    /// Unnormalized world coordinates, with positive Y pointing down.
    /// Invalid settings are sanitized; an invalid display frame produces an empty rectangle.
    func canvasFrame(for display: DisplayDescriptor) -> CGRect {
        guard validDisplayFrame(display.frame) else { return .zero }
        let calibration = sanitized(self)
        let baseFrame = calibration.baseFrame(for: display)
        let frame = CGRect(
            x: baseFrame.minX + calibration.offsetX,
            y: -baseFrame.maxY + calibration.offsetY,
            width: baseFrame.width * calibration.scale,
            height: baseFrame.height * calibration.scale
        )
        return validDisplayFrame(frame) ? frame : .zero
    }
}

public enum CalibrationCorner: CaseIterable, Equatable {
    case topLeft, topRight, bottomLeft, bottomRight

    fileprivate var movesLeftEdge: Bool { self == .topLeft || self == .bottomLeft }
    fileprivate var movesTopEdge: Bool { self == .topLeft || self == .topRight }
}

public struct CalibrationGuide: Equatable {
    public enum Axis: Equatable { case horizontal, vertical }
    public let axis: Axis
    public let coordinate: CGFloat

    public init(axis: Axis, coordinate: CGFloat) {
        self.axis = axis
        self.coordinate = coordinate
    }
}

public struct CalibrationEditResult: Equatable {
    public let calibration: DisplayCalibration
    public let guides: [CalibrationGuide]

    public init(calibration: DisplayCalibration, guides: [CalibrationGuide]) {
        self.calibration = calibration
        self.guides = guides
    }
}

public enum CalibrationInteraction {
    public static func move(
        display: DisplayDescriptor,
        start: DisplayCalibration,
        translation: CGSize,
        others: [CGRect],
        snapDistance: CGFloat
    ) -> CalibrationEditResult {
        let initial = sanitized(start)
        guard validInteraction(display: display, start: start, translation: translation) else {
            return .init(calibration: initial, guides: [])
        }
        var result = DisplayCalibration(
            scale: initial.scale,
            offsetX: clamped(initial.offsetX + translation.width, to: DisplayCalibration.offsetRange),
            offsetY: clamped(initial.offsetY + translation.height, to: DisplayCalibration.offsetRange),
            referenceFrame: initial.referenceFrame
        )
        guard snapDistance.isFinite, snapDistance > 0 else { return .init(calibration: result, guides: []) }
        let frame = result.canvasFrame(for: display)
        let targets = alignmentTargets(others)
        var selectedGuides: [CalibrationGuide] = []
        if let snap = nearestMoveSnap(features: xFeatures(frame), targets: targets.x, offset: result.offsetX, tolerance: snapDistance) {
            result.offsetX = clamped(result.offsetX + snap.delta, to: DisplayCalibration.offsetRange)
            selectedGuides.append(.init(axis: .vertical, coordinate: snap.target))
        }
        if let snap = nearestMoveSnap(features: yFeatures(frame), targets: targets.y, offset: result.offsetY, tolerance: snapDistance) {
            result.offsetY = clamped(result.offsetY + snap.delta, to: DisplayCalibration.offsetRange)
            selectedGuides.append(.init(axis: .horizontal, coordinate: snap.target))
        }
        let finalFrame = result.canvasFrame(for: display)
        return .init(calibration: result, guides: selectedGuides.filter { matches($0, frame: finalFrame) })
    }

    public static func resize(
        display: DisplayDescriptor,
        start: DisplayCalibration,
        corner: CalibrationCorner,
        translation: CGSize,
        others: [CGRect],
        snapDistance: CGFloat
    ) -> CalibrationEditResult {
        let initial = sanitized(start)
        guard validInteraction(display: display, start: start, translation: translation) else {
            return .init(calibration: initial, guides: [])
        }
        let baseFrame = initial.baseFrame(for: display)
        let width = baseFrame.width
        let height = baseFrame.height
        let diagonal = hypot(width, height)
        guard diagonal.isFinite, diagonal > 0 else { return .init(calibration: initial, guides: []) }

        // Project the pointer onto the aspect-preserving diagonal through the fixed corner.
        let delta = ((corner.movesLeftEdge ? -translation.width : translation.width) * (width / diagonal)
            + (corner.movesTopEdge ? -translation.height : translation.height) * (height / diagonal)) / diagonal
        guard !delta.isNaN else { return .init(calibration: initial, guides: []) }
        let scaleRange = feasibleScaleRange(display: display, start: initial, corner: corner)
        var scale = clamped(initial.scale + delta, to: scaleRange)
        let proposed = resizedCalibration(display: display, start: initial, corner: corner, scale: scale)
        var snapped = false

        if snapDistance.isFinite, snapDistance > 0 {
            let frame = proposed.canvasFrame(for: display)
            let targets = alignmentTargets(others, includeCenters: false)
            let movingX = corner.movesLeftEdge ? frame.minX : frame.maxX
            let movingY = corner.movesTopEdge ? frame.minY : frame.maxY
            var nearestTravel = CGFloat.infinity
            for (feature, slope, coordinates) in [
                (movingX, corner.movesLeftEdge ? -width : width, targets.x),
                (movingY, corner.movesTopEdge ? -height : height, targets.y)
            ] {
                for coordinate in coordinates {
                    let correction = (coordinate - feature) / slope
                    let candidate = proposed.scale + correction
                    let travel = abs(correction) * diagonal
                    // Bound the corner's actual movement, even for very wide/tall displays.
                    guard candidate.isFinite, scaleRange.contains(candidate),
                          travel <= snapDistance, travel < nearestTravel else { continue }
                    nearestTravel = travel
                    snapped = true
                    // Every candidate is measured from the same unsnapped proposal.
                    scale = candidate
                }
            }
        }
        let result = resizedCalibration(display: display, start: initial, corner: corner, scale: scale)
        guard result.isValid, validDisplayFrame(result.canvasFrame(for: display)) else {
            return .init(calibration: initial, guides: [])
        }
        let guides = snapped ? matchingGuides(frame: result.canvasFrame(for: display), others: others) : []
        return .init(calibration: result, guides: guides)
    }
}

private func sanitized(_ calibration: DisplayCalibration) -> DisplayCalibration {
    .init(
        scale: clamped(calibration.scale.isFinite ? calibration.scale : 1, to: DisplayCalibration.scaleRange),
        offsetX: clamped(calibration.offsetX.isFinite ? calibration.offsetX : 0, to: DisplayCalibration.offsetRange),
        offsetY: clamped(calibration.offsetY.isFinite ? calibration.offsetY : 0, to: DisplayCalibration.offsetRange),
        referenceFrame: calibration.referenceFrame.flatMap { validDisplayFrame($0) ? $0 : nil }
    )
}

private func clamped(_ value: Double, to range: ClosedRange<Double>) -> Double {
    min(range.upperBound, max(range.lowerBound, value))
}

private func validDisplayFrame(_ frame: CGRect) -> Bool {
    DisplayCalibration.isValidFrame(frame)
}

private func validInteraction(display: DisplayDescriptor, start: DisplayCalibration, translation: CGSize) -> Bool {
    start.isValid && validDisplayFrame(display.frame)
        && validDisplayFrame(start.canvasFrame(for: display))
        && translation.width.isFinite && translation.height.isFinite
}

private func xFeatures(_ frame: CGRect) -> [CGFloat] { [frame.minX, frame.midX, frame.maxX] }
private func yFeatures(_ frame: CGRect) -> [CGFloat] { [frame.minY, frame.midY, frame.maxY] }

private func alignmentTargets(_ others: [CGRect], includeCenters: Bool = true) -> (x: [CGFloat], y: [CGFloat]) {
    let frames = others.filter(validDisplayFrame)
    if !includeCenters {
        return (Array(Set(frames.flatMap { [$0.minX, $0.maxX] })).sorted(), Array(Set(frames.flatMap { [$0.minY, $0.maxY] })).sorted())
    }
    return (Array(Set(frames.flatMap(xFeatures))).sorted(), Array(Set(frames.flatMap(yFeatures))).sorted())
}

private func nearestMoveSnap(features: [CGFloat], targets: [CGFloat], offset: Double, tolerance: CGFloat) -> (delta: CGFloat, target: CGFloat)? {
    var best: (delta: CGFloat, target: CGFloat)?
    for feature in features {
        for target in targets {
            let delta = target - feature
            guard delta.isFinite, abs(delta) <= tolerance,
                  DisplayCalibration.offsetRange.contains(offset + delta) else { continue }
            if best == nil || abs(delta) < abs(best!.delta) { best = (delta, target) }
        }
    }
    return best
}

private func feasibleScaleRange(display: DisplayDescriptor, start: DisplayCalibration, corner: CalibrationCorner) -> ClosedRange<Double> {
    var lower = DisplayCalibration.scaleRange.lowerBound
    var upper = DisplayCalibration.scaleRange.upperBound
    let baseFrame = start.baseFrame(for: display)
    for (movesLeadingEdge, offset, length) in [
        (corner.movesLeftEdge, start.offsetX, baseFrame.width),
        (corner.movesTopEdge, start.offsetY, baseFrame.height)
    ] where movesLeadingEdge {
        lower = max(lower, start.scale + (offset - DisplayCalibration.offsetRange.upperBound) / length)
        upper = min(upper, start.scale + (offset - DisplayCalibration.offsetRange.lowerBound) / length)
    }
    // The valid starting calibration is always a feasible point.
    return min(lower, start.scale)...max(upper, start.scale)
}

private func resizedCalibration(display: DisplayDescriptor, start: DisplayCalibration, corner: CalibrationCorner, scale: Double) -> DisplayCalibration {
    let baseFrame = start.baseFrame(for: display)
    return .init(
        scale: scale,
        offsetX: clamped(start.offsetX + (corner.movesLeftEdge ? (start.scale - scale) * baseFrame.width : 0), to: DisplayCalibration.offsetRange),
        offsetY: clamped(start.offsetY + (corner.movesTopEdge ? (start.scale - scale) * baseFrame.height : 0), to: DisplayCalibration.offsetRange),
        referenceFrame: start.referenceFrame
    )
}

private func matches(_ guide: CalibrationGuide, frame: CGRect) -> Bool {
    let features = guide.axis == .vertical ? xFeatures(frame) : yFeatures(frame)
    let tolerance = max(0.0000001, abs(guide.coordinate) * 1e-12)
    return features.contains { abs($0 - guide.coordinate) <= tolerance }
}

private func matchingGuides(frame: CGRect, others: [CGRect]) -> [CalibrationGuide] {
    let targets = alignmentTargets(others)
    return (targets.x.map { CalibrationGuide(axis: .vertical, coordinate: $0) }
        + targets.y.map { CalibrationGuide(axis: .horizontal, coordinate: $0) })
        .filter { matches($0, frame: frame) }
}
