import XCTest
@testable import WaallpaperCore

final class ManualLayoutTests: XCTestCase {
    func testOlderCalibrationRecordsDecodeWithoutReferenceFrame() throws {
        let data = Data(#"{"scale":1.25,"offsetX":-160.5,"offsetY":45}"#.utf8)
        let calibration = try JSONDecoder().decode(DisplayCalibration.self, from: data)

        XCTAssertEqual(calibration, .init(scale: 1.25, offsetX: -160.5, offsetY: 45))
        XCTAssertNil(calibration.referenceFrame)
        XCTAssertTrue(calibration.isValid)
    }

    func testManualCalibrationPersistsItsCapturedFrame() throws {
        let calibration = DisplayCalibration(
            scale: 1.25, offsetX: -160.5, offsetY: 45,
            referenceFrame: CGRect(x: -1200, y: -300, width: 1200, height: 1600)
        )
        let data = try JSONEncoder().encode(calibration)
        let decoded = try JSONDecoder().decode(DisplayCalibration.self, from: data)

        XCTAssertEqual(decoded, calibration)
        XCTAssertTrue(decoded.isValid)
    }

    func testManualFootprintsSurviveSystemOriginAndLogicalSizeChanges() throws {
        let originalLeft = display("left", x: -4, y: 0, width: 4, height: 8)
        let originalRight = display("right", x: 0, y: 0, width: 4, height: 8)
        let changedLeft = DisplayDescriptor(
            id: "left", name: "left", frame: CGRect(x: 400, y: -200, width: 40, height: 24),
            pixelWidth: 8, pixelHeight: 16
        )
        let changedRight = display("right", x: -80, y: 30, width: 8, height: 10)
        let calibrations = [
            "left": DisplayCalibration(referenceFrame: originalLeft.frame),
            "right": DisplayCalibration(referenceFrame: originalRight.frame)
        ]
        let size = CGSize(width: 8, height: 8)
        let before = try WallpaperGeometry(displays: [originalLeft, originalRight], imageSize: size, calibrations: calibrations)
        let after = try WallpaperGeometry(displays: [changedRight, changedLeft], imageSize: size, calibrations: calibrations)

        XCTAssertEqual(after.canvasSize, before.canvasSize)
        XCTAssertEqual(after.imageRect, before.imageRect)
        XCTAssertEqual(after.normalizedFrame(for: changedLeft), before.normalizedFrame(for: originalLeft))
        XCTAssertEqual(after.normalizedFrame(for: changedRight), before.normalizedFrame(for: originalRight))
        XCTAssertEqual(after.displays, [changedRight, changedLeft])

        let source = try makeQuadrants()
        let renderedLeft = try WallpaperRenderer.render(image: source, display: changedLeft, geometry: after)
        let renderedRight = try WallpaperRenderer.render(image: source, display: changedRight, geometry: after)
        XCTAssertEqual(renderedLeft.width, 8)
        XCTAssertEqual(renderedLeft.height, 16)
        XCTAssertEqual(renderedRight.width, 8)
        XCTAssertEqual(renderedRight.height, 10)
        XCTAssertEqual(pixel(renderedLeft, x: 2, y: 2), .red)
        XCTAssertEqual(pixel(renderedLeft, x: 2, y: 13), .blue)
        XCTAssertEqual(pixel(renderedRight, x: 4, y: 1), .green)
        XCTAssertEqual(pixel(renderedRight, x: 4, y: 8), .yellow)
        XCTAssertThrowsError(try WallpaperRenderer.render(image: source, display: originalLeft, geometry: after))
    }

    func testManualCropsRemainIdenticalAfterSystemRearrangementAndDisplayReordering() throws {
        let originals = [
            display("left", x: -4, y: 0, width: 4, height: 8),
            display("right", x: 0, y: 0, width: 4, height: 8)
        ]
        let changed = [
            DisplayDescriptor(id: "right", name: "right", frame: CGRect(x: 0, y: 40, width: 80, height: 20), pixelWidth: 4, pixelHeight: 8),
            DisplayDescriptor(id: "left", name: "left", frame: CGRect(x: 300, y: -90, width: 10, height: 30), pixelWidth: 4, pixelHeight: 8)
        ]
        let calibrations = [
            "left": DisplayCalibration(scale: 1.5, offsetX: -2, offsetY: 3, referenceFrame: originals[0].frame),
            "right": DisplayCalibration(scale: 0.75, offsetX: 1, offsetY: -2, referenceFrame: originals[1].frame)
        ]
        let source = try makeImage(width: 16, height: 16) { x, y in
            Pixel(r: UInt8(x * 15), g: UInt8(y * 15), b: UInt8((x + y) * 7))
        }
        let size = CGSize(width: 16, height: 16)
        let before = try WallpaperGeometry(displays: originals, imageSize: size, calibrations: calibrations)
        let after = try WallpaperGeometry(displays: changed, imageSize: size, calibrations: calibrations)

        for current in changed {
            let original = try XCTUnwrap(originals.first { $0.id == current.id })
            let first = try WallpaperRenderer.render(image: source, display: original, geometry: before)
            let second = try WallpaperRenderer.render(image: source, display: current, geometry: after)
            let firstData = try XCTUnwrap(first.dataProvider?.data) as Data
            let secondData = try XCTUnwrap(second.dataProvider?.data) as Data
            XCTAssertEqual(secondData, firstData)
        }
    }

    func testCalibrationWithoutReferenceFrameFollowsSystemArrangement() throws {
        let left = display("left", x: -4, y: 0, width: 4, height: 8)
        let originalRight = display("right", x: 0, y: 0, width: 4, height: 8)
        let changedRight = display("right", x: 8, y: -4, width: 8, height: 12)
        let size = CGSize(width: 8, height: 8)
        let calibrations = ["left": DisplayCalibration(), "right": DisplayCalibration()]
        let before = try WallpaperGeometry(displays: [left, originalRight], imageSize: size, calibrations: calibrations)
        let after = try WallpaperGeometry(displays: [left, changedRight], imageSize: size, calibrations: calibrations)

        XCTAssertEqual(DisplayCalibration().baseFrame(for: changedRight), changedRight.frame)
        XCTAssertEqual(before.canvasSize, CGSize(width: 8, height: 8))
        XCTAssertEqual(after.canvasSize, CGSize(width: 20, height: 12))
        XCTAssertEqual(after.normalizedFrame(for: changedRight), CGRect(x: 12, y: 0, width: 8, height: 12))
    }

    func testManualCanvasUsesCapturedTopLeftAndDownwardOffsets() {
        let current = display("main", x: 1000, y: -2000, width: 500, height: 300)
        let reference = CGRect(x: -300, y: 50, width: 200, height: 100)
        let calibration = DisplayCalibration(scale: 1.5, offsetX: 20, offsetY: 30, referenceFrame: reference)

        XCTAssertEqual(calibration.baseFrame(for: current), reference)
        XCTAssertEqual(calibration.canvasFrame(for: current), CGRect(x: -280, y: -120, width: 300, height: 150))
    }

    func testNegativeAndStackedManualReferencesNormalizeFromTopLeft() throws {
        let left = display("left", x: 0, y: 0, width: 100, height: 100)
        let main = display("main", x: 100, y: 0, width: 100, height: 100)
        let upper = display("upper", x: 200, y: 0, width: 100, height: 100)
        let geometry = try WallpaperGeometry(
            displays: [left, main, upper], imageSize: CGSize(width: 4000, height: 3000),
            calibrations: [
                "left": .init(referenceFrame: CGRect(x: -1200, y: -300, width: 1200, height: 1600)),
                "main": .init(referenceFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080)),
                "upper": .init(referenceFrame: CGRect(x: 400, y: 1080, width: 1200, height: 800))
            ]
        )

        XCTAssertEqual(geometry.canvasSize, CGSize(width: 3120, height: 2180))
        XCTAssertEqual(geometry.normalizedFrame(for: left), CGRect(x: 0, y: 580, width: 1200, height: 1600))
        XCTAssertEqual(geometry.normalizedFrame(for: main), CGRect(x: 1200, y: 800, width: 1920, height: 1080))
        XCTAssertEqual(geometry.normalizedFrame(for: upper), CGRect(x: 1600, y: 0, width: 1200, height: 800))
    }

    func testMoveRetainsCapturedFrameAndSnapsUsingItsSize() {
        let current = display("main", x: 2000, y: 3000, width: 300, height: 200)
        let reference = CGRect(x: 0, y: 0, width: 100, height: 100)
        let start = DisplayCalibration(referenceFrame: reference)
        let other = CGRect(x: 200, y: -100, width: 100, height: 100)
        let result = CalibrationInteraction.move(
            display: current, start: start, translation: CGSize(width: 97, height: 3),
            others: [other], snapDistance: 5
        )

        XCTAssertEqual(result.calibration, .init(offsetX: 100, referenceFrame: reference))
        XCTAssertEqual(result.calibration.canvasFrame(for: current), CGRect(x: 100, y: -100, width: 100, height: 100))
        XCTAssertTrue(result.guides.contains(.init(axis: .vertical, coordinate: 200)))
        XCTAssertTrue(result.guides.contains(.init(axis: .horizontal, coordinate: -100)))
    }

    func testEveryResizeCornerUsesCapturedDimensionsAndKeepsOppositeCornerFixed() {
        let current = display("main", x: 2000, y: 3000, width: 500, height: 400)
        let reference = CGRect(x: -300, y: 50, width: 200, height: 100)
        let start = DisplayCalibration(offsetX: 10, offsetY: 20, referenceFrame: reference)
        let before = start.canvasFrame(for: current)

        for corner in CalibrationCorner.allCases {
            let movesLeft = corner == .topLeft || corner == .bottomLeft
            let movesTop = corner == .topLeft || corner == .topRight
            let result = CalibrationInteraction.resize(
                display: current, start: start, corner: corner,
                translation: CGSize(width: movesLeft ? -100 : 100, height: movesTop ? -50 : 50),
                others: [], snapDistance: 0
            )
            let after = result.calibration.canvasFrame(for: current)

            XCTAssertEqual(result.calibration.referenceFrame, reference)
            XCTAssertEqual(result.calibration.scale, 1.5, accuracy: 1e-10)
            XCTAssertEqual(after.width, 300, accuracy: 1e-8)
            XCTAssertEqual(after.height, 150, accuracy: 1e-8)
            XCTAssertEqual(movesLeft ? after.maxX : after.minX, movesLeft ? before.maxX : before.minX, accuracy: 1e-8)
            XCTAssertEqual(movesTop ? after.maxY : after.minY, movesTop ? before.maxY : before.minY, accuracy: 1e-8)
        }
    }

    func testManualResizeSnapAndOffsetLimitsUseCapturedDimensions() {
        let current = display("main", x: 2000, y: 3000, width: 500, height: 400)
        let reference = CGRect(x: 0, y: 0, width: 100, height: 100)
        let snapped = CalibrationInteraction.resize(
            display: current, start: .init(referenceFrame: reference), corner: .bottomRight,
            translation: CGSize(width: 47, height: 47),
            others: [CGRect(x: 150, y: 500, width: 100, height: 100)], snapDistance: 5
        )
        XCTAssertEqual(snapped.calibration.scale, 1.5, accuracy: 1e-10)
        XCTAssertEqual(snapped.calibration.referenceFrame, reference)
        XCTAssertEqual(snapped.calibration.canvasFrame(for: current).origin, CGPoint(x: 0, y: -100))
        XCTAssertTrue(snapped.guides.contains(.init(axis: .vertical, coordinate: 150)))

        let start = DisplayCalibration(offsetX: -9990, referenceFrame: reference)
        let before = start.canvasFrame(for: current)
        let limited = CalibrationInteraction.resize(
            display: current, start: start, corner: .topLeft,
            translation: CGSize(width: -500, height: -500), others: [], snapDistance: 0
        )
        let after = limited.calibration.canvasFrame(for: current)
        XCTAssertEqual(limited.calibration.referenceFrame, reference)
        XCTAssertEqual(limited.calibration.scale, 1.1, accuracy: 1e-10)
        XCTAssertEqual(limited.calibration.offsetX, -10_000, accuracy: 1e-10)
        XCTAssertEqual(after.maxX, before.maxX, accuracy: 1e-8)
        XCTAssertEqual(after.maxY, before.maxY, accuracy: 1e-8)
    }

    func testInvalidReferencesAreRejectedAndInteractionsRemoveThem() throws {
        let current = display("main", x: 0, y: 0, width: 100, height: 100)
        let invalidFrames: [CGRect] = [
            .null, .infinite, .zero,
            CGRect(x: 0, y: 0, width: -1, height: 1),
            CGRect(x: CGFloat.nan, y: 0, width: 1, height: 1),
            CGRect(x: 0, y: CGFloat.infinity, width: 1, height: 1),
            CGRect(x: 0, y: 0, width: 1, height: CGFloat.nan),
            CGRect(x: CGFloat.greatestFiniteMagnitude, y: 0, width: CGFloat.greatestFiniteMagnitude, height: 1)
        ]
        for reference in invalidFrames {
            let calibration = DisplayCalibration(scale: 1.25, offsetX: 20, offsetY: -30, referenceFrame: reference)
            XCTAssertFalse(calibration.isValid)
            XCTAssertThrowsError(try WallpaperGeometry(
                displays: [current], imageSize: CGSize(width: 100, height: 100),
                calibrations: [current.id: calibration]
            ))
            let expected = DisplayCalibration(scale: 1.25, offsetX: 20, offsetY: -30)
            XCTAssertEqual(calibration.canvasFrame(for: current), expected.canvasFrame(for: current))
            let moved = CalibrationInteraction.move(
                display: current, start: calibration, translation: CGSize(width: 10, height: 10),
                others: [], snapDistance: 0
            )
            XCTAssertEqual(moved.calibration, expected)
            XCTAssertTrue(moved.calibration.isValid)
            for corner in CalibrationCorner.allCases {
                let resized = CalibrationInteraction.resize(
                    display: current, start: calibration, corner: corner,
                    translation: CGSize(width: 10, height: 10), others: [], snapDistance: 0
                )
                XCTAssertEqual(resized.calibration, expected)
                XCTAssertTrue(resized.calibration.isValid)
            }
        }
    }

    func testValidReferenceIsRetainedWhenInteractionInputIsInvalid() {
        let current = display("main", x: 0, y: 0, width: 100, height: 100)
        let reference = CGRect(x: -300, y: 50, width: 200, height: 100)
        let start = DisplayCalibration(scale: .nan, offsetX: 20_000, offsetY: .infinity, referenceFrame: reference)
        let expected = DisplayCalibration(offsetX: 10_000, referenceFrame: reference)
        let moved = CalibrationInteraction.move(
            display: current, start: start, translation: CGSize(width: CGFloat.nan, height: 0),
            others: [], snapDistance: 0
        )
        XCTAssertEqual(moved.calibration, expected)
        for corner in CalibrationCorner.allCases {
            let resized = CalibrationInteraction.resize(
                display: current, start: start, corner: corner,
                translation: CGSize(width: CGFloat.infinity, height: 0), others: [], snapDistance: 0
            )
            XCTAssertEqual(resized.calibration, expected)
        }
    }

    func testManualReferenceDoesNotBypassRawDisplayValidation() throws {
        let reference = CGRect(x: -300, y: 50, width: 200, height: 100)
        let invalid = DisplayDescriptor(id: "main", name: "main", frame: .zero, pixelWidth: 100, pixelHeight: 100)
        let calibration = DisplayCalibration(referenceFrame: reference)

        XCTAssertThrowsError(try WallpaperGeometry(
            displays: [invalid], imageSize: CGSize(width: 100, height: 100),
            calibrations: [invalid.id: calibration]
        ))
        XCTAssertEqual(calibration.canvasFrame(for: invalid), .zero)
        let invalidOutput = DisplayDescriptor(id: "main", name: "main", frame: reference, pixelWidth: 0, pixelHeight: 100)
        XCTAssertThrowsError(try WallpaperGeometry(
            displays: [invalidOutput], imageSize: CGSize(width: 100, height: 100),
            calibrations: [invalidOutput.id: calibration]
        ))
    }
}
