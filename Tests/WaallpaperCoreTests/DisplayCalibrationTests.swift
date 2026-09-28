import XCTest
@testable import WaallpaperCore

final class DisplayCalibrationTests: XCTestCase {
    func testScaleKeepsTopLeftAnchorAndOriginalDisplaySnapshot() throws {
        let left = display("left", x: -100, y: 0, width: 100, height: 100)
        let right = display("right", x: 0, y: 0, width: 100, height: 100)
        let geometry = try WallpaperGeometry(
            displays: [left, right], imageSize: CGSize(width: 300, height: 200),
            calibrations: [right.id: .init(scale: 2)]
        )

        XCTAssertEqual(geometry.canvasSize, CGSize(width: 300, height: 200))
        XCTAssertEqual(geometry.imageRect, CGRect(x: 0, y: 0, width: 300, height: 200))
        XCTAssertEqual(geometry.normalizedFrame(for: left), CGRect(x: 0, y: 0, width: 100, height: 100))
        XCTAssertEqual(geometry.normalizedFrame(for: right), CGRect(x: 100, y: 0, width: 200, height: 200))
        XCTAssertEqual(geometry.displays, [left, right])
        XCTAssertEqual(geometry.displays[1].pixelWidth, 100)
        XCTAssertEqual(geometry.displays[1].pixelHeight, 100)
    }

    func testPositiveOffsetsMoveDisplayRightAndDown() throws {
        let left = display("left", x: 0, y: 0, width: 100, height: 100)
        let right = display("right", x: 100, y: 0, width: 100, height: 100)
        let geometry = try WallpaperGeometry(
            displays: [left, right], imageSize: CGSize(width: 220, height: 130),
            calibrations: [right.id: .init(offsetX: 20, offsetY: 30)]
        )

        XCTAssertEqual(geometry.canvasSize, CGSize(width: 220, height: 130))
        XCTAssertEqual(geometry.normalizedFrame(for: left), CGRect(x: 0, y: 0, width: 100, height: 100))
        XCTAssertEqual(geometry.normalizedFrame(for: right), CGRect(x: 120, y: 30, width: 100, height: 100))
    }

    func testReducedScaleAndNegativeOffsetsUseSameTopLeftConvention() throws {
        let left = display("left", x: -100, y: -50, width: 100, height: 100)
        let right = display("right", x: 0, y: -50, width: 100, height: 100)
        let geometry = try WallpaperGeometry(
            displays: [left, right], imageSize: CGSize(width: 140, height: 120),
            calibrations: [right.id: .init(scale: 0.5, offsetX: -10, offsetY: -20)]
        )

        XCTAssertEqual(geometry.canvasSize, CGSize(width: 140, height: 120))
        XCTAssertEqual(geometry.normalizedFrame(for: left), CGRect(x: 0, y: 20, width: 100, height: 100))
        XCTAssertEqual(geometry.normalizedFrame(for: right), CGRect(x: 90, y: 0, width: 50, height: 50))
    }

    func testIdentityCalibrationAndUnusedRecordsPreserveExistingGeometry() throws {
        let left = display("left", x: -1200, y: -300, width: 1200, height: 1600)
        let right = display("right", x: 0, y: 0, width: 1920, height: 1080)
        let size = CGSize(width: 4000, height: 3000)
        let placement = WallpaperPlacement(zoom: 1.5, horizontalOffset: -0.2, verticalOffset: 0.3)
        let original = try WallpaperGeometry(displays: [left, right], imageSize: size, placement: placement)
        let calibrated = try WallpaperGeometry(
            displays: [left, right], imageSize: size, placement: placement,
            calibrations: [left.id: .init(), right.id: .init(), "disconnected": .init(scale: .nan)]
        )

        XCTAssertEqual(original.canvasSize, calibrated.canvasSize)
        XCTAssertEqual(original.imageRect, calibrated.imageRect)
        XCTAssertEqual(original.displays, calibrated.displays)
        XCTAssertEqual(original.normalizedFrame(for: left), calibrated.normalizedFrame(for: left))
        XCTAssertEqual(original.normalizedFrame(for: right), calibrated.normalizedFrame(for: right))
    }

    func testInvalidAppliedCalibrationIsRejected() throws {
        let screen = display("main", x: 0, y: 0, width: 100, height: 100)
        let invalid: [DisplayCalibration] = [
            .init(scale: 0.249), .init(scale: 4.001), .init(scale: .nan), .init(scale: .infinity),
            .init(offsetX: -10_001), .init(offsetX: .nan), .init(offsetX: .infinity),
            .init(offsetY: 10_001), .init(offsetY: .nan), .init(offsetY: -.infinity)
        ]
        for calibration in invalid {
            XCTAssertFalse(calibration.isValid)
            XCTAssertThrowsError(try WallpaperGeometry(
                displays: [screen], imageSize: CGSize(width: 100, height: 100),
                calibrations: [screen.id: calibration]
            )) { error in
                guard case WallpaperError.invalidGeometry = error else {
                    return XCTFail("Expected actionable layout error, received \(error)")
                }
            }
        }
    }

    func testCalibrationRangeBoundariesAreAccepted() throws {
        let screen = display("main", x: 0, y: 0, width: 100, height: 100)
        for scale in [DisplayCalibration.scaleRange.lowerBound, DisplayCalibration.scaleRange.upperBound] {
            for offset in [DisplayCalibration.offsetRange.lowerBound, DisplayCalibration.offsetRange.upperBound] {
                let calibration = DisplayCalibration(scale: scale, offsetX: offset, offsetY: offset)
                XCTAssertTrue(calibration.isValid)
                let geometry = try WallpaperGeometry(displays: [screen], imageSize: CGSize(width: 100, height: 100), calibrations: [screen.id: calibration])
                XCTAssertEqual(geometry.canvasSize, CGSize(width: 100 * scale, height: 100 * scale))
            }
        }
    }

    func testCalibrationSettingsCodableRoundTripAndValidationAfterDecode() throws {
        let settings: [String: DisplayCalibration] = [
            "display-a": .init(scale: 1.25, offsetX: -160.5, offsetY: 45),
            "display-b": .init()
        ]
        let encoded = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode([String: DisplayCalibration].self, from: encoded)
        XCTAssertEqual(decoded, settings)
        XCTAssertTrue(decoded.values.allSatisfy(\.isValid))

        let invalidRecord = Data(#"{"scale":99,"offsetX":0,"offsetY":0}"#.utf8)
        let invalid = try JSONDecoder().decode(DisplayCalibration.self, from: invalidRecord)
        XCTAssertFalse(invalid.isValid)
    }

    func testCalibratedMixedDPIDisplaysKeepTheirOutputPixelDimensions() throws {
        let source = try makeQuadrants(width: 16, height: 8)
        let left = DisplayDescriptor(id: "retina", name: "retina", frame: CGRect(x: 0, y: 0, width: 8, height: 8), pixelWidth: 16, pixelHeight: 16)
        let right = display("standard", x: 8, y: 0, width: 4, height: 4)
        let geometry = try WallpaperGeometry(
            displays: [left, right], imageSize: CGSize(width: 16, height: 8),
            calibrations: [right.id: .init(scale: 2, offsetY: -4)]
        )
        XCTAssertEqual(geometry.normalizedFrame(for: left).maxX, geometry.normalizedFrame(for: right).minX)
        XCTAssertEqual(geometry.normalizedFrame(for: left).height, geometry.normalizedFrame(for: right).height)
        let leftImage = try WallpaperRenderer.render(image: source, display: left, geometry: geometry)
        let rightImage = try WallpaperRenderer.render(image: source, display: right, geometry: geometry)

        XCTAssertEqual(leftImage.width, 16)
        XCTAssertEqual(leftImage.height, 16)
        XCTAssertEqual(rightImage.width, 4)
        XCTAssertEqual(rightImage.height, 4)
        XCTAssertEqual(pixel(leftImage, x: 3, y: 3), .red)
        XCTAssertEqual(pixel(leftImage, x: 3, y: 12), .blue)
        XCTAssertEqual(pixel(rightImage, x: 2, y: 0), .green)
        XCTAssertEqual(pixel(rightImage, x: 2, y: 3), .yellow)
    }

    func testCalibratedOffsetsSelectTheCorrespondingImageRegions() throws {
        let source = try makeImage(width: 12, height: 8) { x, y in
            if x < 4 && y < 4 { return .red }
            if x >= 8 && y >= 4 { return .blue }
            return .green
        }
        let left = display("left", x: 0, y: 0, width: 4, height: 4)
        let right = display("right", x: 4, y: 0, width: 4, height: 4)
        let geometry = try WallpaperGeometry(
            displays: [left, right], imageSize: CGSize(width: 12, height: 8),
            calibrations: [right.id: .init(offsetX: 4, offsetY: 4)]
        )
        let leftImage = try WallpaperRenderer.render(image: source, display: left, geometry: geometry)
        let rightImage = try WallpaperRenderer.render(image: source, display: right, geometry: geometry)
        XCTAssertEqual(pixel(leftImage, x: 1, y: 1), .red)
        XCTAssertEqual(pixel(rightImage, x: 2, y: 2), .blue)
    }

    func testIdentityCalibrationPreservesRenderedPixels() throws {
        let source = try makeQuadrants()
        let screen = display("main", x: -4, y: -3, width: 8, height: 8)
        let original = try WallpaperGeometry(displays: [screen], imageSize: CGSize(width: 8, height: 8))
        let calibrated = try WallpaperGeometry(displays: [screen], imageSize: CGSize(width: 8, height: 8), calibrations: [screen.id: .init()])
        let originalImage = try WallpaperRenderer.render(image: source, display: screen, geometry: original)
        let calibratedImage = try WallpaperRenderer.render(image: source, display: screen, geometry: calibrated)
        let originalData = try XCTUnwrap(originalImage.dataProvider?.data) as Data
        let calibratedData = try XCTUnwrap(calibratedImage.dataProvider?.data) as Data
        XCTAssertEqual(originalData, calibratedData)
    }
}
