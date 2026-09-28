import WaallpaperCore
import SwiftUI

struct CalibrationPanel: View {
    @ObservedObject var model: WallpaperModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "slider.horizontal.3").foregroundStyle(.orange)
                Picker(model.t("calibration_display"), selection: Binding(
                    get: { model.calibrationDisplay?.id ?? "" },
                    set: { model.calibrationDisplayID = $0 }
                )) {
                    ForEach(model.selectedDisplays) { display in Text(display.name).tag(display.id) }
                }
                .frame(maxWidth: 320)
                .accessibilityIdentifier("calibrationDisplayPicker")
                Spacer(minLength: 8)
                Button(model.t("reset_display")) {
                    if let display = model.calibrationDisplay { model.resetCalibration(for: display.id) }
                }
                .disabled(model.calibrationDisplay == nil || (model.displayLayoutMode == .system &&
                    (model.calibrationDisplay.map { model.calibration(for: $0.id) == DisplayCalibration() } ?? true)))
                Button(model.t(model.displayLayoutMode == .manual ? "import_system_layout" : "reset_all")) { model.resetAllCalibrations() }
                    .disabled(model.activeCalibrations.isEmpty)
            }
            Text(model.t(model.displayLayoutMode == .manual ? "manual_layout_help" : "system_layout_help"))
                .font(.system(size: 10)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 16) {
                Toggle(model.t("show_alignment_guides"), isOn: $model.showsAlignmentGuides)
                    .fixedSize()
                    .accessibilityIdentifier("alignmentGuidesToggle")
                Toggle(model.t("snap_edges"), isOn: $model.snapEnabled)
                    .fixedSize()
                    .accessibilityIdentifier("snapEdgesToggle")
                Spacer(minLength: 0)
                Button { model.toggleAlignmentPattern() } label: {
                    Label(model.t(model.isShowingAlignmentPattern ? "stop_alignment_pattern" : "show_alignment_pattern"),
                          systemImage: model.isShowingAlignmentPattern ? "xmark.rectangle" : "grid")
                }
                .accessibilityIdentifier("alignmentPatternButton")
                .help(model.t("alignment_pattern_help"))
            }
            if let display = model.calibrationDisplay {
                HStack(alignment: .top, spacing: 20) {
                    CalibrationControl(model: model, title: model.t("relative_size"), unit: "%", value: binding(display.id, \.scale, multiplier: 100),
                                       range: 25...400, step: 1)
                    CalibrationControl(model: model, title: model.t("offset_x"), unit: "pt", value: binding(display.id, \.offsetX),
                                       range: -10000...10000, step: 1)
                    CalibrationControl(model: model, title: model.t("offset_y"), unit: "pt", value: binding(display.id, \.offsetY),
                                       range: -10000...10000, step: 1)
                }
                .id(display.id)
                Text(model.t("calibration_size_help"))
                    .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .controlSize(.small)
        .padding(14)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
        .disabled(model.isBusy)
    }

    private func binding(_ id: String, _ keyPath: WritableKeyPath<DisplayCalibration, Double>, multiplier: Double = 1) -> Binding<Double> {
        Binding(get: { model.calibration(for: id)[keyPath: keyPath] * multiplier }, set: { value in
            var calibration = model.calibration(for: id)
            calibration[keyPath: keyPath] = value / multiplier
            model.setCalibration(calibration, for: id)
        })
    }
}

private struct CalibrationControl: View {
    @ObservedObject var model: WallpaperModel
    let title: String
    let unit: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 11, weight: .medium))
                .lineLimit(1).minimumScaleFactor(0.85)
            HStack {
                CalibrationNumberField(model: model, value: $value, range: range, label: title)
                    .frame(width: 62)
                Text(unit).font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer(minLength: 2)
                Stepper(title, value: $value, in: range, step: step)
                    .labelsHidden().fixedSize()
                    .accessibilityLabel(model.t("fine_adjustment", title))
            }
            // Avoid native tick marks for every value in large offset ranges.
            Slider(value: Binding(get: { value }, set: { value = ($0 / step).rounded() * step }), in: range)
                .accessibilityLabel(model.t("slider_accessibility", title))
        }
    }
}

/// Keep unfinished numeric input separate from valid geometry; commit on Return or focus loss.
private struct CalibrationNumberField: View {
    @ObservedObject var model: WallpaperModel
    @Binding var value: Double
    let range: ClosedRange<Double>
    let label: String
    @State private var text = ""
    @State private var invalidInput = false
    @FocusState private var focused: Bool

    var body: some View {
        TextField(label, text: $text)
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 11, design: .monospaced))
            .multilineTextAlignment(.trailing)
            .focused($focused)
            .accessibilityLabel(model.t("value_accessibility", label))
            .onAppear { updateText() }
            .onChange(of: value) { _, _ in if !focused { updateText() } }
            .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
            .onSubmit { commit(); focused = false }
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(invalidInput ? Color.red : .clear))
            .help(invalidInput ? model.t("invalid_number") : model.t("number_range_help", Int(range.lowerBound), Int(range.upperBound)))
    }

    private func commit() {
        guard let number = Double(text.trimmingCharacters(in: .whitespaces)), number.isFinite else {
            invalidInput = true
            updateText()
            return
        }
        invalidInput = false
        value = min(range.upperBound, max(range.lowerBound, number))
        updateText()
    }

    private func updateText() {
        text = value == value.rounded() ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }
}
