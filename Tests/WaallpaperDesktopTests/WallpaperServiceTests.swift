import XCTest
import AppKit
import ImageIO
import WaallpaperCore
@testable import WaallpaperDesktop

@MainActor
final class WallpaperServiceTests: XCTestCase {
    @MainActor private struct Fixture {
        let directory: URL
        let root: URL
        let client: FakeDesktopClient
        let originals: [String: DesktopImageState]
        let originalBytes: [String: Data]
        let image: CGImage

        func service(backupFiles: (any BackupFileAccess)? = nil) -> WallpaperService {
            WallpaperService(rootURL: root, client: client, backupFiles: backupFiles)
        }
        func remove() { try? FileManager.default.removeItem(at: directory) }
    }

    private func fixture() throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("WaallpaperTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let displays = [
            DisplayDescriptor(id: "left", name: "Left", frame: CGRect(x: -40, y: 0, width: 40, height: 30), pixelWidth: 80, pixelHeight: 60),
            DisplayDescriptor(id: "right", name: "Right", frame: CGRect(x: 0, y: -10, width: 50, height: 40), pixelWidth: 50, pixelHeight: 40)
        ]
        let options = DesktopImageOptions(scaling: 0, allowClipping: true,
                                          fillColor: .init(red: 0.2, green: 0.3, blue: 0.4, alpha: 1))
        var originals: [String: DesktopImageState] = [:]
        for display in displays {
            let url = directory.appendingPathComponent("\(display.id)-original.png")
            try Data("original \(display.id)".utf8).write(to: url)
            originals[display.id] = DesktopImageState(url: url, options: options)
        }
        let context = try XCTUnwrap(CGContext(data: nil, width: 180, height: 80, bitsPerComponent: 8,
                                             bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 180, height: 80))
        return Fixture(directory: directory, root: directory.appendingPathComponent("state"),
                       client: FakeDesktopClient(displays: displays, states: originals),
                       originals: originals, originalBytes: try originals.mapValues { try Data(contentsOf: $0.url) },
                       image: try XCTUnwrap(context.makeImage()))
    }

    private func assertOriginalContentRestored(_ fixture: Fixture, ids: [String]? = nil,
                                               file: StaticString = #filePath, line: UInt = #line) throws {
        for id in ids ?? Array(fixture.originals.keys) {
            let restored = try XCTUnwrap(fixture.client.states[id], file: file, line: line)
            XCTAssertEqual(restored.options, fixture.originals[id]?.options, file: file, line: line)
            XCTAssertEqual(try Data(contentsOf: restored.url), fixture.originalBytes[id], file: file, line: line)
        }
    }

    private func gradientImage() throws -> CGImage {
        let width = 180
        let height = 80
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                pixels[offset] = UInt8(x * 255 / (width - 1))
                pixels[offset + 1] = UInt8(y * 255 / (height - 1))
                pixels[offset + 2] = ((x / 10 + y / 10) % 2 == 0) ? 40 : 200
            }
        }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(pixels) as CFData))
        return try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                    bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                    provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    }

    private func raster(at url: URL) throws -> (width: Int, height: Int, pixels: Data) {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let context = try XCTUnwrap(CGContext(data: nil, width: image.width, height: image.height,
                                             bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                             space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let bytes = try XCTUnwrap(context.data)
        return (image.width, image.height, Data(bytes: bytes, count: image.width * image.height * 4))
    }

    func testApplyWritesDurablePNGsAndRestartRestoresOriginalOptions() async throws {
        let fixture = try fixture()
        defer { fixture.remove() }
        let service = fixture.service()
        var manifestExistedBeforeEveryMutation = true
        fixture.client.onSet = { _, _ in
            manifestExistedBeforeEveryMutation = manifestExistedBeforeEveryMutation &&
                FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("backup.json").path)
        }
        let urls = try await service.apply(image: fixture.image, displays: fixture.client.catalog, placement: .init())
        XCTAssertTrue(manifestExistedBeforeEveryMutation)
        XCTAssertTrue(service.hasBackup)
        XCTAssertNil(service.backupNotice)
        XCTAssertEqual(urls.count, 2)
        for (display, url) in zip(fixture.client.catalog, urls) {
            XCTAssertTrue(url.path.hasPrefix(fixture.root.appendingPathComponent("Wallpapers").path))
            let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
            let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
            XCTAssertEqual(decoded.width, display.pixelWidth)
            XCTAssertEqual(decoded.height, display.pixelHeight)
            XCTAssertEqual(fixture.client.states[display.id]?.options, .exactFit)
        }
        let reopened = fixture.service()
        XCTAssertTrue(reopened.hasBackup)
        XCTAssertEqual(try reopened.restore(), 2)
        try assertOriginalContentRestored(fixture)
        XCTAssertFalse(reopened.hasBackup)
        XCTAssertFalse(fixture.service().hasBackup)
        XCTAssertTrue(urls.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
    }

    func testRepeatedApplyPreservesFirstOriginalBackup() async throws {
        let fixture = try fixture()
        defer { fixture.remove() }
        let first = fixture.service()
        let firstURLs = try await first.apply(image: fixture.image, displays: fixture.client.catalog, placement: .init())
        let second = fixture.service()
        let secondURLs = try await second.apply(image: fixture.image, displays: fixture.client.catalog,
                                                placement: .init(zoom: 1.5, horizontalOffset: 0.3))
        XCTAssertNotEqual(firstURLs, secondURLs)
        XCTAssertEqual(try second.restore(), 2)
        try assertOriginalContentRestored(fixture)
    }

    func testApplySelectedSubsetLeavesOtherConnectedScreenUnchanged() async throws {
        let fixture = try fixture()
        defer { fixture.remove() }
        let service = fixture.service()
        let selected = Array(fixture.client.catalog.prefix(1))
        let urls = try await service.apply(image: fixture.image, displays: selected, placement: .init())
        XCTAssertEqual(urls.count, 1)
        XCTAssertEqual(fixture.client.calls.map(\.displayID), ["left"])
        XCTAssertEqual(fixture.client.states["left"]?.url, urls[0])
        XCTAssertEqual(fixture.client.states["right"], fixture.originals["right"])
        XCTAssertEqual(try fixture.service().restore(), 1)
        try assertOriginalContentRestored(fixture)
        XCTAssertEqual(fixture.client.states["right"], fixture.originals["right"])
    }

    func testCalibratedApplyAndExportChangeCropWithMatchingPixelsAndOriginalResolution() async throws {
        let fixture = try fixture()
        defer { fixture.remove() }
        let service = fixture.service()
        let image = try gradientImage()
        let snapshot = fixture.client.catalog
        let calibrations = [
            "left": DisplayCalibration(scale: 1.35, offsetX: -12, offsetY: 8),
            "right": DisplayCalibration(scale: 0.8, offsetX: 5, offsetY: -6)
        ]
        let baseline = try await service.export(image: image, displays: snapshot, placement: .init(),
                                                  to: fixture.directory)
        XCTAssertTrue(fixture.client.calls.isEmpty)
        // The client still reports the original frames: calibration must not trigger
        // the topology guard, nor change the selected displays' output pixel dimensions.
        let applied = try await service.apply(image: image, displays: snapshot, placement: .init(),
                                               calibrations: calibrations)
        let exported = try await service.export(image: image, displays: snapshot, placement: .init(),
                                                 to: fixture.directory, calibrations: calibrations)
        XCTAssertEqual(fixture.client.catalog, snapshot)
        XCTAssertEqual(fixture.client.calls.map(\.displayID), ["left", "right"])
        for (index, display) in snapshot.enumerated() {
            let defaultRaster = try raster(at: baseline[index])
            let appliedRaster = try raster(at: applied[index])
            let exportedRaster = try raster(at: exported[index])
            XCTAssertEqual(appliedRaster.width, display.pixelWidth)
            XCTAssertEqual(appliedRaster.height, display.pixelHeight)
            XCTAssertEqual(exportedRaster.width, display.pixelWidth)
            XCTAssertEqual(exportedRaster.height, display.pixelHeight)
            XCTAssertNotEqual(appliedRaster.pixels, defaultRaster.pixels, "Calibration must change \(display.name)'s crop")
            XCTAssertEqual(appliedRaster.pixels, exportedRaster.pixels)
            XCTAssertEqual(fixture.client.states[display.id]?.url, applied[index])
        }
        XCTAssertEqual(try service.restore(), 2)
        try assertOriginalContentRestored(fixture)
    }

    func testInitialTopologyMismatchDoesNotRenderOrMutate() async throws {
        let fixture = try fixture()
        defer { fixture.remove() }
        let snapshot = fixture.client.catalog
        fixture.client.catalog.removeLast()
        do {
            _ = try await fixture.service().apply(image: fixture.image, displays: snapshot, placement: .init())
            XCTFail("Expected a topology error")
        } catch WallpaperServiceError.topologyChanged {} catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertTrue(fixture.client.calls.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.root.path))
    }

    func testTopologyChangeDuringRenderDoesNotMutateOrLeaveUnpublishedImages() async throws {
        let fixture = try fixture()
        defer { fixture.remove() }
        let snapshot = fixture.client.catalog
        fixture.client.onReadDisplays = { count in
            count == 1 ? snapshot : Array(snapshot.prefix(1))
        }
        do {
            _ = try await fixture.service().apply(image: fixture.image, displays: snapshot, placement: .init())
            XCTFail("Expected a topology error")
        } catch WallpaperServiceError.topologyChanged {} catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertTrue(fixture.client.calls.isEmpty)
        let wallpaperDirectory = fixture.root.appendingPathComponent("Wallpapers")
        let remaining = (try? FileManager.default.contentsOfDirectory(atPath: wallpaperDirectory.path)) ?? []
        XCTAssertTrue(remaining.isEmpty)
        XCTAssertFalse(fixture.service().hasBackup)
    }

    func testPartialApplyFailureRollsBackAttemptedScreensAndClearsNewBackup() async throws {
        let fixture = try fixture()
        defer { fixture.remove() }
        fixture.client.failCalls = [2]
        let service = fixture.service()
        do {
            _ = try await service.apply(image: fixture.image, displays: fixture.client.catalog, placement: .init())
            XCTFail("Expected apply failure")
        } catch WallpaperServiceError.applyFailed(_, let issues) {
            XCTAssertTrue(issues.isEmpty)
        } catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(fixture.client.calls.map(\.displayID), ["left", "right", "right", "left"])
        XCTAssertEqual(fixture.client.states, fixture.originals)
        XCTAssertFalse(service.hasBackup)
        XCTAssertFalse(fixture.service().hasBackup)
    }

    func testRollbackFailureKeepsDurableBackupsForRestoreRetry() async throws {
        let fixture = try fixture()
        defer { fixture.remove() }
        fixture.client.failCalls = [2, 4]
        let service = fixture.service()
        do {
            _ = try await service.apply(image: fixture.image, displays: fixture.client.catalog, placement: .init())
            XCTFail("Expected apply failure")
        } catch WallpaperServiceError.applyFailed(_, let issues) {
            XCTAssertEqual(issues.count, 1)
        } catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertTrue(service.hasBackup)
        let activeLeft = try XCTUnwrap(fixture.client.states["left"])
        XCTAssertNotEqual(activeLeft, fixture.originals["left"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: activeLeft.url.path))
        fixture.client.failCalls = []
        let reopened = fixture.service()
        XCTAssertEqual(try reopened.restore(), 2)
        try assertOriginalContentRestored(fixture)
        XCTAssertFalse(reopened.hasBackup)
    }

    func testTopologyChangeBetweenScreenUpdatesRollsBackChangedScreen() async throws {
        let fixture = try fixture()
        defer { fixture.remove() }
        let snapshot = fixture.client.catalog
        fixture.client.onSet = { _, _ in fixture.client.catalog = Array(snapshot.prefix(1)) }
        let service = fixture.service()
        do {
            _ = try await service.apply(image: fixture.image, displays: snapshot, placement: .init())
            XCTFail("Expected topology change to abort apply")
        } catch WallpaperServiceError.applyFailed(_, let issues) {
            XCTAssertTrue(issues.isEmpty)
        } catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(fixture.client.calls.map(\.displayID), ["left", "left"])
        XCTAssertEqual(fixture.client.states, fixture.originals)
        XCTAssertFalse(service.hasBackup)
    }

    func testFailedRepeatedApplyRetainsOriginalBackup() async throws {
        let fixture = try fixture()
        defer { fixture.remove() }
        let service = fixture.service()
        _ = try await service.apply(image: fixture.image, displays: fixture.client.catalog, placement: .init())
        let previouslyApplied = fixture.client.states
        fixture.client.failCalls = [4]
        do {
            _ = try await service.apply(image: fixture.image, displays: fixture.client.catalog, placement: .init(zoom: 2))
            XCTFail("Expected repeated apply failure")
        } catch WallpaperServiceError.applyFailed(_, let issues) {
            XCTAssertTrue(issues.isEmpty)
        } catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(fixture.client.states, previouslyApplied)
        XCTAssertTrue(service.hasBackup)
        fixture.client.failCalls = []
        XCTAssertEqual(try fixture.service().restore(), 2)
        try assertOriginalContentRestored(fixture)
    }

    func testDisconnectedMonitorBackupSurvivesPartialRestoreAndReconnect() async throws {
        let fixture = try fixture()
        defer { fixture.remove() }
        let service = fixture.service()
        let snapshot = fixture.client.catalog
        _ = try await service.apply(image: fixture.image, displays: snapshot, placement: .init())
        fixture.client.catalog = Array(snapshot.prefix(1))
        do {
            _ = try service.restore()
            XCTFail("Expected incomplete restore")
        } catch WallpaperServiceError.restoreIncomplete(let restored, let issues) {
            XCTAssertEqual(restored, 1)
            XCTAssertEqual(issues.count, 1)
        } catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertTrue(service.hasBackup)
        try assertOriginalContentRestored(fixture, ids: ["left"])
        let reopened = fixture.service()
        fixture.client.catalog = snapshot
        XCTAssertEqual(try reopened.restore(), 1)
        try assertOriginalContentRestored(fixture)
        XCTAssertFalse(reopened.hasBackup)
    }

    func testFailedRestoreKeepsOnlyFailedRecordForRetry() async throws {
        let fixture = try fixture()
        defer { fixture.remove() }
        let service = fixture.service()
        _ = try await service.apply(image: fixture.image, displays: fixture.client.catalog, placement: .init())
        fixture.client.failCalls = [3]
        do {
            _ = try service.restore()
            XCTFail("Expected incomplete restore")
        } catch WallpaperServiceError.restoreIncomplete(let restored, _) {
            XCTAssertEqual(restored, 1)
        } catch { XCTFail("Unexpected error: \(error)") }
        fixture.client.failCalls = []
        XCTAssertEqual(try fixture.service().restore(), 1)
        XCTAssertEqual(fixture.client.calls.last?.displayID, "left")
        try assertOriginalContentRestored(fixture)
    }

    func testMissingOriginalRestoresPreservedCopyAndKeepsActiveFile() async throws {
        let fixture = try fixture()
        defer { fixture.remove() }
        let service = fixture.service()
        _ = try await service.apply(image: fixture.image, displays: fixture.client.catalog, placement: .init())
        let original = try XCTUnwrap(fixture.originals["left"])
        let bytes = try Data(contentsOf: original.url)
        try FileManager.default.removeItem(at: original.url)
        XCTAssertEqual(try service.restore(), 2)
        let restored = try XCTUnwrap(fixture.client.states["left"])
        XCTAssertNotEqual(restored.url, original.url)
        XCTAssertEqual(try Data(contentsOf: restored.url), bytes)
        XCTAssertEqual(restored.options, original.options)
        XCTAssertFalse(service.hasBackup)
        XCTAssertTrue(FileManager.default.fileExists(atPath: restored.url.path))
    }

    func testRestoreUsesPreservedBytesWhenOriginalFileWasReplaced() async throws {
        let fixture = try fixture()
        defer { fixture.remove() }
        let service = fixture.service()
        _ = try await service.apply(image: fixture.image, displays: fixture.client.catalog, placement: .init())
        let originalURL = try XCTUnwrap(fixture.originals["left"]?.url)
        let replacementBytes = Data("a different wallpaper at the same path".utf8)
        try replacementBytes.write(to: originalURL)
        XCTAssertEqual(try fixture.service().restore(), 2)
        try assertOriginalContentRestored(fixture)
        XCTAssertNotEqual(fixture.client.states["left"]?.url, originalURL)
        XCTAssertEqual(try Data(contentsOf: originalURL), replacementBytes)
    }

    func testRestoreFallsBackToOriginalWhenPreservedCopyIsMissing() async throws {
        let fixture = try fixture()
        defer { fixture.remove() }
        let service = fixture.service()
        _ = try await service.apply(image: fixture.image, displays: fixture.client.catalog, placement: .init())
        let backupRoot = fixture.root.appendingPathComponent("Backups")
        let backupDirectories = try FileManager.default.contentsOfDirectory(at: backupRoot, includingPropertiesForKeys: nil)
        for directory in backupDirectories {
            for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
                try FileManager.default.removeItem(at: file)
            }
        }
        XCTAssertEqual(try fixture.service().restore(), 2)
        XCTAssertEqual(fixture.client.states, fixture.originals)
        try assertOriginalContentRestored(fixture)
    }

    func testAppReadDenialAllowsApplyAndReferenceRestoreAfterRestart() async throws {
        let fixture = try fixture()
        defer { fixture.remove() }
        let originalURL = try XCTUnwrap(fixture.originals["right"]?.url)
        let access = ControlledBackupFileAccess()
        access.unreadableURLs = [originalURL]
        let service = fixture.service(backupFiles: access)
        let urls = try await service.apply(image: fixture.image, displays: fixture.client.catalog, placement: .init())
        XCTAssertEqual(urls.count, 2)
        XCTAssertTrue(service.hasBackup)
        XCTAssertTrue(try XCTUnwrap(service.backupNotice).contains("Right"))
        XCTAssertEqual(try Data(contentsOf: originalURL), fixture.originalBytes["right"])
        let reopened = fixture.service(backupFiles: access)
        XCTAssertNotNil(reopened.backupNotice)
        XCTAssertEqual(try reopened.restore(), 2)
        XCTAssertEqual(fixture.client.states["right"], fixture.originals["right"])
        try assertOriginalContentRestored(fixture)
        XCTAssertFalse(reopened.hasBackup)
        XCTAssertNil(reopened.backupNotice)
    }

    func testCopyDenialRetainsReferenceBackupAcrossRepeatedApplies() async throws {
        let fixture = try fixture()
        defer { fixture.remove() }
        let originalURL = try XCTUnwrap(fixture.originals["right"]?.url)
        let access = ControlledBackupFileAccess()
        access.copyDeniedURLs = [originalURL]
        let service = fixture.service(backupFiles: access)
        _ = try await service.apply(image: fixture.image, displays: fixture.client.catalog, placement: .init())
        XCTAssertEqual(access.deniedCopyAttempts, [originalURL])
        XCTAssertNotNil(service.backupNotice)
        _ = try await service.apply(image: fixture.image, displays: fixture.client.catalog, placement: .init(zoom: 1.5))
        // A subsequent app-owned wallpaper must never replace the first original record.
        XCTAssertEqual(access.deniedCopyAttempts, [originalURL])
        let reopened = fixture.service()
        XCTAssertNotNil(reopened.backupNotice)
        XCTAssertEqual(try reopened.restore(), 2)
        XCTAssertEqual(fixture.client.states["right"], fixture.originals["right"])
        try assertOriginalContentRestored(fixture)
    }

    func testMissingOriginalIsRecordedAndFailedRestoreRemainsRetryable() async throws {
        let fixture = try fixture()
        defer { fixture.remove() }
        let originalURL = try XCTUnwrap(fixture.originals["right"]?.url)
        try FileManager.default.removeItem(at: originalURL)
        let service = fixture.service()
        _ = try await service.apply(image: fixture.image, displays: fixture.client.catalog, placement: .init())
        XCTAssertNotNil(service.backupNotice)
        fixture.client.failURLs = [originalURL]
        let reopened = fixture.service()
        reopened.language = .korean
        do {
            _ = try reopened.restore()
            XCTFail("Expected an incomplete restore")
        } catch WallpaperServiceError.restoreIncomplete(let restored, let issues) {
            XCTAssertEqual(restored, 1)
            XCTAssertTrue(try XCTUnwrap(issues.first).contains("원본 파일이 이동·삭제"))
        } catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(fixture.client.calls.last?.state.url, originalURL)
        XCTAssertTrue(reopened.hasBackup)
        XCTAssertTrue(fixture.service().hasBackup)
        XCTAssertNotNil(reopened.backupNotice)
        try XCTUnwrap(fixture.originalBytes["right"]).write(to: originalURL)
        fixture.client.failURLs = []
        let retry = fixture.service()
        XCTAssertEqual(try retry.restore(), 1)
        try assertOriginalContentRestored(fixture)
        XCTAssertFalse(retry.hasBackup)
        XCTAssertNil(retry.backupNotice)
    }

    func testInvalidBackupBlocksMutationButAllowsExport() async throws {
        let fixture = try fixture()
        defer { fixture.remove() }
        try FileManager.default.createDirectory(at: fixture.root, withIntermediateDirectories: true)
        try Data("damaged".utf8).write(to: fixture.root.appendingPathComponent("backup.json"))
        let service = fixture.service()
        XCTAssertTrue(service.hasBackup)
        do {
            _ = try await service.apply(image: fixture.image, displays: fixture.client.catalog, placement: .init())
            XCTFail("Expected invalid backup")
        } catch WallpaperServiceError.invalidBackup {} catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertThrowsError(try service.restore())
        let files = try await service.export(image: fixture.image, displays: fixture.client.catalog,
                                              placement: .init(), to: fixture.directory)
        XCTAssertEqual(files.count, 2)
        XCTAssertTrue(fixture.client.calls.isEmpty)
    }

    func testOriginalDirectoryIsRejectedBeforeCopyOrMutation() async throws {
        let fixture = try fixture()
        defer { fixture.remove() }
        fixture.client.states["left"] = DesktopImageState(url: fixture.directory, options: .init())
        let service = fixture.service()
        do {
            _ = try await service.apply(image: fixture.image, displays: fixture.client.catalog, placement: .init())
            XCTFail("Expected a non-file background to be rejected")
        } catch WallpaperServiceError.backupUnavailable {} catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertTrue(fixture.client.calls.isEmpty)
        XCTAssertFalse(service.hasBackup)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("Backups").path))
    }

    func testNonFileOriginalURLIsRejectedBeforeMutation() async throws {
        let fixture = try fixture()
        defer { fixture.remove() }
        fixture.client.states["left"] = DesktopImageState(url: try XCTUnwrap(URL(string: "https://example.com/wallpaper.jpg")),
                                                         options: .init())
        let service = fixture.service()
        do {
            _ = try await service.apply(image: fixture.image, displays: fixture.client.catalog, placement: .init())
            XCTFail("Expected a non-file original URL to be rejected")
        } catch WallpaperServiceError.backupUnavailable {} catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertTrue(fixture.client.calls.isEmpty)
        XCTAssertFalse(service.hasBackup)
    }

    func testExportsUseUniqueFoldersWithoutDesktopOrBackupChanges() async throws {
        let fixture = try fixture()
        defer { fixture.remove() }
        let service = fixture.service()
        let first = try await service.export(image: fixture.image, displays: fixture.client.catalog,
                                              placement: .init(), to: fixture.directory)
        let second = try await service.export(image: fixture.image, displays: fixture.client.catalog,
                                               placement: .init(), to: fixture.directory)
        XCTAssertNotEqual(first, second)
        XCTAssertNotEqual(first[0].deletingLastPathComponent(), second[0].deletingLastPathComponent())
        XCTAssertEqual(Set(first.map { $0.deletingLastPathComponent() }).count, 1)
        XCTAssertTrue(first.allSatisfy { CGImageSourceCreateWithURL($0 as CFURL, nil) != nil })
        XCTAssertTrue(fixture.client.calls.isEmpty)
        XCTAssertFalse(service.hasBackup)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.root.path))
    }

    func testDesktopOptionRoundTripPreservesKnownWorkspaceValues() async throws {
        let options = DesktopImageOptions(scaling: 3, allowClipping: true,
                                         fillColor: .init(red: 0.25, green: 0.5, blue: 0.75, alpha: 1))
        let captured = try DesktopImageOptions(dictionary: options.dictionary)
        XCTAssertEqual(captured, options)
        XCTAssertEqual(try DesktopImageOptions(dictionary: [:]), DesktopImageOptions())
    }
}

@MainActor
private final class FakeDesktopClient: DesktopClient {
    struct Call {
        let displayID: String
        let state: DesktopImageState
    }

    var catalog: [DisplayDescriptor]
    var states: [String: DesktopImageState]
    var calls: [Call] = []
    var failCalls: Set<Int> = []
    var failURLs: Set<URL> = []
    var onReadDisplays: ((Int) -> [DisplayDescriptor])?
    var onSet: ((String, DesktopImageState) -> Void)?
    private var readCount = 0

    init(displays: [DisplayDescriptor], states: [String: DesktopImageState]) {
        catalog = displays
        self.states = states
    }

    func displays() -> [DisplayDescriptor] {
        readCount += 1
        return onReadDisplays?(readCount) ?? catalog
    }

    func imageState(for displayID: String) throws -> DesktopImageState {
        guard let state = states[displayID] else { throw NSError(domain: "FakeDesktop", code: 1) }
        return state
    }

    func setImage(_ state: DesktopImageState, for displayID: String) throws {
        calls.append(Call(displayID: displayID, state: state))
        onSet?(displayID, state)
        if failCalls.contains(calls.count) || failURLs.contains(state.url) {
            throw NSError(domain: "FakeDesktop", code: calls.count)
        }
        states[displayID] = state
    }
}

@MainActor
private final class ControlledBackupFileAccess: BackupFileAccess {
    var unreadableURLs: Set<URL> = []
    var copyDeniedURLs: Set<URL> = []
    var deniedCopyAttempts: [URL] = []
    private let files = FileSystemBackupFileAccess()

    func status(of url: URL) -> BackupFileStatus {
        unreadableURLs.contains(url) ? .unavailable : files.status(of: url)
    }

    func copy(at source: URL, to destination: URL) throws {
        if copyDeniedURLs.contains(source) {
            deniedCopyAttempts.append(source)
            throw CocoaError(.fileReadNoPermission)
        }
        try files.copy(at: source, to: destination)
    }
}
