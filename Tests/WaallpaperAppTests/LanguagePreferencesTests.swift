import XCTest
import WaallpaperCore
@testable import Waallpaper

final class LanguagePreferencesTests: XCTestCase {
    func testOldPreferencesLoadWithoutNewLanguageAndGuideSettings() throws {
        let data = Data(#"{"zoom":1.4,"horizontalOffset":0.2,"verticalOffset":-0.1,"excludedIDs":[],"calibrations":{"external":{"scale":1.25,"offsetX":30,"offsetY":-50}}}"#.utf8)
        let preferences = try JSONDecoder().decode(Preferences.self, from: data)
        XCTAssertNil(preferences.language)
        XCTAssertNil(preferences.showsAlignmentGuides)
        XCTAssertNil(preferences.snapEnabled)
        XCTAssertEqual(preferences.validCalibrations["external"], DisplayCalibration(scale: 1.25, offsetX: 30, offsetY: -50))
    }

    func testLanguageAndGuidePreferencesRoundTripAlongsidePlacement() throws {
        let original = Preferences(zoom: 1.6, horizontalOffset: 0.2, verticalOffset: -0.3,
                                   excludedIDs: ["ignored"], imageName: "photo.png",
                                   calibrations: ["external": DisplayCalibration(scale: 0.8, offsetX: 15, offsetY: 20)],
                                   language: .english, showsAlignmentGuides: false, snapEnabled: false)
        let decoded = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded.language, .english)
        XCTAssertEqual(decoded.showsAlignmentGuides, false)
        XCTAssertEqual(decoded.snapEnabled, false)
        XCTAssertEqual(decoded.validCalibrations, original.validCalibrations)
        XCTAssertEqual(decoded.zoom, original.zoom)
        XCTAssertEqual(decoded.excludedIDs, original.excludedIDs)
    }

    @MainActor
    func testOldInstallKeepsKoreanWhileNewInstallUsesSystem() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertEqual(WallpaperModel(storageURL: directory).language, .system)
        let legacyData = Data(#"{"zoom":1.4,"horizontalOffset":0.2,"verticalOffset":-0.1,"excludedIDs":[],"calibrations":{"external":{"scale":1.25,"offsetX":30,"offsetY":-50}}}"#.utf8)
        try legacyData.write(to: directory.appendingPathComponent("preferences.json"))
        let upgraded = WallpaperModel(storageURL: directory)
        XCTAssertEqual(upgraded.language, .korean)
        XCTAssertEqual(upgraded.zoom, 1.4)
        XCTAssertEqual(upgraded.calibration(for: "external"), DisplayCalibration(scale: 1.25, offsetX: 30, offsetY: -50))
    }

    @MainActor
    func testLanguageSwitchUpdatesLiveLabelsAndPersistsWithoutResettingCalibration() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = WallpaperModel(storageURL: directory)
        model.zoom = 1.4
        let calibration = DisplayCalibration(scale: 1.25, offsetX: 30, offsetY: -50)
        model.setCalibration(calibration, for: "disconnected-display")
        model.language = .english
        XCTAssertEqual(model.imageName, "Golden hour · Sample image")
        XCTAssertEqual(model.status, "Choose an image to connect your displays.")
        XCTAssertEqual(model.t("open_image_menu"), "Open Image…")
        model.language = .korean
        XCTAssertEqual(model.imageName, "Golden hour · 샘플 이미지")
        XCTAssertEqual(model.t("open_image_menu"), "이미지 열기…")
        XCTAssertEqual(model.calibration(for: "disconnected-display"), calibration)
        XCTAssertEqual(model.zoom, 1.4)
        let saved = try JSONDecoder().decode(Preferences.self, from: Data(contentsOf: directory.appendingPathComponent("preferences.json")))
        XCTAssertEqual(saved.language, .korean)
        XCTAssertEqual(saved.validCalibrations["disconnected-display"], calibration)
        let reopened = WallpaperModel(storageURL: directory)
        XCTAssertEqual(reopened.language, .korean)
        XCTAssertEqual(reopened.calibration(for: "disconnected-display"), calibration)
        XCTAssertEqual(reopened.zoom, 1.4)
    }

    @MainActor
    func testPresentedImageErrorUpdatesWhenLanguageChanges() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = WallpaperModel(storageURL: directory)
        model.language = .english
        await model.importImage(from: directory.appendingPathComponent("missing.png"))
        XCTAssertEqual(model.errorMessage, AppLocalization.description(for: WallpaperError.imageDecodeFailed, language: .english))
        model.language = .korean
        XCTAssertEqual(model.errorMessage, AppLocalization.description(for: WallpaperError.imageDecodeFailed, language: .korean))
        XCTAssertEqual(model.status, model.errorMessage)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Waallpaper-LanguageTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
