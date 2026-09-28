import XCTest
@testable import WaallpaperCore

final class CalibrationInteractionTests: XCTestCase {
    func testCanvasFrameUsesUnnormalizedDownwardCoordinates() {
        let screen = display("main", x: -300, y: 50, width: 200, height: 100)
        let frame = DisplayCalibration(scale: 1.5, offsetX: 20, offsetY: 30).canvasFrame(for: screen)
        XCTAssertEqual(frame, CGRect(x: -280, y: -120, width: 300, height: 150))
    }

    func testMoveWithoutSnappingAddsLogicalTranslation() {
        let screen = display("main", x: 100, y: 200, width: 200, height: 100)
        let start = DisplayCalibration(scale: 1.5, offsetX: 20, offsetY: -30)
        let result = CalibrationInteraction.move(display: screen, start: start, translation: CGSize(width: -15, height: 25), others: [CGRect(x: 100, y: -300, width: 200, height: 100)], snapDistance: 0)
        XCTAssertEqual(result.calibration, .init(scale: 1.5, offsetX: 5, offsetY: -5))
        XCTAssertTrue(result.guides.isEmpty)
    }

    func testMoveSnapsAdjacentEdgesAndMatchingTop() {
        let screen = display("main", x: 0, y: 0, width: 100, height: 100)
        let other = CGRect(x: 200, y: -100, width: 100, height: 100)
        let result = CalibrationInteraction.move(display: screen, start: .init(), translation: CGSize(width: 97, height: 3), others: [other], snapDistance: 5)
        let frame = result.calibration.canvasFrame(for: screen)
        XCTAssertEqual(frame.maxX, other.minX)
        XCTAssertEqual(frame.minY, other.minY)
        XCTAssertEqual(result.calibration, .init(offsetX: 100))
        XCTAssertTrue(result.guides.contains(.init(axis: .vertical, coordinate: 200)))
        XCTAssertTrue(result.guides.contains(.init(axis: .horizontal, coordinate: -100)))
    }

    func testMoveChoosesNearestAlignmentAcrossMonitors() {
        let screen = display("main", x: 0, y: 0, width: 100, height: 100)
        let others = [CGRect(x: 200, y: 1000, width: 100, height: 100), CGRect(x: 198, y: 2000, width: 100, height: 100)]
        let result = CalibrationInteraction.move(display: screen, start: .init(), translation: CGSize(width: 97, height: 0), others: others, snapDistance: 5)
        XCTAssertEqual(result.calibration.offsetX, 98)
        XCTAssertEqual(result.guides, [.init(axis: .vertical, coordinate: 198)])
    }

    func testMoveCanAlignCenters() {
        let screen = display("main", x: 0, y: 0, width: 100, height: 100)
        let other = CGRect(x: 200, y: 1000, width: 200, height: 200)
        let result = CalibrationInteraction.move(display: screen, start: .init(), translation: CGSize(width: 251, height: 0), others: [other], snapDistance: 3)
        XCTAssertEqual(result.calibration.canvasFrame(for: screen).midX, other.midX)
        XCTAssertEqual(result.guides, [.init(axis: .vertical, coordinate: 300)])
    }

    func testEveryResizeCornerKeepsOppositeCornerFixed() {
        let screen = display("main", x: 100, y: 200, width: 200, height: 100)
        let start = DisplayCalibration(offsetX: 10, offsetY: 20)
        let before = start.canvasFrame(for: screen)
        for corner in CalibrationCorner.allCases {
            let translation = CGSize(width: left(corner) ? -100 : 100, height: top(corner) ? -50 : 50)
            let result = CalibrationInteraction.resize(display: screen, start: start, corner: corner, translation: translation, others: [], snapDistance: 0)
            let after = result.calibration.canvasFrame(for: screen)
            XCTAssertEqual(result.calibration.scale, 1.5, accuracy: 1e-10)
            assertPoint(oppositeCorner(after, corner), equals: oppositeCorner(before, corner))
            assertPoint(movingCorner(after, corner), equals: CGPoint(x: movingCorner(before, corner).x + translation.width, y: movingCorner(before, corner).y + translation.height))
            XCTAssertEqual(after.width / after.height, 2, accuracy: 1e-10)
            XCTAssertTrue(result.guides.isEmpty)
        }
    }

    func testResizeProjectsOffDiagonalTranslationWithoutChangingAspect() {
        let screen = display("main", x: 0, y: 0, width: 200, height: 100)
        let result = CalibrationInteraction.resize(display: screen, start: .init(), corner: .bottomRight, translation: CGSize(width: 200, height: 0), others: [], snapDistance: 0)
        XCTAssertEqual(result.calibration.scale, 1.8, accuracy: 1e-10)
        XCTAssertEqual(result.calibration.offsetX, 0)
        XCTAssertEqual(result.calibration.offsetY, 0)
    }

    func testResizeChoosesNearestEdgeSnapAndPreservesAnchor() {
        let screen = display("main", x: 0, y: 0, width: 100, height: 100)
        let others = [CGRect(x: 150, y: 500, width: 100, height: 100), CGRect(x: 148, y: 800, width: 100, height: 100)]
        let result = CalibrationInteraction.resize(display: screen, start: .init(), corner: .bottomRight, translation: CGSize(width: 47, height: 47), others: others, snapDistance: 5)
        XCTAssertEqual(result.calibration.scale, 1.48, accuracy: 1e-10)
        XCTAssertEqual(result.calibration.canvasFrame(for: screen).origin, CGPoint(x: 0, y: -100))
        XCTAssertEqual(result.guides, [.init(axis: .vertical, coordinate: 148)])
    }

    func testTopLeftResizeSnapsWhileOppositeCornerStaysFixed() {
        let screen = display("main", x: 0, y: 0, width: 100, height: 100)
        let other = CGRect(x: -150, y: 500, width: 100, height: 100)
        let result = CalibrationInteraction.resize(display: screen, start: .init(), corner: .topLeft, translation: CGSize(width: -47, height: -47), others: [other], snapDistance: 5)
        XCTAssertEqual(result.calibration.scale, 1.5, accuracy: 1e-10)
        let frame = result.calibration.canvasFrame(for: screen)
        assertPoint(CGPoint(x: frame.maxX, y: frame.maxY), equals: CGPoint(x: 100, y: 0))
        XCTAssertTrue(result.guides.contains(.init(axis: .vertical, coordinate: -50)))
    }

    func testResizeDoesNotJumpFarToSnapShortDimension() {
        let screen = display("wide", x: 0, y: 0, width: 1000, height: 10)
        let translation = CGSize(width: 10, height: 0)
        let unsnapped = CalibrationInteraction.resize(display: screen, start: .init(), corner: .bottomRight, translation: translation, others: [], snapDistance: 0)
        let snapped = CalibrationInteraction.resize(display: screen, start: .init(), corner: .bottomRight, translation: translation, others: [CGRect(x: 5000, y: 1, width: 100, height: 20)], snapDistance: 5)
        XCTAssertEqual(snapped.calibration, unsnapped.calibration)
        XCTAssertTrue(snapped.guides.isEmpty)
    }

    func testResizeSnapsToEdgesRatherThanOtherMonitorCenters() {
        let screen = display("main", x: 0, y: 0, width: 100, height: 100)
        let result = CalibrationInteraction.resize(display: screen, start: .init(), corner: .bottomRight, translation: CGSize(width: 47, height: 47), others: [CGRect(x: 100, y: 500, width: 100, height: 100)], snapDistance: 5)
        XCTAssertEqual(result.calibration.scale, 1.47, accuracy: 1e-10)
        XCTAssertTrue(result.guides.isEmpty)
    }

    func testEveryCornerClampsScaleAndKeepsAnchor() {
        let screen = display("main", x: 0, y: 0, width: 200, height: 100)
        let before = DisplayCalibration().canvasFrame(for: screen)
        for corner in CalibrationCorner.allCases {
            for (direction, expectedScale) in [(1.0, 4.0), (-1.0, 0.25)] {
                let translation = CGSize(width: (left(corner) ? -1 : 1) * direction * 1_000_000, height: (top(corner) ? -1 : 1) * direction * 1_000_000)
                let result = CalibrationInteraction.resize(display: screen, start: .init(), corner: corner, translation: translation, others: [], snapDistance: 0)
                XCTAssertEqual(result.calibration.scale, expectedScale)
                XCTAssertTrue(result.calibration.isValid)
                assertPoint(oppositeCorner(result.calibration.canvasFrame(for: screen), corner), equals: oppositeCorner(before, corner))
            }
        }
    }

    func testResizeOffsetLimitRestrictsScaleInsteadOfMovingAnchor() {
        let screen = display("main", x: 0, y: 0, width: 100, height: 100)
        let start = DisplayCalibration(offsetX: -9990)
        let before = start.canvasFrame(for: screen)
        let result = CalibrationInteraction.resize(display: screen, start: start, corner: .topLeft, translation: CGSize(width: -500, height: -500), others: [], snapDistance: 0)
        XCTAssertEqual(result.calibration.scale, 1.1, accuracy: 1e-10)
        XCTAssertEqual(result.calibration.offsetX, -10_000, accuracy: 1e-10)
        assertPoint(oppositeCorner(result.calibration.canvasFrame(for: screen), .topLeft), equals: oppositeCorner(before, .topLeft))
    }

    func testMoveClampsOffsetsAndDoesNotReportUnreachableSnap() {
        let screen = display("main", x: 0, y: 0, width: 100, height: 100)
        let clamped = CalibrationInteraction.move(display: screen, start: .init(), translation: CGSize(width: 50_000, height: -50_000), others: [], snapDistance: 0)
        XCTAssertEqual(clamped.calibration, .init(offsetX: 10_000, offsetY: -10_000))
        let result = CalibrationInteraction.move(display: screen, start: .init(offsetX: 9999), translation: .zero, others: [CGRect(x: 10_105, y: 1000, width: 100, height: 100)], snapDistance: 10)
        XCTAssertEqual(result.calibration.offsetX, 9999)
        XCTAssertTrue(result.guides.isEmpty)
    }

    func testInvalidInputAlwaysReturnsFiniteValidSettings() {
        let screen = display("main", x: 0, y: 0, width: 100, height: 100)
        let badStart = DisplayCalibration(scale: .nan, offsetX: 20_000, offsetY: .infinity)
        let move = CalibrationInteraction.move(display: screen, start: badStart, translation: CGSize(width: CGFloat.nan, height: 0), others: [.null, .infinite], snapDistance: .infinity)
        XCTAssertEqual(move.calibration, .init(offsetX: 10_000))
        XCTAssertTrue(move.guides.isEmpty)
        for corner in CalibrationCorner.allCases {
            let result = CalibrationInteraction.resize(display: screen, start: .init(), corner: corner, translation: CGSize(width: CGFloat.infinity, height: 0), others: [.null], snapDistance: 5)
            XCTAssertEqual(result.calibration, .init())
            XCTAssertTrue(result.guides.isEmpty)
        }
        let invalidDisplay = DisplayDescriptor(id: "bad", name: "bad", frame: CGRect(x: 0, y: 0, width: -1, height: 1), pixelWidth: 1, pixelHeight: 1)
        XCTAssertEqual(DisplayCalibration().canvasFrame(for: invalidDisplay), .zero)
        let result = CalibrationInteraction.resize(display: invalidDisplay, start: badStart, corner: .bottomRight, translation: CGSize(width: 50, height: 50), others: [], snapDistance: 5)
        XCTAssertTrue(result.calibration.isValid)
        XCTAssertTrue(result.guides.isEmpty)
    }

    func testInvalidSnapDistanceDisablesSnappingAndInvalidOtherFramesAreIgnored() {
        let screen = display("main", x: 0, y: 0, width: 100, height: 100)
        for distance in [CGFloat.zero, -1, .nan, .infinity] {
            let result = CalibrationInteraction.move(display: screen, start: .init(), translation: CGSize(width: 97, height: 0), others: [CGRect(x: 200, y: -100, width: 100, height: 100)], snapDistance: distance)
            XCTAssertEqual(result.calibration.offsetX, 97)
            XCTAssertTrue(result.guides.isEmpty)
        }
        let result = CalibrationInteraction.move(display: screen, start: .init(), translation: CGSize(width: 97, height: 0), others: [.null, .infinite, .zero], snapDistance: 5)
        XCTAssertEqual(result.calibration.offsetX, 97)
        XCTAssertTrue(result.guides.isEmpty)
    }

    private func left(_ corner: CalibrationCorner) -> Bool { corner == .topLeft || corner == .bottomLeft }
    private func top(_ corner: CalibrationCorner) -> Bool { corner == .topLeft || corner == .topRight }
    private func movingCorner(_ frame: CGRect, _ corner: CalibrationCorner) -> CGPoint {
        CGPoint(x: left(corner) ? frame.minX : frame.maxX, y: top(corner) ? frame.minY : frame.maxY)
    }
    private func oppositeCorner(_ frame: CGRect, _ corner: CalibrationCorner) -> CGPoint {
        CGPoint(x: left(corner) ? frame.maxX : frame.minX, y: top(corner) ? frame.maxY : frame.minY)
    }
    private func assertPoint(_ actual: CGPoint, equals expected: CGPoint, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.x, expected.x, accuracy: 1e-8, file: file, line: line)
        XCTAssertEqual(actual.y, expected.y, accuracy: 1e-8, file: file, line: line)
    }
}
