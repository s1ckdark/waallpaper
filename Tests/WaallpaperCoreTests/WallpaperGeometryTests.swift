import XCTest
@testable import WaallpaperCore

final class WallpaperGeometryTests: XCTestCase {
    func testAdjacentDisplaysShareOneCanvas() throws {
        let left = display("left", x: 0, y: 0, width: 1920, height: 1080)
        let right = display("right", x: 1920, y: 0, width: 1920, height: 1080)
        let geometry = try WallpaperGeometry(displays: [left, right], imageSize: CGSize(width: 3840, height: 1080))

        XCTAssertEqual(geometry.canvasSize, CGSize(width: 3840, height: 1080))
        XCTAssertEqual(geometry.imageRect, CGRect(x: 0, y: 0, width: 3840, height: 1080))
        XCTAssertEqual(geometry.normalizedFrame(for: left), CGRect(x: 0, y: 0, width: 1920, height: 1080))
        XCTAssertEqual(geometry.normalizedFrame(for: right), CGRect(x: 1920, y: 0, width: 1920, height: 1080))
    }

    func testNegativeAndVerticalPositionsNormalizeFromTopLeft() throws {
        let left = display("left", x: -1200, y: -300, width: 1200, height: 1600)
        let main = display("main", x: 0, y: 0, width: 1920, height: 1080)
        let upper = display("upper", x: 400, y: 1080, width: 1200, height: 800)
        let geometry = try WallpaperGeometry(displays: [left, main, upper], imageSize: CGSize(width: 4000, height: 3000))

        XCTAssertEqual(geometry.canvasSize, CGSize(width: 3120, height: 2180))
        XCTAssertEqual(geometry.normalizedFrame(for: left), CGRect(x: 0, y: 580, width: 1200, height: 1600))
        XCTAssertEqual(geometry.normalizedFrame(for: main), CGRect(x: 1200, y: 800, width: 1920, height: 1080))
        XCTAssertEqual(geometry.normalizedFrame(for: upper), CGRect(x: 1600, y: 0, width: 1200, height: 800))
    }

    func testGapsRemainInCanvas() throws {
        let left = display("left", x: -200, y: 0, width: 100, height: 100)
        let right = display("right", x: 100, y: 0, width: 100, height: 100)
        let geometry = try WallpaperGeometry(displays: [left, right], imageSize: CGSize(width: 400, height: 100))

        XCTAssertEqual(geometry.canvasSize.width, 400)
        XCTAssertEqual(geometry.normalizedFrame(for: right).minX, 300)
        XCTAssertEqual(geometry.imageRect.width, 400)
    }

    func testFillAndHorizontalPanReachBothImageEdges() throws {
        let screen = display("main", x: 0, y: 0, width: 100, height: 100)
        let left = try geometry(screen, image: CGSize(width: 400, height: 200), placement: .init(horizontalOffset: -1))
        let center = try geometry(screen, image: CGSize(width: 400, height: 200))
        let right = try geometry(screen, image: CGSize(width: 400, height: 200), placement: .init(horizontalOffset: 1))

        XCTAssertEqual(left.imageRect, CGRect(x: 0, y: 0, width: 200, height: 100))
        XCTAssertEqual(center.imageRect.minX, -50)
        XCTAssertEqual(right.imageRect.minX, -100)
        XCTAssertEqual(right.imageRect.maxX, 100)
    }

    func testZoomAndVerticalPanKeepCanvasCovered() throws {
        let screen = display("main", x: 0, y: 0, width: 100, height: 100)
        let top = try geometry(screen, image: CGSize(width: 100, height: 200), placement: .init(zoom: 2, verticalOffset: -1))
        let bottom = try geometry(screen, image: CGSize(width: 100, height: 200), placement: .init(zoom: 2, verticalOffset: 1))

        XCTAssertEqual(top.imageRect, CGRect(x: -50, y: 0, width: 200, height: 400))
        XCTAssertEqual(bottom.imageRect, CGRect(x: -50, y: -300, width: 200, height: 400))
        for x in [-1.0, 0, 1] {
            for y in [-1.0, 0, 1] {
                let layout = try geometry(screen, image: CGSize(width: 100, height: 200), placement: .init(zoom: 2, horizontalOffset: x, verticalOffset: y))
                XCTAssertTrue(layout.imageRect.contains(CGRect(origin: .zero, size: layout.canvasSize)))
            }
        }
    }

    func testRetinaPixelsDoNotChangeLogicalCrop() throws {
        let standard = display("standard", x: 0, y: 0, width: 1920, height: 1080)
        let retina = DisplayDescriptor(id: "retina", name: "retina", frame: standard.frame, pixelWidth: 3840, pixelHeight: 2160)
        let first = try geometry(standard, image: CGSize(width: 4000, height: 2000))
        let second = try geometry(retina, image: CGSize(width: 4000, height: 2000))
        XCTAssertEqual(first.canvasSize, second.canvasSize)
        XCTAssertEqual(first.imageRect, second.imageRect)
        XCTAssertEqual(first.normalizedFrame(for: standard), second.normalizedFrame(for: retina))
    }

    func testMalformedInputThrows() throws {
        let valid = display("main", x: 0, y: 0, width: 100, height: 100)
        let size = CGSize(width: 100, height: 100)
        XCTAssertThrowsError(try WallpaperGeometry(displays: [], imageSize: size))
        XCTAssertThrowsError(try WallpaperGeometry(displays: [valid, valid], imageSize: size))
        for malformedSize in [CGSize.zero, CGSize(width: -1, height: 1), CGSize(width: CGFloat.infinity, height: 1), CGSize(width: CGFloat.nan, height: 1)] {
            XCTAssertThrowsError(try WallpaperGeometry(displays: [valid], imageSize: malformedSize))
        }
        for placement in [WallpaperPlacement(zoom: 0.9), .init(zoom: .infinity), .init(zoom: .nan), .init(horizontalOffset: 1.1), .init(verticalOffset: -.infinity)] {
            XCTAssertThrowsError(try WallpaperGeometry(displays: [valid], imageSize: size, placement: placement))
        }
        let invalidFrames = [CGRect(x: 0, y: 0, width: 0, height: 1), CGRect(x: 0, y: 0, width: -1, height: 1), CGRect(x: CGFloat.infinity, y: 0, width: 1, height: 1)]
        for frame in invalidFrames {
            let invalid = DisplayDescriptor(id: "bad", name: "bad", frame: frame, pixelWidth: 100, pixelHeight: 100)
            XCTAssertThrowsError(try WallpaperGeometry(displays: [invalid], imageSize: size))
        }
        for pixels in [(0, 1), (1, -1), (Int.max, 1), (16_384, 16_384)] {
            let invalid = DisplayDescriptor(id: "bad", name: "bad", frame: valid.frame, pixelWidth: pixels.0, pixelHeight: pixels.1)
            XCTAssertThrowsError(try WallpaperGeometry(displays: [invalid], imageSize: size))
        }
    }

    private func geometry(_ display: DisplayDescriptor, image: CGSize, placement: WallpaperPlacement = .init()) throws -> WallpaperGeometry {
        try WallpaperGeometry(displays: [display], imageSize: image, placement: placement)
    }
}

func display(_ id: String, x: CGFloat, y: CGFloat, width: Int, height: Int) -> DisplayDescriptor {
    DisplayDescriptor(id: id, name: id, frame: CGRect(x: x, y: y, width: CGFloat(width), height: CGFloat(height)), pixelWidth: width, pixelHeight: height)
}
