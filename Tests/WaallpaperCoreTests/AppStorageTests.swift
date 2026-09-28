import XCTest
@testable import WaallpaperCore

final class AppStorageTests: XCTestCase {
    func testFreshInstallUsesNewBrandDirectory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        XCTAssertEqual(AppStorage.rootURL(in: root), root.appendingPathComponent("Waallpaper", isDirectory: true))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    func testLegacyPreferencesAndBackupsRemainAtTheirOriginalPaths() throws {
        for marker in ["preferences.json", "backup.json", "source.png"] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let legacy = root.appendingPathComponent("MoreWallpaper", isDirectory: true)
            try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
            let original = Data("existing data".utf8)
            try original.write(to: legacy.appendingPathComponent(marker))
            try FileManager.default.createDirectory(at: root.appendingPathComponent("Waallpaper"), withIntermediateDirectories: true)
            XCTAssertEqual(AppStorage.rootURL(in: root), legacy)
            XCTAssertEqual(try Data(contentsOf: legacy.appendingPathComponent(marker)), original)
        }
    }

    func testExistingNewBrandDataTakesPrecedenceWithoutRemovingLegacyData() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["MoreWallpaper", "Waallpaper"] {
            let directory = root.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data(name.utf8).write(to: directory.appendingPathComponent("preferences.json"))
        }
        XCTAssertEqual(AppStorage.rootURL(in: root), root.appendingPathComponent("Waallpaper", isDirectory: true))
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("MoreWallpaper/preferences.json")), Data("MoreWallpaper".utf8))
    }
}
