import Foundation

enum BackupFileStatus {
    case readableFile
    case directory
    case unavailable
}

/// Source access can differ between the app and the macOS wallpaper service.
/// In particular, TCC may prevent this app from reading another app's container.
@MainActor
protocol BackupFileAccess {
    func status(of url: URL) -> BackupFileStatus
    func copy(at source: URL, to destination: URL) throws
}

@MainActor
struct FileSystemBackupFileAccess: BackupFileAccess {
    func status(of url: URL) -> BackupFileStatus {
        guard url.isFileURL else { return .unavailable }
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
        if values?.isDirectory == true { return .directory }
        if values?.isRegularFile == true && FileManager.default.isReadableFile(atPath: url.path) {
            return .readableFile
        }
        return .unavailable
    }

    func copy(at source: URL, to destination: URL) throws {
        try FileManager.default.copyItem(at: source, to: destination)
    }
}
