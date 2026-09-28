import AppKit
import CoreGraphics
import WaallpaperCore

/// Temporary, mouse-transparent guides. This controller never changes desktop images.
@MainActor
final class AlignmentOverlayController {
    var onStop: (() -> Void)?
    var language: AppLanguage = .system
    private(set) var isVisible = false

    private var windows: [String: AlignmentGuideWindow] = [:]
    private weak var editorWindow: NSWindow?
    private var originalEditorLevel: NSWindow.Level?
    private var observers: [NSObjectProtocol] = []
    private var escapeMonitor: Any?
    private let guideLevel = NSWindow.Level.floating

    func show(displays: [DisplayDescriptor], calibrations: [String: DisplayCalibration], editorWindow: NSWindow?) throws {
        if isVisible {
            try update(displays: displays, calibrations: calibrations)
            return
        }
        let candidates = [editorWindow, NSApp.keyWindow, NSApp.mainWindow].compactMap { $0 } + NSApp.windows
        guard let editor = candidates.first(where: {
            $0.isVisible && !$0.isMiniaturized && $0.canBecomeMain && $0.styleMask.contains(.titled)
        }) else {
            throw OverlayError.editorRequired
        }
        // Accessibility/menu actions can arrive while the editor is visible but not key.
        // Keep keyboard focus in the editor so Escape always reaches the local monitor.
        NSApp.activate(ignoringOtherApps: true)
        editor.makeKeyAndOrderFront(nil)
        self.editorWindow = editor
        originalEditorLevel = editor.level
        editor.level = NSWindow.Level(rawValue: max(editor.level.rawValue, guideLevel.rawValue + 1))
        do {
            try renderAndDisplay(displays: displays, calibrations: calibrations)
            isVisible = true
            editor.orderFrontRegardless()
            installObservers(for: editor)
        } catch {
            cleanUp(notify: false)
            throw error
        }
    }

    func update(displays: [DisplayDescriptor], calibrations: [String: DisplayCalibration]) throws {
        guard isVisible else { return }
        guard let editorWindow, editorWindow.isVisible, !editorWindow.isMiniaturized else {
            stop()
            return
        }
        do {
            try renderAndDisplay(displays: displays, calibrations: calibrations)
            editorWindow.orderFrontRegardless()
        } catch {
            stop()
            throw error
        }
    }

    func stop() { cleanUp(notify: true) }

    private func renderAndDisplay(displays: [DisplayDescriptor], calibrations: [String: DisplayCalibration]) throws {
        let geometry = try WallpaperGeometry(displays: displays, imageSize: CGSize(width: 1, height: 1),
                                             calibrations: calibrations)
        let screens = currentScreens()
        var images: [String: CGImage] = [:]
        for display in displays {
            guard let screen = screens[display.id], screen.frame == display.frame else {
                throw WallpaperError.displayNotInLayout
            }
            let backing = screen.convertRectToBacking(NSRect(origin: .zero, size: screen.frame.size))
            guard Int(backing.width.rounded()) == display.pixelWidth,
                  Int(backing.height.rounded()) == display.pixelHeight else {
                throw WallpaperError.displayNotInLayout
            }
            images[display.id] = try autoreleasepool {
                try AlignmentPattern.render(display: display, geometry: geometry, maxPixelDimension: 2_000)
            }
        }

        let selected = Set(displays.map(\.id))
        for id in Array(windows.keys) where !selected.contains(id) {
            windows.removeValue(forKey: id)?.close()
        }
        for display in displays {
            guard let screen = screens[display.id], let image = images[display.id] else { continue }
            let window = windows[display.id] ?? makeWindow(frame: screen.frame)
            window.setFrame(screen.frame, display: false)
            if let imageView = window.contentView as? NSImageView {
                imageView.image = NSImage(cgImage: image, size: screen.frame.size)
            }
            windows[display.id] = window
            window.orderFrontRegardless()
        }
    }

    private func makeWindow(frame: NSRect) -> AlignmentGuideWindow {
        let window = AlignmentGuideWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.level = guideLevel
        window.isOpaque = true
        window.backgroundColor = .black
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.hidesOnDeactivate = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .transient]
        let imageView = NSImageView(frame: NSRect(origin: .zero, size: frame.size))
        imageView.imageScaling = .scaleAxesIndependently
        imageView.autoresizingMask = [.width, .height]
        window.contentView = imageView
        return window
    }

    private func currentScreens() -> [String: NSScreen] {
        var result: [String: NSScreen] = [:]
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { continue }
            let displayID = CGDirectDisplayID(number.uint32Value)
            guard CGDisplayMirrorsDisplay(displayID) == kCGNullDirectDisplay,
                  let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else { continue }
            result[CFUUIDCreateString(nil, uuid) as String] = screen
        }
        return result
    }

    private func installObservers(for editor: NSWindow) {
        let center = NotificationCenter.default
        for name in [NSApplication.didResignActiveNotification, NSApplication.didHideNotification,
                     NSApplication.willTerminateNotification, NSApplication.didChangeScreenParametersNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.stop() }
            })
        }
        for name in [NSWindow.willCloseNotification, NSWindow.didMiniaturizeNotification] {
            observers.append(center.addObserver(forName: name, object: editor, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.stop() }
            })
        }
        observers.append(center.addObserver(forName: NSWindow.didChangeOcclusionStateNotification,
                                            object: editor, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.editorWindow?.isVisible != true || self.editorWindow?.isMiniaturized == true {
                    self.stop()
                }
            }
        })
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            let consumed = MainActor.assumeIsolated {
                guard self?.isVisible == true else { return false }
                self?.stop()
                return true
            }
            return consumed ? nil : event
        }
    }

    private func cleanUp(notify: Bool) {
        let wasVisible = isVisible
        isVisible = false
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        escapeMonitor = nil
        for window in windows.values {
            (window.contentView as? NSImageView)?.image = nil
            window.orderOut(nil)
            window.close()
        }
        windows.removeAll()
        if let editorWindow, let originalEditorLevel { editorWindow.level = originalEditorLevel }
        editorWindow = nil
        originalEditorLevel = nil
        if notify && wasVisible { onStop?() }
    }

    deinit {
        // AppKit-owned visible windows must not outlive the controller that can stop them.
        let retainedWindows = Array(windows.values)
        let retainedEditor = editorWindow
        let level = originalEditorLevel
        let retainedObservers = observers
        let monitor = escapeMonitor
        Task { @MainActor in
            retainedObservers.forEach(NotificationCenter.default.removeObserver)
            if let monitor { NSEvent.removeMonitor(monitor) }
            retainedWindows.forEach { $0.orderOut(nil); $0.close() }
            if let retainedEditor, let level { retainedEditor.level = level }
        }
    }

    private enum OverlayError: AppLocalizableError {
        case editorRequired

        func localizedDescription(language: AppLanguage) -> String {
            AppLocalization.text("alignment.error.editorRequired", language: language)
        }
    }
}

@MainActor
private final class AlignmentGuideWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}
