import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct WaallpaperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = WallpaperModel()

    var body: some Scene {
        Window("Waallpaper", id: "main") {
            ContentView(model: model)
                .frame(minWidth: 1000, minHeight: 700)
        }
        .defaultSize(width: 1180, height: 790)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(model.t("open_image_menu")) { model.chooseImage() }
                    .keyboardShortcut("o")
                    .disabled(model.isBusy)
            }
            CommandMenu(model.t("wallpaper_menu")) {
                Button(model.t("apply_selected")) { Task { await model.apply() } }
                    .keyboardShortcut(.return, modifiers: [.command])
                    .disabled(model.isBusy || model.geometry == nil)
                Button(model.t("export_png_menu")) { model.chooseExportFolder() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                    .disabled(model.isBusy || model.geometry == nil)
                Divider()
                Button(model.t("restore")) { model.restore() }
                    .disabled(model.isBusy || !model.canRestore)
            }
        }
    }
}
