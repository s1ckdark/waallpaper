import WaallpaperCore
import SwiftUI
import UniformTypeIdentifiers

enum Palette {
    static let accent = Color(red: 0.93, green: 0.48, blue: 0.27)
    static let canvas = Color(red: 0.075, green: 0.095, blue: 0.13)
    static let muted = Color(red: 0.59, green: 0.64, blue: 0.70)
}

struct ContentView: View {
    @ObservedObject var model: WallpaperModel
    @State private var isDropTargeted = false

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 288)
            Divider()
            workspace
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(Palette.accent)
        .environment(\.locale, Locale(identifier: model.language.resolvedCode()))
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first, !model.isBusy else { return false }
            Task { await model.importImage(from: url) }
            return true
        } isTargeted: { isDropTargeted = $0 }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 12).fill(Palette.accent.opacity(0.12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.accent, lineWidth: 3))
                    .overlay {
                        Label(model.t("drop_image"), systemImage: "photo.badge.plus")
                            .font(.title2.bold()).padding(24).background(.regularMaterial, in: Capsule())
                    }
                    .padding(8).allowsHitTesting(false)
            }
        }
        .alert(model.t("operation_error"), isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button(model.t("ok"), role: .cancel) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "rectangle.split.2x1.fill")
                    .font(.system(size: 24, weight: .semibold)).foregroundStyle(Palette.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Waallpaper").font(.system(size: 19, weight: .bold, design: .rounded))
                    Text(model.t("subtitle")).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 14)

            Picker(model.t("language"), selection: $model.language) {
                Text(model.t("language_system")).tag(AppLanguage.system)
                Text("한국어").tag(AppLanguage.korean)
                Text("English").tag(AppLanguage.english)
            }
            .accessibilityIdentifier("languagePicker")
            .padding(.bottom, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    imageSection
                    Divider()
                    placementSection
                    Divider()
                    displaySection
                }.padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)

            Divider().padding(.bottom, 13)
            Button { model.restore() } label: {
                Label(model.t("restore"), systemImage: "arrow.uturn.backward")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .disabled(!model.canRestore || model.isBusy)
            .help(model.t("restore_help"))
            if let notice = model.backupNotice {
                Label(notice, systemImage: "exclamationmark.circle")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 9)
                    .accessibilityIdentifier("backupNotice")
            }
        }
        .padding(22)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
    }

    private var imageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("01", model.t("image_section"))
            if let image = model.image {
                Image(decorative: image, scale: 1)
                    .resizable().scaledToFill()
                    .frame(width: 244, height: 84)
                    .clipped().clipShape(RoundedRectangle(cornerRadius: 9))
                    .accessibilityLabel(model.t("selected_image"))
            }
            Text(model.imageName).font(.system(size: 12, weight: .medium)).lineLimit(1).help(model.imageName)
            Text(model.imageSizeLabel).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
            Button { model.chooseImage() } label: {
                Label(model.t("choose_image"), systemImage: "plus").frame(maxWidth: .infinity)
            }
            .controlSize(.large).disabled(model.isBusy)
            HStack {
                Text(model.t("drop_hint"))
                Spacer(minLength: 0)
                if !model.isSample {
                    Button(model.t("sample")) { model.useSample() }.buttonStyle(.plain).foregroundStyle(Palette.accent)
                        .disabled(model.isBusy)
                }
            }
            .font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }

    private var placementSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                sectionLabel("02", model.t("placement_section"))
                Spacer()
                Button(model.t("reset")) { model.resetPlacement() }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
                    .disabled(model.isBusy)
            }
            adjustment(model.t("zoom"), value: $model.zoom, range: 1...3,
                       label: "\(Int((model.zoom * 100).rounded()))%", symbol: "plus.magnifyingglass")
            adjustment(model.t("horizontal_position"), value: $model.horizontalOffset, range: -1...1,
                       label: positionLabel(model.horizontalOffset), symbol: "arrow.left.and.right")
            adjustment(model.t("vertical_position"), value: $model.verticalOffset, range: -1...1,
                       label: positionLabel(model.verticalOffset), symbol: "arrow.up.and.down")
            Text(model.t("placement_help"))
                .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
            if model.resolutionWarning {
                Label(model.t("resolution_warning"), systemImage: "info.circle")
                    .font(.system(size: 11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
        }
        .disabled(model.isBusy)
    }

    private var displaySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionLabel("03", model.t("display_section"))
                Spacer()
                Text("\(model.selectedDisplays.count)/\(model.displays.count)")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
            }
            ForEach(Array(model.displays.enumerated()), id: \.element.id) { index, display in
                let selected = !model.excludedIDs.contains(display.id)
                Button { model.toggleDisplay(display) } label: {
                    HStack(spacing: 10) {
                        Text("\(index + 1)").font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .frame(width: 27, height: 25)
                            .background(selected ? Palette.accent.opacity(0.14) : Color.secondary.opacity(0.08),
                                        in: RoundedRectangle(cornerRadius: 5))
                            .foregroundStyle(selected ? Palette.accent : .secondary)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(display.name).font(.system(size: 11, weight: .medium)).lineLimit(1)
                            Text("\(display.pixelWidth) × \(display.pixelHeight) px")
                                .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selected ? Palette.accent : .secondary)
                    }
                    .padding(9)
                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain).disabled(model.isBusy)
                .accessibilityLabel(model.t("display_selection_accessibility", display.name, model.t(selected ? "selected" : "not_selected")))
                .help(selected && model.selectedDisplays.count == 1 ? model.t("minimum_display") : model.t("select_display_help"))
            }
            if model.displays.count == 1 {
                Text(model.t("connect_display_hint"))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Button {
                model.isCalibrating.toggle()
            } label: {
                Label(model.isCalibrating ? model.t("close_calibration") : model.t("open_calibration"), systemImage: "slider.horizontal.3")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large).disabled(model.isBusy || model.selectedDisplays.isEmpty)
        }
    }

    private var workspace: some View {
        VStack(alignment: .leading, spacing: model.isCalibrating ? 12 : 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(model.t("headline")).font(.system(size: 26, weight: .semibold))
                    Text(model.t("headline_detail"))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Label(model.t("connected_displays", model.displays.count), systemImage: "circle.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(red: 0.22, green: 0.60, blue: 0.45))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color.green.opacity(0.08), in: Capsule())
            }
            .padding(.top, 5)

            VStack(spacing: 0) {
                HStack {
                    Label(model.t("layout_preview"), systemImage: "rectangle.3.group")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.9))
                    Spacer()
                    Picker(model.t("layout_mode"), selection: $model.displayLayoutMode) {
                        Text(model.t("layout_system")).tag(DisplayLayoutMode.system)
                        Text(model.t("layout_manual")).tag(DisplayLayoutMode.manual)
                    }
                    .labelsHidden().frame(width: 172).controlSize(.small)
                    .disabled(model.isBusy)
                    .accessibilityIdentifier("displayLayoutModePicker")
                    if model.hasCalibration {
                        Text(model.t("calibration_active")).font(.system(size: 10)).foregroundStyle(Palette.accent)
                    }
                    Button {
                        model.isCalibrating.toggle()
                    } label: {
                        Label(model.isCalibrating ? model.t("finish_calibration") : model.t("calibrate_displays"), systemImage: "slider.horizontal.3")
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                    .tint(model.isCalibrating ? Palette.accent : .gray)
                    .foregroundStyle(.white)
                    .disabled(model.isBusy || model.selectedDisplays.isEmpty)
                    .accessibilityIdentifier("toggleCalibration")
                }
                .padding(20)
                WallpaperCanvas(model: model)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                HStack(spacing: 7) {
                    Image(systemName: model.isCalibrating ? "cursorarrow" : "hand.draw")
                    Text(model.isCalibrating ? model.t("calibration_preview_help") : model.t("image_preview_help"))
                    Spacer()
                    if let geometry = model.geometry {
                        Text("\(Int(geometry.canvasSize.width)) × \(Int(geometry.canvasSize.height)) pt")
                            .font(.system(size: 10, design: .monospaced))
                    }
                }
                .font(.system(size: 11)).foregroundStyle(Palette.muted)
                .padding(20)
            }
            .background(Palette.canvas, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.primary.opacity(0.06)))

            if model.isCalibrating { CalibrationPanel(model: model) }

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "info.circle").foregroundStyle(.secondary)
                Text(model.t("calibration_help"))
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
            }

            Divider()
            HStack(spacing: 14) {
                if model.isBusy { ProgressView().controlSize(.small) }
                Text(model.status).font(.system(size: 11)).foregroundStyle(.secondary)
                    .lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
                    .help(model.status)
                    .accessibilityIdentifier("operationStatus")
                Button { model.chooseExportFolder() } label: {
                    Label(model.t("export_png"), systemImage: "square.and.arrow.up")
                }
                .controlSize(.large).disabled(model.isBusy || model.geometry == nil)
                Button { Task { await model.apply() } } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "rectangle.on.rectangle")
                        Text(model.t("apply_displays", model.selectedDisplays.count)).fontWeight(.semibold)
                    }.padding(.horizontal, 5)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(model.isBusy || model.geometry == nil)
                .accessibilityIdentifier("applyWallpaper")
            }
        }
        .padding(28)
    }

    private func sectionLabel(_ number: String, _ label: String) -> some View {
        HStack(spacing: 7) {
            Text(number).font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(Palette.accent)
            Text(label).font(.system(size: 12, weight: .semibold))
        }
    }

    private func positionLabel(_ value: Double) -> String {
        abs(value) < 0.005 ? model.t("center") : String(format: "%+.0f%%", value * 100)
    }

    private func adjustment(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, label: String, symbol: String) -> some View {
        VStack(spacing: 5) {
            HStack {
                Label(title, systemImage: symbol).font(.system(size: 11))
                Spacer()
                Text(label).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
            }
            Slider(value: value, in: range).controlSize(.small).accessibilityLabel(title)
        }
    }
}
