import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import WaallpaperCore

public enum WallpaperServiceError: AppLocalizableError {
    case operationInProgress
    case topologyChanged
    case backupUnavailable(String)
    case invalidBackup(String)
    case pngWriteFailed(String)
    case applyFailed(reason: String, rollbackIssues: [String])
    case restoreIncomplete(restored: Int, issues: [String])

    public func localizedDescription(language: AppLanguage) -> String {
        func text(_ key: String, _ arguments: CVarArg...) -> String {
            AppLocalization.text(key, language: language, arguments: arguments)
        }
        switch self {
        case .operationInProgress: return text("error_busy")
        case .topologyChanged: return text("error_topology")
        case .backupUnavailable(let reason): return text("error_backup", text(reason))
        case .invalidBackup(let reason): return text("error_invalid_backup", text(reason))
        case .pngWriteFailed(let name): return text("error_png_write", name)
        case .applyFailed(let reason, let rollbackIssues):
            return rollbackIssues.isEmpty
                ? text("error_apply_rolled_back", reason)
                : text("error_apply_rollback_issues", reason, rollbackIssues.joined(separator: "\n"))
        case .restoreIncomplete(let restored, let issues):
            return text("error_restore_incomplete", restored, issues.joined(separator: "\n"))
        }
    }
}

/// Owns durable rendered images and an original-wallpaper backup for each display.
/// Desktop mutations remain on the main actor; image rendering runs off the main actor.
@MainActor
public final class WallpaperService {
    private struct BackupRecord: Codable {
        let displayID: String
        let displayName: String
        let original: DesktopImageState
        let preservedURL: URL?
    }

    private struct BackupManifest: Codable {
        let version: Int
        let records: [BackupRecord]
    }

    private let rootURL: URL
    private let client: any DesktopClient
    private let backupFiles: any BackupFileAccess
    private var backups: [String: BackupRecord] = [:]
    private var backupLoadError: String?
    private var busy = false
    public var language: AppLanguage = .system

    public convenience init(rootURL: URL? = nil) {
        self.init(rootURL: rootURL ?? Self.defaultRootURL, client: WorkspaceDesktopClient())
    }

    init(rootURL: URL, client: any DesktopClient, backupFiles: (any BackupFileAccess)? = nil) {
        self.rootURL = rootURL
        self.client = client
        self.backupFiles = backupFiles ?? FileSystemBackupFileAccess()
        let manifestURL = rootURL.appendingPathComponent("backup.json")
        if FileManager.default.fileExists(atPath: manifestURL.path) {
            do {
                let manifest = try JSONDecoder().decode(BackupManifest.self, from: Data(contentsOf: manifestURL))
                guard manifest.version == 1,
                      Set(manifest.records.map(\.displayID)).count == manifest.records.count,
                      manifest.records.allSatisfy({ $0.original.url.isFileURL && ($0.preservedURL?.isFileURL ?? true) }) else {
                    throw WallpaperServiceError.invalidBackup("backup_invalid_format")
                }
                backups = Dictionary(uniqueKeysWithValues: manifest.records.map { ($0.displayID, $0) })
            } catch {
                backupLoadError = AppLocalization.description(for: error, language: language)
            }
        }
    }

    public var hasBackup: Bool { !backups.isEmpty || backupLoadError != nil }

    /// Warns when a restore depends on an external original instead of a usable saved copy.
    public var backupNotice: String? { backupNotice(language: language) }

    public func backupNotice(language: AppLanguage) -> String? {
        let names = backups.values.filter { usablePreservedURL(for: $0) == nil }
            .sorted { $0.displayID < $1.displayID }.map(\.displayName)
        guard !names.isEmpty else { return nil }
        return AppLocalization.text("backup_notice", language: language, arguments: [names.joined(separator: ", ")])
    }

    public func apply(image: CGImage, displays: [DisplayDescriptor], placement: WallpaperPlacement,
                      calibrations: [String: DisplayCalibration] = [:]) async throws -> [URL] {
        try beginOperation()
        defer { busy = false }
        try verifyTopology(displays)
        let outputDirectory = rootURL.appendingPathComponent("Wallpapers", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let backupDirectory = rootURL.appendingPathComponent("Backups", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        var hasAttemptedDesktopChange = false
        var keepBackupDirectory = false
        defer {
            // Only remove this operation's unpublished artifacts. Published wallpapers stay durable.
            if !hasAttemptedDesktopChange { try? FileManager.default.removeItem(at: outputDirectory) }
            if !keepBackupDirectory { try? FileManager.default.removeItem(at: backupDirectory) }
        }

        let urls = try await Self.render(image: image, displays: displays, placement: placement,
                                         directory: outputDirectory, calibrations: calibrations)
        try verifyTopology(displays)
        var previousStates: [String: DesktopImageState] = [:]
        var proposedBackups = backups
        for (index, display) in displays.enumerated() {
            let state = try client.imageState(for: display.id)
            guard state.url.isFileURL else {
                throw WallpaperServiceError.backupUnavailable(t("backup_path_unavailable", display.name))
            }
            let sourceStatus = backupFiles.status(of: state.url)
            guard sourceStatus != .directory else {
                throw WallpaperServiceError.backupUnavailable(t("backup_path_directory", display.name))
            }
            previousStates[display.id] = state
            if backups[display.id] == nil {
                var preservedURL: URL?
                if sourceStatus == .readableFile {
                    try FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true,
                                                            attributes: [.posixPermissions: 0o700])
                    let suffix = state.url.pathExtension.isEmpty ? "image" : state.url.pathExtension
                    let candidateURL = backupDirectory.appendingPathComponent("original-\(index + 1).\(suffix)")
                    do {
                        try backupFiles.copy(at: state.url, to: candidateURL)
                        preservedURL = candidateURL
                    } catch {
                        // A source may become inaccessible between inspection and copy.
                        // Persist its URL/options without bypassing its access controls.
                        try? FileManager.default.removeItem(at: candidateURL)
                    }
                }
                proposedBackups[display.id] = BackupRecord(displayID: display.id, displayName: display.name,
                                                           original: state, preservedURL: preservedURL)
            }
        }
        try verifyTopology(displays)
        let priorBackups = backups
        try persist(proposedBackups)
        keepBackupDirectory = true

        var attempted: [DisplayDescriptor] = []
        do {
            for (display, url) in zip(displays, urls) {
                try verifyTopology(displays)
                // Include the failing call: the API may throw after an OS-side partial change.
                attempted.append(display)
                hasAttemptedDesktopChange = true
                try client.setImage(DesktopImageState(url: url, options: .exactFit), for: display.id)
            }
        } catch {
            let failure = AppLocalization.description(for: error, language: language)
            var rollbackIssues: [String] = []
            for display in attempted.reversed() {
                guard let previous = previousStates[display.id] else { continue }
                do { try client.setImage(previous, for: display.id) }
                catch { rollbackIssues.append("\(display.name): \(AppLocalization.description(for: error, language: language))") }
            }
            if rollbackIssues.isEmpty {
                do {
                    try persist(priorBackups)
                    keepBackupDirectory = false
                } catch {
                    rollbackIssues.append(t("restore_record_issue", AppLocalization.description(for: error, language: language)))
                }
            }
            throw WallpaperServiceError.applyFailed(reason: failure, rollbackIssues: rollbackIssues)
        }
        return urls
    }

    /// Restores connected displays, retaining every failed or disconnected record for a later retry.
    @discardableResult
    public func restore() throws -> Int {
        try beginOperation()
        defer { busy = false }
        let connected = Set(client.displays().map(\.id))
        var remaining = backups
        var restored = 0
        var issues: [String] = []
        for record in backups.values.sorted(by: { $0.displayID < $1.displayID }) {
            guard connected.contains(record.displayID) else {
                issues.append(t("restore_display_disconnected", record.displayName))
                continue
            }
            let preservedURL = usablePreservedURL(for: record)
            do {
                // The original path may now contain a replacement image. Prefer the
                // captured bytes so restore returns to the wallpaper that was backed up.
                // NSWorkspace may access an original that TCC prevents this app reading;
                // let the actual restore API decide instead of rejecting it preemptively.
                let url = preservedURL ?? record.original.url
                try client.setImage(DesktopImageState(url: url, options: record.original.options), for: record.displayID)
                remaining.removeValue(forKey: record.displayID)
                restored += 1
            } catch {
                let detail = preservedURL == nil
                    ? t("restore_original_failed")
                    : ""
                issues.append("\(record.displayName): \(detail)\(AppLocalization.description(for: error, language: language))")
            }
        }
        if restored > 0 {
            do { try persist(remaining) }
            catch { issues.append(t("restore_record_failed", AppLocalization.description(for: error, language: language))) }
        }
        // A preserved copy may now be the active desktop image, so never remove it here.
        if !issues.isEmpty { throw WallpaperServiceError.restoreIncomplete(restored: restored, issues: issues) }
        return restored
    }

    public func export(image: CGImage, displays: [DisplayDescriptor], placement: WallpaperPlacement, to directory: URL,
                       calibrations: [String: DisplayCalibration] = [:]) async throws -> [URL] {
        guard !busy else { throw WallpaperServiceError.operationInProgress }
        busy = true
        defer { busy = false }
        let accessed = directory.startAccessingSecurityScopedResource()
        defer { if accessed { directory.stopAccessingSecurityScopedResource() } }
        let outputDirectory = directory.appendingPathComponent("Waallpaper-\(UUID().uuidString)", isDirectory: true)
        do {
            return try await Self.render(image: image, displays: displays, placement: placement,
                                         directory: outputDirectory, calibrations: calibrations)
        } catch {
            try? FileManager.default.removeItem(at: outputDirectory)
            throw error
        }
    }

    private static var defaultRootURL: URL {
        AppStorage.defaultRootURL
    }

    private func usablePreservedURL(for record: BackupRecord) -> URL? {
        guard let url = record.preservedURL, backupFiles.status(of: url) == .readableFile else { return nil }
        return url
    }

    private func t(_ key: String, _ arguments: CVarArg...) -> String {
        AppLocalization.text(key, language: language, arguments: arguments)
    }

    private func beginOperation() throws {
        guard !busy else { throw WallpaperServiceError.operationInProgress }
        if let backupLoadError { throw WallpaperServiceError.invalidBackup(backupLoadError) }
        busy = true
    }

    private func verifyTopology(_ snapshot: [DisplayDescriptor]) throws {
        let current = client.displays()
        guard !snapshot.isEmpty,
              Set(snapshot.map(\.id)).count == snapshot.count else {
            throw WallpaperServiceError.topologyChanged
        }
        let unchanged = snapshot.allSatisfy { expected in
            current.contains { actual in
                actual.id == expected.id && actual.frame == expected.frame &&
                actual.pixelWidth == expected.pixelWidth && actual.pixelHeight == expected.pixelHeight
            }
        }
        guard unchanged else { throw WallpaperServiceError.topologyChanged }
    }

    private func persist(_ records: [String: BackupRecord]) throws {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let manifest = BackupManifest(version: 1, records: records.values.sorted { $0.displayID < $1.displayID })
        let data = try encoder.encode(manifest)
        try data.write(to: rootURL.appendingPathComponent("backup.json"), options: .atomic)
        backups = records
    }

    nonisolated private static func render(image: CGImage, displays: [DisplayDescriptor], placement: WallpaperPlacement,
                                          directory: URL, calibrations: [String: DisplayCalibration]) async throws -> [URL] {
        try await Task.detached(priority: .userInitiated) {
            let geometry = try WallpaperGeometry(displays: displays,
                                                 imageSize: CGSize(width: image.width, height: image.height),
                                                 placement: placement, calibrations: calibrations)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            return try displays.enumerated().map { index, display in
                try autoreleasepool {
                    let rendered = try WallpaperRenderer.render(image: image, display: display, geometry: geometry)
                    let url = directory.appendingPathComponent("screen-\(index + 1).png")
                    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
                        throw WallpaperServiceError.pngWriteFailed(display.name)
                    }
                    CGImageDestinationAddImage(destination, rendered, nil)
                    guard CGImageDestinationFinalize(destination) else {
                        throw WallpaperServiceError.pngWriteFailed(display.name)
                    }
                    return url
                }
            }
        }.value
    }
}
