import AppKit
import WaallpaperCore

struct DesktopImageOptions: Codable, Equatable {
    struct Color: Codable, Equatable {
        let red: Double
        let green: Double
        let blue: Double
        let alpha: Double
    }

    var scaling: Int?
    var allowClipping: Bool?
    var fillColor: Color?

    static let exactFit = DesktopImageOptions(
        scaling: Int(NSImageScaling.scaleAxesIndependently.rawValue),
        allowClipping: false
    )

    init(scaling: Int? = nil, allowClipping: Bool? = nil, fillColor: Color? = nil) {
        self.scaling = scaling
        self.allowClipping = allowClipping
        self.fillColor = fillColor
    }

    init(dictionary: [NSWorkspace.DesktopImageOptionKey: Any]) throws {
        scaling = (dictionary[.imageScaling] as? NSNumber)?.intValue
        allowClipping = (dictionary[.allowClipping] as? NSNumber)?.boolValue
        if let color = dictionary[.fillColor] as? NSColor {
            guard let rgb = color.usingColorSpace(.genericRGB) else {
                throw WallpaperServiceError.backupUnavailable("backup_color_unavailable")
            }
            fillColor = Color(red: rgb.redComponent, green: rgb.greenComponent,
                              blue: rgb.blueComponent, alpha: rgb.alphaComponent)
        }
    }

    var dictionary: [NSWorkspace.DesktopImageOptionKey: Any] {
        var result: [NSWorkspace.DesktopImageOptionKey: Any] = [:]
        if let scaling { result[.imageScaling] = NSNumber(value: scaling) }
        if let allowClipping { result[.allowClipping] = NSNumber(value: allowClipping) }
        if let fillColor {
            result[.fillColor] = NSColor(colorSpace: .genericRGB, components: [
                fillColor.red, fillColor.green, fillColor.blue, fillColor.alpha
            ], count: 4)
        }
        return result
    }
}

struct DesktopImageState: Codable, Equatable {
    let url: URL
    let options: DesktopImageOptions
}

@MainActor
protocol DesktopClient {
    func displays() -> [DisplayDescriptor]
    func imageState(for displayID: String) throws -> DesktopImageState
    func setImage(_ state: DesktopImageState, for displayID: String) throws
}

@MainActor
final class WorkspaceDesktopClient: DesktopClient {
    func displays() -> [DisplayDescriptor] { DisplayCatalog.current() }

    func imageState(for displayID: String) throws -> DesktopImageState {
        let screen = try screen(for: displayID)
        guard let url = NSWorkspace.shared.desktopImageURL(for: screen), url.isFileURL else {
            throw DesktopBackupError(displayName: screen.localizedName)
        }
        let options = try DesktopImageOptions(dictionary: NSWorkspace.shared.desktopImageOptions(for: screen) ?? [:])
        return DesktopImageState(url: url, options: options)
    }

    func setImage(_ state: DesktopImageState, for displayID: String) throws {
        try NSWorkspace.shared.setDesktopImageURL(state.url, for: screen(for: displayID), options: state.options.dictionary)
    }

    private func screen(for id: String) throws -> NSScreen {
        guard let screen = DisplayCatalog.screens().first(where: { $0.1 == id })?.0 else {
            throw WallpaperServiceError.topologyChanged
        }
        return screen
    }
}

private struct DesktopBackupError: AppLocalizableError {
    let displayName: String
    func localizedDescription(language: AppLanguage) -> String {
        AppLocalization.text("error_backup", language: language, arguments: [
            AppLocalization.text("backup_image_unavailable", language: language, arguments: [displayName])
        ])
    }
}
