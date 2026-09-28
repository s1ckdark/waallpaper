import Foundation

/// Reuse existing prototype data so wallpaper URLs and restore records stay valid.
public enum AppStorage {
    public static var defaultRootURL: URL {
        rootURL(in: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0])
    }

    public static func rootURL(in applicationSupport: URL) -> URL {
        let current = applicationSupport.appendingPathComponent("Waallpaper", isDirectory: true)
        let legacy = applicationSupport.appendingPathComponent("MoreWallpaper", isDirectory: true)
        if containsAppData(current) { return current }
        if containsAppData(legacy) { return legacy }
        return current
    }

    private static func containsAppData(_ directory: URL) -> Bool {
        ["preferences.json", "backup.json", "source.png"].contains {
            FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path)
        }
    }
}
