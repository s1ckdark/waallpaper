import XCTest
import WaallpaperCore
@testable import Waallpaper

final class PreferencesTests: XCTestCase {
    func testExistingSettingsWithoutCalibrationsStillLoad() throws {
        let json = #"{"zoom":1.2,"horizontalOffset":-1,"verticalOffset":0.3,"excludedIDs":["secondary"],"imageName":"photo.png"}"#
        let preferences = try JSONDecoder().decode(Preferences.self, from: Data(json.utf8))
        XCTAssertEqual(preferences.zoom, 1.2)
        XCTAssertEqual(preferences.horizontalOffset, -1)
        XCTAssertEqual(preferences.excludedIDs, ["secondary"])
        XCTAssertEqual(preferences.imageName, "photo.png")
        XCTAssertTrue(preferences.validCalibrations.isEmpty)
    }

    func testPerDisplaySettingsPersistIncludingDisconnectedDisplay() throws {
        let calibration = DisplayCalibration(scale: 0.85, offsetX: 37.5, offsetY: -82)
        let preferences = Preferences(zoom: 1.4, horizontalOffset: 0, verticalOffset: 0.1,
                                      excludedIDs: [], imageName: "source.heic",
                                      calibrations: ["disconnected-display-uuid": calibration])
        let restored = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(preferences))
        XCTAssertEqual(restored.validCalibrations["disconnected-display-uuid"], calibration)
        XCTAssertEqual(restored.zoom, 1.4)
    }

    func testInvalidCalibrationDoesNotDiscardOtherSettings() throws {
        let json = #"{"zoom":1.5,"horizontalOffset":0,"verticalOffset":0,"excludedIDs":[],"calibrations":{"valid":{"scale":0.75,"offsetX":20,"offsetY":-5},"invalid":{"scale":0,"offsetX":0,"offsetY":0}}}"#
        let preferences = try JSONDecoder().decode(Preferences.self, from: Data(json.utf8))
        XCTAssertEqual(preferences.zoom, 1.5)
        XCTAssertEqual(preferences.validCalibrations.count, 1)
        XCTAssertEqual(preferences.validCalibrations["valid"]?.scale, 0.75)
    }
}
