import XCTest
import WaallpaperCore
@testable import Waallpaper

@MainActor
final class ManualLayoutPreferencesTests: XCTestCase {
    func testManualLayoutSurvivesSystemRearrangementReconnectAndRestart() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var displays = [screen("a", x: 0), screen("b", x: 100)]
        let model = WallpaperModel(storageURL: root, displayProvider: { displays })
        model.setCalibration(.init(scale: 1.2, offsetX: 10), for: "b")
        model.displayLayoutMode = .manual
        model.setCalibration(.init(scale: 0.8, offsetX: 30, offsetY: -20), for: "b")
        let manual = try XCTUnwrap(model.geometry)
        let originalFrames = displays.map { manual.normalizedFrame(for: $0) }
        let storedManual = model.manualCalibrations

        displays = [screen("a", x: 3000, y: -1000, size: 50), screen("b", x: -300, y: 500, size: 50)]
        model.refreshDisplays()
        let moved = try XCTUnwrap(model.geometry)
        XCTAssertEqual(displays.map { moved.normalizedFrame(for: $0) }, originalFrames)
        XCTAssertEqual(moved.displays, displays)

        displays.removeLast()
        model.refreshDisplays()
        XCTAssertEqual(model.manualCalibrations, storedManual)
        displays.append(screen("b", x: 999, y: 999, size: 50))
        model.refreshDisplays()
        XCTAssertEqual(model.manualCalibrations, storedManual)

        let reopened = WallpaperModel(storageURL: root, displayProvider: { displays })
        XCTAssertEqual(reopened.displayLayoutMode, .manual)
        XCTAssertEqual(reopened.manualCalibrations, storedManual)
        let restored = try XCTUnwrap(reopened.geometry)
        XCTAssertEqual(displays.map { restored.normalizedFrame(for: $0) }, originalFrames)

        reopened.displayLayoutMode = .system
        XCTAssertEqual(reopened.calibration(for: "b"), .init(scale: 1.2, offsetX: 10))
        reopened.displayLayoutMode = .manual
        XCTAssertEqual(reopened.manualCalibrations, storedManual)
    }

    func testImportingSystemLayoutResetsOnlyManualSettings() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let displays = [screen("a", x: 0), screen("b", x: 100)]
        let model = WallpaperModel(storageURL: root, displayProvider: { displays })
        let correction = DisplayCalibration(scale: 1.3, offsetY: 40)
        model.setCalibration(correction, for: "b")
        model.displayLayoutMode = .manual
        model.setCalibration(.init(scale: 0.7, offsetX: -500), for: "b")
        model.resetAllCalibrations()
        XCTAssertEqual(model.displayLayoutMode, .manual)
        XCTAssertEqual(model.calibration(for: "b"), .init(referenceFrame: displays[1].frame))
        model.displayLayoutMode = .system
        XCTAssertEqual(model.calibration(for: "b"), correction)
    }

    private func screen(_ id: String, x: CGFloat, y: CGFloat = 0, size: CGFloat = 100) -> DisplayDescriptor {
        .init(id: id, name: id, frame: CGRect(x: x, y: y, width: size, height: size), pixelWidth: 200, pixelHeight: 200)
    }
}
