// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Waallpaper",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Waallpaper", targets: ["Waallpaper"])],
    targets: [
        .target(name: "WaallpaperCore", resources: [.process("Resources")]),
        .target(name: "WaallpaperDesktop", dependencies: ["WaallpaperCore"]),
        .executableTarget(name: "Waallpaper", dependencies: ["WaallpaperCore", "WaallpaperDesktop"]),
        .testTarget(name: "WaallpaperCoreTests", dependencies: ["WaallpaperCore"]),
        .testTarget(name: "WaallpaperDesktopTests", dependencies: ["WaallpaperDesktop"]),
        .testTarget(name: "WaallpaperAppTests", dependencies: ["Waallpaper"])
    ],
    swiftLanguageModes: [.v5]
)
