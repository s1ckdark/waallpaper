import CoreGraphics
import XCTest
@testable import WaallpaperCore

final class AlignmentPatternTests: XCTestCase {
    func testOutputDimensionsPreviewCapAndOpaqueBackground() throws {
        let display = screen("retina", x: 0, y: 0, width: 400, height: 300, pixels: CGSize(width: 800, height: 600))
        let geometry = try layout([display])
        let full = try AlignmentPattern.render(display: display, geometry: geometry)
        XCTAssertEqual(full.width, 800)
        XCTAssertEqual(full.height, 600)
        XCTAssertEqual(sample(full, x: 70, y: 90).alpha, 255)
        let preview = try AlignmentPattern.render(display: display, geometry: geometry, maxPixelDimension: 200)
        XCTAssertEqual(preview.width, 200)
        XCTAssertEqual(preview.height, 150)
        let uncapped = try AlignmentPattern.render(display: display, geometry: geometry, maxPixelDimension: 2_000)
        XCTAssertEqual(uncapped.width, 800)
        XCTAssertThrowsError(try AlignmentPattern.render(display: display, geometry: geometry, maxPixelDimension: 0))
    }

    func testHorizontalSeamSharesGridCrosshairAndDiagonalCoordinates() throws {
        let left = screen("left", x: -400, y: 0, width: 400, height: 300)
        let right = screen("right", x: 0, y: 0, width: 600, height: 300)
        let geometry = try layout([left, right])
        let first = try AlignmentPattern.render(display: left, geometry: geometry)
        let second = try AlignmentPattern.render(display: right, geometry: geometry)
        for y in [30, 75, 149, 150, 220, 298] {
            XCTAssertEqual(sample(first, x: 399, y: y), sample(second, x: 0, y: y), "Seam row \(y)")
        }
        XCTAssertTrue(sample(first, x: 399, y: 150).isCyan)
        XCTAssertTrue(sample(second, x: 0, y: 150).isCyan)
        XCTAssertTrue(sample(first, x: 399, y: 120).isWarm)
        XCTAssertTrue(sample(second, x: 0, y: 120).isWarm)
    }

    func testVerticalArrangementKeepsTopLeftDiagonalOrientationAndSeam() throws {
        let top = screen("top", x: 0, y: 300, width: 600, height: 300)
        let bottom = screen("bottom", x: 0, y: 0, width: 600, height: 300)
        let geometry = try layout([bottom, top])
        let upper = try AlignmentPattern.render(display: top, geometry: geometry)
        let lower = try AlignmentPattern.render(display: bottom, geometry: geometry)
        XCTAssertTrue(sample(upper, x: 10, y: 10).isWarm)
        XCTAssertFalse(sample(upper, x: 10, y: 290).isWarm)
        XCTAssertTrue(sample(lower, x: 590, y: 290).isWarm)
        XCTAssertFalse(sample(lower, x: 590, y: 10).isWarm)
        for x in [50, 120, 450] {
            XCTAssertEqual(sample(upper, x: x, y: 299), sample(lower, x: x, y: 0))
            XCTAssertTrue(sample(upper, x: x, y: 299).isCyan)
        }
    }

    func testMixedPixelScalesAndCalibrationUseSharedWorldPosition() throws {
        let left = screen("left", x: 0, y: 0, width: 400, height: 300, pixels: CGSize(width: 800, height: 600))
        let right = screen("right", x: 400, y: 0, width: 600, height: 300)
        let geometry = try layout([left, right], calibrations: ["right": .init(scale: 0.5, offsetY: 30)])
        let first = try AlignmentPattern.render(display: left, geometry: geometry)
        let second = try AlignmentPattern.render(display: right, geometry: geometry)
        XCTAssertEqual(first.width, 800)
        XCTAssertEqual(first.height, 600)
        XCTAssertEqual(second.width, 600)
        XCTAssertEqual(second.height, 300)
        // Shared y=150 appears at 300px on the 2x left display and at 240px on
        // the right display, whose corrected frame starts at y=30 and is 150pt tall.
        XCTAssertTrue(sample(first, x: 200, y: 300).isCyan)
        XCTAssertTrue(sample(second, x: 20, y: 240).isCyan)
        XCTAssertFalse(sample(second, x: 20, y: 150).isCyan)
        // A 150-point grid remains in world coordinates: x=450 is 100 output
        // pixels into the calibrated right display, rather than a fresh local grid.
        XCTAssertGreaterThan(sample(second, x: 100, y: 20).green, sample(second, x: 50, y: 20).green)
    }

    func testPatternDoesNotDependOnWallpaperSizeOrPanAndZoom() throws {
        let display = screen("main", x: 0, y: 0, width: 500, height: 300)
        let firstGeometry = try layout([display])
        let secondGeometry = try WallpaperGeometry(displays: [display], imageSize: CGSize(width: 3_000, height: 800),
                                                  placement: .init(zoom: 3, horizontalOffset: 0.5, verticalOffset: -0.5))
        let first = try AlignmentPattern.render(display: display, geometry: firstGeometry)
        let second = try AlignmentPattern.render(display: display, geometry: secondGeometry)
        XCTAssertEqual(first.dataProvider?.data as Data?, second.dataProvider?.data as Data?)
    }

    func testLargeArrangementKeepsRenderingBoundedAndRejectsStaleDisplay() throws {
        let display = screen("wide", x: 0, y: 0, width: 1_000_000, height: 500_000,
                             pixels: CGSize(width: 800, height: 400))
        let geometry = try layout([display])
        let image = try AlignmentPattern.render(display: display, geometry: geometry, maxPixelDimension: 200)
        XCTAssertEqual(image.width, 200)
        XCTAssertEqual(image.height, 100)
        let stale = screen("wide", x: 10, y: 0, width: 1_000_000, height: 500_000,
                           pixels: CGSize(width: 800, height: 400))
        XCTAssertThrowsError(try AlignmentPattern.render(display: stale, geometry: geometry))
    }

    private func screen(_ id: String, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat,
                        pixels: CGSize? = nil) -> DisplayDescriptor {
        DisplayDescriptor(id: id, name: id, frame: CGRect(x: x, y: y, width: width, height: height),
                          pixelWidth: Int(pixels?.width ?? width), pixelHeight: Int(pixels?.height ?? height))
    }

    private func layout(_ displays: [DisplayDescriptor], calibrations: [String: DisplayCalibration] = [:]) throws -> WallpaperGeometry {
        try WallpaperGeometry(displays: displays, imageSize: CGSize(width: 1, height: 1), calibrations: calibrations)
    }

    private struct Color: Equatable {
        let red: UInt8
        let green: UInt8
        let blue: UInt8
        let alpha: UInt8
        var isCyan: Bool { red < 80 && green > 200 && blue > 220 }
        var isWarm: Bool { red > 220 && green > 140 && green < 210 && blue < 100 }
    }

    private func sample(_ image: CGImage, x: Int, y: Int) -> Color {
        let bytes = CFDataGetBytePtr(image.dataProvider!.data!)!
        let offset = y * image.bytesPerRow + x * 4
        return Color(red: bytes[offset], green: bytes[offset + 1], blue: bytes[offset + 2], alpha: bytes[offset + 3])
    }
}
