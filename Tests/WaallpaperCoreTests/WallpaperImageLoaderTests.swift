import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import WaallpaperCore

final class WallpaperImageLoaderTests: XCTestCase {
    func testLoadsPNGAtOriginalDimensions() throws {
        try withTemporaryDirectory { directory in
            let url = directory.appendingPathComponent("quadrants.png")
            try writeImage(try makeQuadrants(), to: url, type: UTType.png.identifier)
            let image = try WallpaperImageLoader.load(url: url)
            XCTAssertEqual(image.width, 8)
            XCTAssertEqual(image.height, 8)
            let screen = display("test", x: 0, y: 0, width: 8, height: 8)
            let geometry = try WallpaperGeometry(displays: [screen], imageSize: CGSize(width: 8, height: 8))
            let result = try WallpaperRenderer.render(image: image, display: screen, geometry: geometry)
            XCTAssertEqual(pixel(result, x: 1, y: 1), .red)
            XCTAssertEqual(pixel(result, x: 6, y: 6), .yellow)
        }
    }

    func testAppliesEXIFRotationBeforeReturningImage() throws {
        try withTemporaryDirectory { directory in
            let url = directory.appendingPathComponent("rotated.tiff")
            let source = try makeQuadrants(width: 8, height: 4)
            try writeImage(source, to: url, type: UTType.tiff.identifier, properties: [kCGImagePropertyOrientation: 6])
            let image = try WallpaperImageLoader.load(url: url)
            XCTAssertEqual(image.width, 4)
            XCTAssertEqual(image.height, 8)
            let screen = display("test", x: 0, y: 0, width: 4, height: 8)
            let geometry = try WallpaperGeometry(displays: [screen], imageSize: CGSize(width: 4, height: 8))
            let result = try WallpaperRenderer.render(image: image, display: screen, geometry: geometry)
            XCTAssertEqual(pixel(result, x: 0, y: 1), .blue)
            XCTAssertEqual(pixel(result, x: 3, y: 1), .red)
            XCTAssertEqual(pixel(result, x: 0, y: 6), .yellow)
            XCTAssertEqual(pixel(result, x: 3, y: 6), .green)
        }
    }

    func testBoundsDecodeDimension() throws {
        try withTemporaryDirectory { directory in
            let url = directory.appendingPathComponent("wide.png")
            let source = try makeImage(width: 20_000, height: 2) { _, _ in .red }
            try writeImage(source, to: url, type: UTType.png.identifier)
            let image = try WallpaperImageLoader.load(url: url)
            XCTAssertLessThanOrEqual(image.width, 16_384)
            XCTAssertGreaterThan(image.height, 0)
        }
    }

    func testRejectsMissingUnsupportedAndRemoteInputs() throws {
        try withTemporaryDirectory { directory in
            XCTAssertThrowsError(try WallpaperImageLoader.load(url: directory.appendingPathComponent("missing.png")))
            let invalid = directory.appendingPathComponent("invalid.png")
            try Data("not an image".utf8).write(to: invalid)
            XCTAssertThrowsError(try WallpaperImageLoader.load(url: invalid))
            XCTAssertThrowsError(try WallpaperImageLoader.load(url: URL(string: "https://example.com/image.png")!))
        }
    }

    private func writeImage(_ image: CGImage, to url: URL, type: String, properties: [CFString: Any] = [:]) throws {
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, type as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }

    private func withTemporaryDirectory(_ action: (URL) throws -> Void) throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("WaallpaperTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: url) }
        try action(url)
    }
}
