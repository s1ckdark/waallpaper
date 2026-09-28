import CoreGraphics
import XCTest
@testable import WaallpaperCore

final class WallpaperRendererTests: XCTestCase {
    func testHorizontalCropsPreserveColoredQuadrantOrientation() throws {
        let source = try makeQuadrants()
        let left = display("left", x: -4, y: 0, width: 4, height: 8)
        let right = display("right", x: 0, y: 0, width: 4, height: 8)
        let geometry = try WallpaperGeometry(displays: [left, right], imageSize: CGSize(width: 8, height: 8))
        let leftImage = try WallpaperRenderer.render(image: source, display: left, geometry: geometry)
        let rightImage = try WallpaperRenderer.render(image: source, display: right, geometry: geometry)

        XCTAssertEqual(pixel(leftImage, x: 1, y: 1), .red)
        XCTAssertEqual(pixel(leftImage, x: 1, y: 6), .blue)
        XCTAssertEqual(pixel(rightImage, x: 2, y: 1), .green)
        XCTAssertEqual(pixel(rightImage, x: 2, y: 6), .yellow)
    }

    func testVerticalCropsMapMacOSUpperScreenToImageTop() throws {
        let source = try makeQuadrants()
        let bottom = display("bottom", x: 0, y: -4, width: 8, height: 4)
        let top = display("top", x: 0, y: 0, width: 8, height: 4)
        let geometry = try WallpaperGeometry(displays: [bottom, top], imageSize: CGSize(width: 8, height: 8))
        let topImage = try WallpaperRenderer.render(image: source, display: top, geometry: geometry)
        let bottomImage = try WallpaperRenderer.render(image: source, display: bottom, geometry: geometry)

        XCTAssertEqual(pixel(topImage, x: 1, y: 1), .red)
        XCTAssertEqual(pixel(topImage, x: 6, y: 1), .green)
        XCTAssertEqual(pixel(bottomImage, x: 1, y: 1), .blue)
        XCTAssertEqual(pixel(bottomImage, x: 6, y: 1), .yellow)
    }

    func testPhysicalOutputResolutionDoesNotChangeCrops() throws {
        let source = try makeQuadrants()
        let retina = DisplayDescriptor(id: "retina", name: "retina", frame: CGRect(x: 0, y: 0, width: 4, height: 8), pixelWidth: 8, pixelHeight: 16)
        let standard = display("standard", x: 4, y: 0, width: 4, height: 8)
        let geometry = try WallpaperGeometry(displays: [retina, standard], imageSize: CGSize(width: 8, height: 8))
        let first = try WallpaperRenderer.render(image: source, display: retina, geometry: geometry)
        let second = try WallpaperRenderer.render(image: source, display: standard, geometry: geometry)

        XCTAssertEqual(first.width, 8)
        XCTAssertEqual(first.height, 16)
        XCTAssertEqual(second.width, 4)
        XCTAssertEqual(second.height, 8)
        XCTAssertEqual(pixel(first, x: 2, y: 2), .red)
        XCTAssertEqual(pixel(first, x: 2, y: 13), .blue)
        XCTAssertEqual(pixel(second, x: 2, y: 1), .green)
        XCTAssertEqual(pixel(second, x: 2, y: 6), .yellow)
    }

    func testGapsSkipCorrespondingSourcePixels() throws {
        let source = try makeImage(width: 8, height: 2) { x, _ in Pixel(r: UInt8(x * 30), g: 0, b: 0) }
        let left = display("left", x: 0, y: 0, width: 2, height: 2)
        let right = display("right", x: 6, y: 0, width: 2, height: 2)
        let geometry = try WallpaperGeometry(displays: [left, right], imageSize: CGSize(width: 8, height: 2))
        let first = try WallpaperRenderer.render(image: source, display: left, geometry: geometry)
        let second = try WallpaperRenderer.render(image: source, display: right, geometry: geometry)
        XCTAssertEqual(pixel(first, x: 0, y: 0).r, 0)
        XCTAssertEqual(pixel(first, x: 1, y: 0).r, 30)
        XCTAssertEqual(pixel(second, x: 0, y: 0).r, 180)
        XCTAssertEqual(pixel(second, x: 1, y: 0).r, 210)
    }

    func testZoomAndPanRenderChosenCorner() throws {
        let source = try makeQuadrants()
        let screen = display("main", x: 0, y: 0, width: 4, height: 4)
        let geometry = try WallpaperGeometry(displays: [screen], imageSize: CGSize(width: 8, height: 8), placement: .init(zoom: 2, horizontalOffset: 1, verticalOffset: -1))
        let result = try WallpaperRenderer.render(image: source, display: screen, geometry: geometry)
        XCTAssertEqual(pixel(result, x: 1, y: 1), .green)
        XCTAssertEqual(pixel(result, x: 2, y: 2), .green)
    }

    func testPreviewPreservesAspectRatioAndDoesNotUpscale() throws {
        let source = try makeQuadrants()
        let screen = display("main", x: 0, y: 0, width: 80, height: 40)
        let geometry = try WallpaperGeometry(displays: [screen], imageSize: CGSize(width: 8, height: 8))
        let preview = try WallpaperRenderer.render(image: source, display: screen, geometry: geometry, maxPixelDimension: 20)
        XCTAssertEqual(preview.width, 20)
        XCTAssertEqual(preview.height, 10)
        let full = try WallpaperRenderer.render(image: source, display: screen, geometry: geometry, maxPixelDimension: 800)
        XCTAssertEqual(full.width, 80)
        XCTAssertThrowsError(try WallpaperRenderer.render(image: source, display: screen, geometry: geometry, maxPixelDimension: 0))
    }

    func testStaleDisplayOrImageIsRejected() throws {
        let source = try makeQuadrants()
        let screen = display("main", x: 0, y: 0, width: 8, height: 8)
        let geometry = try WallpaperGeometry(displays: [screen], imageSize: CGSize(width: 8, height: 8))
        let stale = display("main", x: 1, y: 0, width: 8, height: 8)
        XCTAssertThrowsError(try WallpaperRenderer.render(image: source, display: stale, geometry: geometry))
        let wrongSize = try makeImage(width: 2, height: 2) { _, _ in .red }
        XCTAssertThrowsError(try WallpaperRenderer.render(image: wrongSize, display: screen, geometry: geometry))
    }

    func testExtremeFiniteZoomCannotReachRasterizer() throws {
        let source = try makeQuadrants()
        let screen = display("main", x: 0, y: 0, width: 8, height: 8)
        let geometry = try WallpaperGeometry(displays: [screen], imageSize: CGSize(width: 8, height: 8), placement: .init(zoom: 1e100))
        XCTAssertThrowsError(try WallpaperRenderer.render(image: source, display: screen, geometry: geometry))
    }

    func testTransparencyFlattensOntoOpaqueBlack() throws {
        // The second source pixel is 50% red in premultiplied RGBA storage.
        let bytes: [UInt8] = [0, 0, 0, 0, 128, 0, 0, 128]
        let provider = try XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData))
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let source = try XCTUnwrap(CGImage(width: 2, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 8, space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let screen = display("main", x: 0, y: 0, width: 2, height: 1)
        let geometry = try WallpaperGeometry(displays: [screen], imageSize: CGSize(width: 2, height: 1))
        let result = try WallpaperRenderer.render(image: source, display: screen, geometry: geometry)

        XCTAssertEqual(pixel(result, x: 0, y: 0), Pixel(r: 0, g: 0, b: 0))
        XCTAssertEqual(pixel(result, x: 1, y: 0), Pixel(r: 128, g: 0, b: 0))
        let outputData = try XCTUnwrap(result.dataProvider?.data)
        let outputBytes = try XCTUnwrap(CFDataGetBytePtr(outputData))
        XCTAssertEqual(outputBytes[3], 255)
        XCTAssertEqual(outputBytes[7], 255)
    }
}

struct Pixel: Equatable {
    let r: UInt8
    let g: UInt8
    let b: UInt8
    static let red = Pixel(r: 255, g: 0, b: 0)
    static let green = Pixel(r: 0, g: 255, b: 0)
    static let blue = Pixel(r: 0, g: 0, b: 255)
    static let yellow = Pixel(r: 255, g: 255, b: 0)
}

func makeQuadrants(width: Int = 8, height: Int = 8) throws -> CGImage {
    try makeImage(width: width, height: height) { x, y in
        if y < height / 2 { return x < width / 2 ? .red : .green }
        return x < width / 2 ? .blue : .yellow
    }
}

func makeImage(width: Int, height: Int, color: (Int, Int) -> Pixel) throws -> CGImage {
    var bytes: [UInt8] = []
    for y in 0..<height {
        for x in 0..<width {
            let p = color(x, y)
            bytes.append(contentsOf: [p.r, p.g, p.b, 255])
        }
    }
    let data = Data(bytes) as CFData
    let provider = try XCTUnwrap(CGDataProvider(data: data))
    let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
    return try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
}

func pixel(_ image: CGImage, x: Int, y: Int) -> Pixel {
    let data = image.dataProvider!.data!
    let bytes = CFDataGetBytePtr(data)!
    let offset = y * image.bytesPerRow + x * 4
    return Pixel(r: bytes[offset], g: bytes[offset + 1], b: bytes[offset + 2])
}
