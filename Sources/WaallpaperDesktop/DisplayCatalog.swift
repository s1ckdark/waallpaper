import AppKit
import CoreGraphics
import WaallpaperCore

@MainActor
public enum DisplayCatalog {
    public static func current() -> [DisplayDescriptor] {
        screens().map { screen, id in
            let backing = screen.convertRectToBacking(NSRect(origin: .zero, size: screen.frame.size))
            return DisplayDescriptor(
                id: id,
                name: screen.localizedName,
                frame: screen.frame,
                pixelWidth: max(1, Int(backing.width.rounded())),
                pixelHeight: max(1, Int(backing.height.rounded()))
            )
        }
    }

    static func screens() -> [(NSScreen, String)] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }
            let displayID = CGDirectDisplayID(number.uint32Value)
            // A mirrored display does not provide another independently positioned desktop.
            guard CGDisplayMirrorsDisplay(displayID) == kCGNullDirectDisplay else { return nil }
            // Numeric display IDs may be reused after reconnect/reboot. Never associate a
            // persistent restore record with an unstable ID during a transient disconnect.
            guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else { return nil }
            let identifier = CFUUIDCreateString(nil, uuid) as String
            return (screen, identifier)
        }
    }
}
