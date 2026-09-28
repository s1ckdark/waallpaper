import WaallpaperCore
import SwiftUI

struct WallpaperCanvas: View {
    @ObservedObject var model: WallpaperModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var displayDrag: DisplayDrag?
    @State private var imageDragStart: CGPoint?
    @State private var snapGuides: [CalibrationGuide] = []

    var body: some View {
        GeometryReader { proxy in
            if let image = model.image, let geometry = model.geometry {
                let worldBounds = bounds()
                let viewport = displayDrag?.viewport ?? CanvasViewport(available: proxy.size, bounds: worldBounds)
                Canvas { context, size in
                    drawBackground(context: context, size: size)
                    if model.isCalibrating { drawConnections(context: context, viewport: viewport) }

                    if model.isCalibrating && model.showsAlignmentGuides {
                        for display in model.selectedDisplays {
                            if let pattern = try? AlignmentPattern.render(display: display, geometry: geometry, maxPixelDimension: 800) {
                                context.draw(Image(decorative: pattern, scale: 1), in: viewport.rect(worldFrame(display)))
                            }
                        }
                        drawReferenceLines(context: context, viewport: viewport, worldBounds: worldBounds)
                    } else {
                        var clipping = Path()
                        for display in model.selectedDisplays { clipping.addRect(viewport.rect(worldFrame(display))) }
                        let worldImageRect = geometry.imageRect.offsetBy(dx: worldBounds.minX, dy: worldBounds.minY)
                        context.drawLayer { layer in
                            layer.clip(to: clipping)
                            layer.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
                            layer.draw(Image(decorative: image, scale: 1), in: viewport.rect(worldImageRect))
                        }
                    }
                    drawScreens(context: context, viewport: viewport)
                    for guide in snapGuides {
                        var path = Path()
                        switch guide.axis {
                        case .horizontal:
                            let y = viewport.point(CGPoint(x: 0, y: guide.coordinate)).y
                            path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y))
                        case .vertical:
                            let x = viewport.point(CGPoint(x: guide.coordinate, y: 0)).x
                            path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height))
                        }
                        context.stroke(path, with: .color(.mint), style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                    }
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard !model.isBusy else { return }
                        if model.isCalibrating {
                            editDisplay(value, viewport: viewport)
                        } else {
                            panImage(value, geometry: geometry, viewport: viewport)
                        }
                    }
                    .onEnded { _ in finishInteraction() })
                .accessibilityLabel(model.t("preview_accessibility", model.selectedDisplays.count))
                .accessibilityHint(model.t(model.isCalibrating ? "resize_display" : "move_display"))
                .accessibilityChildren {
                    if model.isCalibrating {
                        ForEach(model.selectedDisplays) { display in
                            Button(display.name) { model.calibrationDisplayID = display.id }
                        }
                    }
                }
            } else {
                ContentUnavailableView(model.t("preview_unavailable"), systemImage: "display",
                                       description: Text(model.t("preview_unavailable_detail")))
                    .foregroundStyle(.white)
            }
        }
        .onChange(of: model.isCalibrating) { _, _ in finishInteraction() }
        .onChange(of: model.displayLayoutMode) { _, _ in finishInteraction() }
        .onChange(of: model.displays) { _, _ in finishInteraction() }
        .onChange(of: model.selectedDisplays) { _, _ in finishInteraction() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { finishInteraction() } }
        .onDisappear { finishInteraction() }
    }

    private func editDisplay(_ value: DragGesture.Value, viewport: CanvasViewport) {
        if displayDrag == nil {
            let selected = model.calibrationDisplay
            let hitCorner = selected.flatMap { display in
                let frame = viewport.rect(worldFrame(display))
                return CalibrationCorner.allCases.first { corner in
                    let point = cornerPoint(corner, frame: frame)
                    return hypot(point.x - value.startLocation.x, point.y - value.startLocation.y) <= 13
                }
            }
            if let selected, let hitCorner {
                displayDrag = DisplayDrag(display: selected, start: model.calibration(for: selected.id),
                                          corner: hitCorner, viewport: viewport,
                                          others: model.selectedDisplays.filter { $0.id != selected.id }.map(worldFrame))
            } else if let display = model.selectedDisplays.reversed().first(where: {
                viewport.rect(worldFrame($0)).contains(value.startLocation)
            }) {
                model.calibrationDisplayID = display.id
                displayDrag = DisplayDrag(display: display, start: model.calibration(for: display.id),
                                          corner: nil, viewport: viewport,
                                          others: model.selectedDisplays.filter { $0.id != display.id }.map(worldFrame))
            }
        }
        guard let drag = displayDrag else { return }
        // Keep this transform fixed until mouse-up: recomputing fit-to-window while dragging
        // would move the monitor away from the pointer as its bounding rectangle changes.
        let translation = CGSize(width: value.translation.width / drag.viewport.scale,
                                 height: value.translation.height / drag.viewport.scale)
        guard abs(translation.width) + abs(translation.height) > 0.01 else { return }
        let tolerance = model.snapEnabled ? 8 / drag.viewport.scale : 0
        let result: CalibrationEditResult
        if let corner = drag.corner {
            result = CalibrationInteraction.resize(display: drag.display, start: drag.start, corner: corner,
                                                   translation: translation, others: drag.others, snapDistance: tolerance)
        } else {
            result = CalibrationInteraction.move(display: drag.display, start: drag.start,
                                                 translation: translation, others: drag.others, snapDistance: tolerance)
        }
        snapGuides = result.guides
        if result.calibration != model.calibration(for: drag.display.id) {
            model.setCalibration(result.calibration, for: drag.display.id, persist: false)
        }
    }

    private func panImage(_ value: DragGesture.Value, geometry: WallpaperGeometry, viewport: CanvasViewport) {
        if imageDragStart == nil { imageDragStart = CGPoint(x: model.horizontalOffset, y: model.verticalOffset) }
        guard let start = imageDragStart, abs(value.translation.width) + abs(value.translation.height) > 0.01 else { return }
        let overflowX = (geometry.imageRect.width - geometry.canvasSize.width) * viewport.scale
        let overflowY = (geometry.imageRect.height - geometry.canvasSize.height) * viewport.scale
        if overflowX > 0.1 {
            model.horizontalOffset = min(1, max(-1, start.x - 2 * value.translation.width / overflowX))
        }
        if overflowY > 0.1 {
            model.verticalOffset = min(1, max(-1, start.y - 2 * value.translation.height / overflowY))
        }
    }

    private func finishInteraction() {
        if displayDrag != nil { model.commitCalibrationChanges() }
        displayDrag = nil
        imageDragStart = nil
        snapGuides = []
    }

    private func worldFrame(_ display: DisplayDescriptor) -> CGRect {
        model.calibration(for: display.id).canvasFrame(for: display)
    }

    private func bounds() -> CGRect {
        model.selectedDisplays.reduce(CGRect.null) { $0.union(worldFrame($1)) }
    }

    private func drawBackground(context: GraphicsContext, size: CGSize) {
        var grid = Path()
        for x in stride(from: CGFloat(0), through: size.width, by: 28) {
            grid.move(to: CGPoint(x: x, y: 0)); grid.addLine(to: CGPoint(x: x, y: size.height))
        }
        for y in stride(from: CGFloat(0), through: size.height, by: 28) {
            grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: size.width, y: y))
        }
        context.stroke(grid, with: .color(.white.opacity(0.035)), lineWidth: 0.5)
    }

    private func drawConnections(context: GraphicsContext, viewport: CanvasViewport) {
        let displays = model.selectedDisplays
        for first in displays.indices {
            for second in displays.indices where second > first {
                let a = worldFrame(displays[first]), b = worldFrame(displays[second])
                let p = CGPoint(x: min(a.maxX, max(a.minX, b.midX)), y: min(a.maxY, max(a.minY, b.midY)))
                let q = CGPoint(x: min(b.maxX, max(b.minX, a.midX)), y: min(b.maxY, max(b.minY, a.midY)))
                let viewP = viewport.point(p), viewQ = viewport.point(q)
                let distance = hypot(viewP.x - viewQ.x, viewP.y - viewQ.y)
                guard !a.intersects(b), distance > 4 else { continue }
                var path = Path()
                path.move(to: viewP); path.addLine(to: viewQ)
                context.stroke(path, with: .color(.cyan.opacity(0.65)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                if distance > 35 {
                    context.draw(Text(String(format: "%.0f pt", hypot(p.x - q.x, p.y - q.y)))
                        .font(.system(size: 9, design: .monospaced)).foregroundColor(.cyan),
                                 at: CGPoint(x: (viewP.x + viewQ.x) / 2, y: (viewP.y + viewQ.y) / 2 - 10))
                }
            }
        }
    }

    private func drawReferenceLines(context: GraphicsContext, viewport: CanvasViewport, worldBounds: CGRect) {
        // Keep the shared references legible even when a large desktop is fitted into a small preview.
        var clipping = Path()
        for display in model.selectedDisplays { clipping.addRect(viewport.rect(worldFrame(display))) }
        context.drawLayer { layer in
            layer.clip(to: clipping)
            let unit = pow(2, max(0, ceil(log2(max(worldBounds.width, worldBounds.height) / 12_000))))
            let spacing = 600 * unit
            var grid = Path()
            for x in stride(from: CGFloat(0), through: worldBounds.width, by: spacing) {
                grid.move(to: viewport.point(CGPoint(x: worldBounds.minX + x, y: worldBounds.minY)))
                grid.addLine(to: viewport.point(CGPoint(x: worldBounds.minX + x, y: worldBounds.maxY)))
            }
            for y in stride(from: CGFloat(0), through: worldBounds.height, by: spacing) {
                grid.move(to: viewport.point(CGPoint(x: worldBounds.minX, y: worldBounds.minY + y)))
                grid.addLine(to: viewport.point(CGPoint(x: worldBounds.maxX, y: worldBounds.minY + y)))
            }
            layer.stroke(grid, with: .color(.white.opacity(0.25)), lineWidth: 0.65)
            let lines: [(CGPoint, CGPoint, Color)] = [
                (CGPoint(x: worldBounds.minX, y: worldBounds.midY), CGPoint(x: worldBounds.maxX, y: worldBounds.midY), .cyan),
                (CGPoint(x: worldBounds.midX, y: worldBounds.minY), CGPoint(x: worldBounds.midX, y: worldBounds.maxY), .pink),
                (worldBounds.origin, CGPoint(x: worldBounds.maxX, y: worldBounds.maxY), .orange)
            ]
            for (start, end, color) in lines {
                var line = Path()
                line.move(to: viewport.point(start)); line.addLine(to: viewport.point(end))
                layer.stroke(line, with: .color(color), lineWidth: 1)
            }
        }
    }

    private func drawScreens(context: GraphicsContext, viewport: CanvasViewport) {
        for (index, display) in model.displays.enumerated() where !model.excludedIDs.contains(display.id) {
            let rect = viewport.rect(worldFrame(display))
            let isEditing = model.isCalibrating && model.calibrationDisplay?.id == display.id
            context.stroke(Path(rect.insetBy(dx: -1.5, dy: -1.5)), with: .color(.black.opacity(0.6)), lineWidth: 4)
            context.stroke(Path(rect), with: .color(isEditing ? Palette.accent : .white.opacity(0.65)),
                           lineWidth: isEditing ? 2 : 1)
            let badge = CGRect(x: rect.minX + 8, y: rect.minY + 8, width: 23, height: 21)
            context.fill(Path(roundedRect: badge, cornerRadius: 4), with: .color(.black.opacity(0.6)))
            context.draw(Text("\(index + 1)").font(.system(size: 11, weight: .semibold)).foregroundColor(.white),
                         at: CGPoint(x: badge.midX, y: badge.midY))
            if rect.width > 90 && rect.height > 55 {
                let caption = Text(display.name).font(.system(size: 10, weight: .medium)).foregroundColor(.white)
                let bottom = CGRect(x: rect.minX, y: rect.maxY - 24, width: rect.width, height: 24)
                context.fill(Path(bottom), with: .color(.black.opacity(0.5)))
                context.draw(caption, at: CGPoint(x: rect.midX, y: bottom.midY))
            }
        }
        // Draw the selected outline and handles last so neighboring screens cannot cover them.
        if model.isCalibrating, let display = model.calibrationDisplay {
            let rect = viewport.rect(worldFrame(display))
            context.stroke(Path(rect), with: .color(Palette.accent), lineWidth: 2)
            for corner in CalibrationCorner.allCases {
                let point = cornerPoint(corner, frame: rect)
                let handle = CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10)
                context.fill(Path(roundedRect: handle, cornerRadius: 2), with: .color(.white))
                context.stroke(Path(roundedRect: handle, cornerRadius: 2), with: .color(Palette.accent), lineWidth: 2)
            }
        }
    }

    private func cornerPoint(_ corner: CalibrationCorner, frame: CGRect) -> CGPoint {
        switch corner {
        case .topLeft: return CGPoint(x: frame.minX, y: frame.minY)
        case .topRight: return CGPoint(x: frame.maxX, y: frame.minY)
        case .bottomLeft: return CGPoint(x: frame.minX, y: frame.maxY)
        case .bottomRight: return CGPoint(x: frame.maxX, y: frame.maxY)
        }
    }
}

private struct DisplayDrag {
    let display: DisplayDescriptor
    let start: DisplayCalibration
    let corner: CalibrationCorner?
    let viewport: CanvasViewport
    let others: [CGRect]
}

private struct CanvasViewport {
    let scale: CGFloat
    let origin: CGPoint
    let bounds: CGRect

    init(available: CGSize, bounds: CGRect) {
        self.bounds = bounds
        scale = max(0.001, min(max(1, available.width - 48) / max(1, bounds.width),
                               max(1, available.height - 32) / max(1, bounds.height)))
        origin = CGPoint(x: (available.width - bounds.width * scale) / 2,
                         y: (available.height - bounds.height * scale) / 2)
    }

    func point(_ point: CGPoint) -> CGPoint {
        CGPoint(x: origin.x + (point.x - bounds.minX) * scale,
                y: origin.y + (point.y - bounds.minY) * scale)
    }

    func rect(_ rect: CGRect) -> CGRect {
        CGRect(origin: point(rect.origin), size: CGSize(width: rect.width * scale, height: rect.height * scale))
    }
}
