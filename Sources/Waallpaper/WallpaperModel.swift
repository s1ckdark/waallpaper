import AppKit
import Combine
import ImageIO
import WaallpaperCore
import WaallpaperDesktop
import UniformTypeIdentifiers

@MainActor
final class WallpaperModel: ObservableObject {
    @Published private(set) var displays: [DisplayDescriptor] = []
    @Published private(set) var image: CGImage?
    @Published private(set) var imageName = ""
    @Published private(set) var isSample = true
    @Published private(set) var isBusy = false
    @Published private(set) var status = ""
    @Published private(set) var canRestore = false
    @Published private(set) var backupNotice: String?
    @Published var errorMessage: String?
    @Published var zoom: Double = 1 { didSet { savePreferences() } }
    @Published var horizontalOffset: Double = 0 { didSet { savePreferences() } }
    @Published var verticalOffset: Double = 0 { didSet { savePreferences() } }
    @Published private(set) var excludedIDs: Set<String> = []
    @Published private(set) var calibrations: [String: DisplayCalibration] = [:]
    @Published private(set) var manualCalibrations: [String: DisplayCalibration] = [:]
    @Published var displayLayoutMode: DisplayLayoutMode = .system {
        didSet {
            guard isReady else { return }
            if displayLayoutMode == .manual {
                seedManualLayouts()
                isCalibrating = true
            }
            updateAlignmentPattern()
            savePreferences()
        }
    }
    @Published var language: AppLanguage = .system {
        didSet {
            refreshLocalizedText()
            savePreferences()
        }
    }
    @Published var showsAlignmentGuides = true { didSet { savePreferences() } }
    @Published var snapEnabled = true { didSet { savePreferences() } }
    @Published private(set) var isShowingAlignmentPattern = false
    @Published var isCalibrating = false {
        didSet { if !isCalibrating { stopAlignmentPattern() } }
    }
    @Published var calibrationDisplayID: String?

    private let service: WallpaperService
    private let alignmentController = AlignmentOverlayController()
    private var statusKey = "status_initial"
    private var statusArguments: [CVarArg] = []
    private var lastError: Error?
    private let storageURL: URL
    private let displayProvider: @MainActor () -> [DisplayDescriptor]
    private var screenObserver: NSObjectProtocol?
    private var isReady = false

    var selectedDisplays: [DisplayDescriptor] { displays.filter { !excludedIDs.contains($0.id) } }
    var activeCalibrations: [String: DisplayCalibration] {
        displayLayoutMode == .manual ? manualCalibrations : calibrations
    }
    var placement: WallpaperPlacement {
        WallpaperPlacement(zoom: zoom, horizontalOffset: horizontalOffset, verticalOffset: verticalOffset)
    }
    var geometry: WallpaperGeometry? {
        guard let image else { return nil }
        return try? WallpaperGeometry(displays: selectedDisplays,
                                      imageSize: CGSize(width: image.width, height: image.height),
                                      placement: placement, calibrations: activeCalibrations)
    }
    var imageSizeLabel: String {
        guard let image else { return t("no_image") }
        return "\(image.width) × \(image.height) px"
    }
    var resolutionWarning: Bool {
        guard let image, let geometry else { return false }
        let sourcePixelsPerPoint = CGFloat(image.width) / geometry.imageRect.width
        return selectedDisplays.contains {
            CGFloat($0.pixelWidth) / geometry.normalizedFrame(for: $0).width > sourcePixelsPerPoint * 1.05
        }
    }

    var calibrationDisplay: DisplayDescriptor? {
        selectedDisplays.first { $0.id == calibrationDisplayID } ?? selectedDisplays.first
    }

    var hasCalibration: Bool {
        selectedDisplays.contains { calibration(for: $0.id) != DisplayCalibration() }
    }

    func calibration(for id: String) -> DisplayCalibration { activeCalibrations[id] ?? DisplayCalibration() }

    func setCalibration(_ value: DisplayCalibration, for id: String, persist: Bool = true) {
        guard !isBusy else { return }
        var adjusted = value
        if displayLayoutMode == .manual {
            adjusted.referenceFrame = adjusted.referenceFrame ?? manualCalibrations[id]?.referenceFrame
                ?? displays.first(where: { $0.id == id })?.frame
            guard adjusted.referenceFrame != nil, adjusted.isValid else { return }
            manualCalibrations[id] = adjusted
        } else {
            adjusted.referenceFrame = nil
            guard adjusted.isValid else { return }
            calibrations[id] = adjusted == DisplayCalibration() ? nil : adjusted
        }
        updateAlignmentPattern()
        if persist { savePreferences() }
    }

    func resetCalibration(for id: String) {
        guard !isBusy else { return }
        if displayLayoutMode == .manual, let display = displays.first(where: { $0.id == id }) {
            manualCalibrations[id] = DisplayCalibration(referenceFrame: display.frame)
        } else {
            calibrations.removeValue(forKey: id)
        }
        updateAlignmentPattern()
        savePreferences()
    }

    func resetAllCalibrations() {
        guard !isBusy else { return }
        if displayLayoutMode == .manual {
            manualCalibrations = Dictionary(uniqueKeysWithValues: displays.map {
                ($0.id, DisplayCalibration(referenceFrame: $0.frame))
            })
        } else {
            calibrations = [:]
        }
        updateAlignmentPattern()
        savePreferences()
    }

    init(storageURL: URL? = nil,
         displayProvider: @escaping @MainActor () -> [DisplayDescriptor] = { DisplayCatalog.current() }) {
        let resolvedStorageURL = storageURL ?? AppStorage.defaultRootURL
        self.storageURL = resolvedStorageURL
        self.displayProvider = displayProvider
        service = WallpaperService(rootURL: resolvedStorageURL)
        image = SampleArtwork.make()
        if let data = try? Data(contentsOf: self.storageURL.appendingPathComponent("preferences.json")),
           let preferences = try? JSONDecoder().decode(Preferences.self, from: data) {
            zoom = preferences.zoom.isFinite ? min(3, max(1, preferences.zoom)) : 1
            horizontalOffset = preferences.horizontalOffset.isFinite ? min(1, max(-1, preferences.horizontalOffset)) : 0
            verticalOffset = preferences.verticalOffset.isFinite ? min(1, max(-1, preferences.verticalOffset)) : 0
            excludedIDs = preferences.excludedIDs
            calibrations = preferences.validCalibrations
            manualCalibrations = preferences.validManualCalibrations
            displayLayoutMode = preferences.displayLayoutMode ?? .system
            // Existing releases only had Korean UI; preserve it when upgrading old settings.
            language = preferences.language ?? .korean
            showsAlignmentGuides = preferences.showsAlignmentGuides ?? true
            snapEnabled = preferences.snapEnabled ?? true
            if let name = preferences.imageName {
                do {
                    image = try WallpaperImageLoader.load(url: self.storageURL.appendingPathComponent("source.png"))
                    imageName = name
                    isSample = false
                } catch {
                    setStatus("status_saved_image_failed")
                }
            }
        }
        alignmentController.onStop = { [weak self] in self?.isShowingAlignmentPattern = false }
        refreshLocalizedText()
        refreshDisplays()
        canRestore = service.hasBackup
        backupNotice = service.backupNotice(language: language)
        isReady = true
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshDisplays() }
        }
    }

    deinit {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    }

    func refreshDisplays() {
        stopAlignmentPattern()
        displays = displayProvider()
        if displayLayoutMode == .manual { seedManualLayouts() }
        if selectedDisplays.isEmpty, let first = displays.first { excludedIDs.remove(first.id) }
        if !selectedDisplays.contains(where: { $0.id == calibrationDisplayID }) {
            calibrationDisplayID = selectedDisplays.first?.id
        }
        savePreferences()
    }

    func toggleDisplay(_ display: DisplayDescriptor) {
        guard !isBusy else { return }
        if excludedIDs.contains(display.id) {
            excludedIDs.remove(display.id)
        } else if selectedDisplays.count > 1 {
            excludedIDs.insert(display.id)
        }
        if !selectedDisplays.contains(where: { $0.id == calibrationDisplayID }) {
            calibrationDisplayID = selectedDisplays.first?.id
        }
        updateAlignmentPattern()
        savePreferences()
    }

    func resetPlacement() {
        zoom = 1
        horizontalOffset = 0
        verticalOffset = 0
    }

    func chooseImage() {
        guard !isBusy else { return }
        stopAlignmentPattern()
        let panel = NSOpenPanel()
        panel.title = t("choose_image_title")
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await importImage(from: url) }
    }

    func importImage(from url: URL) async {
        guard !isBusy, url.isFileURL else { return }
        stopAlignmentPattern()
        isBusy = true
        setStatus("status_loading")
        defer { isBusy = false }
        let sourceURL = storageURL.appendingPathComponent("source.png")
        do {
            let loaded = try await Task.detached(priority: .userInitiated) {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let loaded = try WallpaperImageLoader.load(url: url)
                try FileManager.default.createDirectory(at: sourceURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                let data = NSMutableData()
                guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
                    throw AppError("image_save_unavailable")
                }
                CGImageDestinationAddImage(destination, loaded, nil)
                guard CGImageDestinationFinalize(destination) else { throw AppError("image_save_failed") }
                try (data as Data).write(to: sourceURL, options: .atomic)
                return loaded
            }.value
            image = loaded
            imageName = url.lastPathComponent
            isSample = false
            resetPlacement()
            savePreferences()
            setStatus("status_loaded")
        } catch { report(error) }
    }

    func useSample() {
        guard !isBusy else { return }
        image = SampleArtwork.make()
        imageName = t("sample_name")
        isSample = true
        resetPlacement()
        savePreferences()
        setStatus("status_sample")
    }

    func apply() async {
        guard !isBusy, let image, !selectedDisplays.isEmpty else { return }
        stopAlignmentPattern()
        isBusy = true
        setStatus("status_applying")
        defer {
            isBusy = false
            canRestore = service.hasBackup
            backupNotice = service.backupNotice(language: language)
        }
        do {
            let files = try await service.apply(image: image, displays: selectedDisplays,
                                                placement: placement, calibrations: activeCalibrations)
            setStatus(service.backupNotice == nil ? "status_applied" : "status_applied_notice", files.count)
        } catch { report(error) }
    }

    func restore() {
        guard !isBusy else { return }
        stopAlignmentPattern()
        defer { backupNotice = service.backupNotice(language: language) }
        do {
            let count = try service.restore()
            if count > 0 { setStatus("status_restored", count) }
            else { setStatus("status_no_restore_display") }
            canRestore = service.hasBackup
        } catch {
            canRestore = service.hasBackup
            report(error)
        }
    }

    func chooseExportFolder() {
        guard !isBusy, image != nil, !selectedDisplays.isEmpty else { return }
        stopAlignmentPattern()
        let panel = NSOpenPanel()
        panel.title = t("choose_export_title")
        panel.prompt = t("export")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let directory = panel.url else { return }
        Task { await export(to: directory) }
    }

    func export(to directory: URL) async {
        guard !isBusy, let image, !selectedDisplays.isEmpty else { return }
        stopAlignmentPattern()
        isBusy = true
        setStatus("status_exporting")
        defer { isBusy = false }
        do {
            let files = try await service.export(image: image, displays: selectedDisplays, placement: placement,
                                                 to: directory, calibrations: activeCalibrations)
            setStatus("status_exported", files.count)
            NSWorkspace.shared.activateFileViewerSelecting(files)
        } catch { report(error) }
    }

    func t(_ key: String, _ arguments: CVarArg...) -> String {
        AppLocalization.text(key, language: language, arguments: arguments)
    }

    func commitCalibrationChanges() { savePreferences() }

    func toggleAlignmentPattern() {
        guard !isBusy, isCalibrating else { return }
        if alignmentController.isVisible { stopAlignmentPattern(); return }
        do {
            try alignmentController.show(displays: selectedDisplays, calibrations: activeCalibrations, editorWindow: NSApp.keyWindow)
            isShowingAlignmentPattern = alignmentController.isVisible
        } catch { report(error) }
    }

    private func stopAlignmentPattern() {
        alignmentController.stop()
        isShowingAlignmentPattern = false
    }

    private func updateAlignmentPattern() {
        guard alignmentController.isVisible else { return }
        do {
            try alignmentController.update(displays: selectedDisplays, calibrations: activeCalibrations)
            isShowingAlignmentPattern = alignmentController.isVisible
        } catch {
            stopAlignmentPattern()
            report(error)
        }
    }

    private func setStatus(_ key: String, _ arguments: CVarArg...) {
        statusKey = key
        statusArguments = arguments
        lastError = nil
        status = AppLocalization.text(key, language: language, arguments: arguments)
    }

    private func seedManualLayouts() {
        for display in displays where manualCalibrations[display.id] == nil {
            var value = calibrations[display.id] ?? DisplayCalibration()
            value.referenceFrame = display.frame
            manualCalibrations[display.id] = value
        }
    }

    private func refreshLocalizedText() {
        service.language = language
        alignmentController.language = language
        if isSample { imageName = t("sample_name") }
        if let lastError {
            status = AppLocalization.description(for: lastError, language: language)
            if errorMessage != nil { errorMessage = status }
        } else {
            status = AppLocalization.text(statusKey, language: language, arguments: statusArguments)
        }
        backupNotice = service.backupNotice(language: language)
    }

    private func report(_ error: Error) {
        lastError = error
        status = AppLocalization.description(for: error, language: language)
        errorMessage = status
    }

    private func savePreferences() {
        guard isReady else { return }
        do {
            try FileManager.default.createDirectory(at: storageURL, withIntermediateDirectories: true)
            let preferences = Preferences(zoom: zoom, horizontalOffset: horizontalOffset,
                                          verticalOffset: verticalOffset, excludedIDs: excludedIDs,
                                          imageName: isSample ? nil : imageName, calibrations: calibrations,
                                          language: language, showsAlignmentGuides: showsAlignmentGuides,
                                          snapEnabled: snapEnabled, displayLayoutMode: displayLayoutMode,
                                          manualCalibrations: manualCalibrations)
            try JSONEncoder().encode(preferences).write(to: storageURL.appendingPathComponent("preferences.json"), options: .atomic)
        } catch {
            setStatus("status_preferences_failed")
        }
    }
}

struct Preferences: Codable {
    let zoom: Double
    let horizontalOffset: Double
    let verticalOffset: Double
    let excludedIDs: Set<String>
    let imageName: String?
    var calibrations: [String: DisplayCalibration]? = nil
    var language: AppLanguage? = nil
    var showsAlignmentGuides: Bool? = nil
    var snapEnabled: Bool? = nil
    var displayLayoutMode: DisplayLayoutMode? = nil
    var manualCalibrations: [String: DisplayCalibration]? = nil

    var validCalibrations: [String: DisplayCalibration] {
        (calibrations ?? [:]).filter { $0.value.isValid }.mapValues {
            var value = $0
            value.referenceFrame = nil
            return value
        }
    }

    var validManualCalibrations: [String: DisplayCalibration] {
        (manualCalibrations ?? [:]).filter { $0.value.isValid && $0.value.referenceFrame != nil }
    }
}

struct AppError: AppLocalizableError {
    let key: String
    init(_ key: String) { self.key = key }
    func localizedDescription(language: AppLanguage) -> String {
        AppLocalization.text(key, language: language)
    }
}
