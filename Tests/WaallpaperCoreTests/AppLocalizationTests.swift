import XCTest
@testable import WaallpaperCore

final class AppLocalizationTests: XCTestCase {
    func testSystemLanguageUsesFirstSupportedPreferenceAndExplicitChoiceWins() {
        XCTAssertEqual(AppLanguage.system.resolvedCode(preferredLanguages: ["fr-FR", "ko-KR", "en-US"]), "ko")
        XCTAssertEqual(AppLanguage.system.resolvedCode(preferredLanguages: ["en-GB", "ko-KR"]), "en")
        XCTAssertEqual(AppLanguage.system.resolvedCode(preferredLanguages: ["ko_KR"]), "ko")
        XCTAssertEqual(AppLanguage.system.resolvedCode(preferredLanguages: ["ja-JP"]), "en")
        XCTAssertEqual(AppLanguage.korean.resolvedCode(preferredLanguages: ["en-US"]), "ko")
        XCTAssertEqual(AppLanguage.english.resolvedCode(preferredLanguages: ["ko-KR"]), "en")
    }

    func testNativeLanguageResourcesHaveEqualKeysAndCompatibleFormatArguments() throws {
        let korean = try strings(code: "ko")
        let english = try strings(code: "en")
        XCTAssertGreaterThan(korean.count, 100)
        XCTAssertEqual(Set(korean.keys), Set(english.keys))
        let expression = try NSRegularExpression(pattern: "%[0-9$.+-]*[@df]")
        for key in korean.keys.sorted() {
            let ko = try XCTUnwrap(korean[key])
            let en = try XCTUnwrap(english[key])
            func formats(_ value: String) -> [String] {
                expression.matches(in: value, range: NSRange(value.startIndex..., in: value)).map {
                    String(value[Range($0.range, in: value)!])
                }
            }
            XCTAssertFalse(ko.isEmpty, key)
            XCTAssertFalse(en.isEmpty, key)
            XCTAssertEqual(formats(ko), formats(en), key)
            XCTAssertEqual(AppLocalization.text(key, language: .korean), ko, key)
            XCTAssertEqual(AppLocalization.text(key, language: .english), en, key)
        }
    }

    func testFormattedDisplayCountAndRestoreNoticeResolveExplicitLanguage() {
        XCTAssertEqual(AppLocalization.text("apply_displays", language: .english, arguments: [2]), "Apply to 2 Displays")
        XCTAssertEqual(AppLocalization.text("apply_displays", language: .korean, arguments: [2]), "2개 화면에 적용")
        XCTAssertTrue(AppLocalization.text("backup_notice", language: .english, arguments: ["Studio Display"]).hasPrefix("Studio Display: A saved copy"))
        XCTAssertEqual(AppLocalization.text("number_range_help", language: .english, arguments: [-10000, 10000]), "-10,000 to 10,000; press Return to save")
    }

    func testCoreErrorsResolveAtPresentationTimeWithoutGlobalLanguageState() {
        let error = WallpaperError.invalidGeometry("geometry_calibration")
        XCTAssertEqual(AppLocalization.description(for: error, language: .english),
                       "Unable to calculate the wallpaper layout. The display calibration is invalid. Reset its size and position.")
        XCTAssertTrue(AppLocalization.description(for: error, language: .korean).contains("모니터 보정값"))
        XCTAssertTrue(AppLocalization.description(for: WallpaperError.imageDecodeFailed, language: .english).hasPrefix("Unable to open"))
        XCTAssertTrue(AppLocalization.description(for: WallpaperError.imageDecodeFailed, language: .korean).hasPrefix("이미지를 열"))
    }

    private func strings(code: String) throws -> [String: String] {
        let url = try XCTUnwrap(AppLocalization.bundle(for: code).url(forResource: "Localizable", withExtension: "strings"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
    }
}
