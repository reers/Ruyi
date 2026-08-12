import AppKit
import Ruyi
import SwiftUI

private enum TintMode: String, CaseIterable, Identifiable {
    case original
    case solid
    case linear
    case radial

    var id: String { rawValue }

    var title: String {
        switch self {
        case .original: return "Original"
        case .solid: return "Solid"
        case .linear: return "Linear"
        case .radial: return "Radial"
        }
    }
}

private enum LinearDirectionPreset: String, CaseIterable, Identifiable {
    case topToBottom
    case leftToRight
    case topLeftToBottomRight
    case angle

    var id: String { rawValue }

    var title: String {
        switch self {
        case .topToBottom: return "Top → Bottom"
        case .leftToRight: return "Left → Right"
        case .topLeftToBottomRight: return "↖ → ↘"
        case .angle: return "Custom angle"
        }
    }
}

struct ContentView: View {
    @State private var tintMode: TintMode = .original

    var body: some View {
        // Hard split workspaces: switching modes remounts so gradient work cannot
        // pollute Original/Solid. Mode picker lives in each sidebar (no extra top bar).
        Group {
            switch tintMode {
            case .original:
                OriginalWorkspace(tintMode: $tintMode)
            case .solid:
                SolidWorkspace(tintMode: $tintMode)
            case .linear, .radial:
                GradientWorkspace(tintMode: $tintMode)
            }
        }
        .id(tintMode)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .preferredColorScheme(.dark)
        .onChange(of: tintMode) { _ in
            NSColorPanel.shared.orderOut(nil)
        }
    }
}

/// Segmented control is relatively heavy — keep it out of stroke/size invalidation.
private struct ModePickerView: View, Equatable {
    @Binding var tintMode: TintMode

    static func == (lhs: ModePickerView, rhs: ModePickerView) -> Bool {
        lhs.tintMode == rhs.tintMode
    }

    var body: some View {
        Picker("", selection: $tintMode) {
            ForEach(TintMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}

// MARK: - Original workspace (size only, keep SVG colors/strokes)

private struct OriginalWorkspace: View {
    @Binding var tintMode: TintMode

    @State private var size: Double = 24
    @State private var rendered: [String: NSImage] = [:]
    @State private var isRendering = false
    @State private var renderGeneration = 0
    @State private var renderBusy = false
    @State private var rasterSize: Double = 24

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 300)
                .padding(24)
                .background(Color(nsColor: .init(calibratedWhite: 0.11, alpha: 1)))

            IconGrid(
                icons: IconCatalog.icons,
                rendered: rendered,
                displaySize: size
            )
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .init(calibratedWhite: 0.16, alpha: 1)))
        }
        .onAppear(perform: requestRender)
        .onChange(of: size) { newValue in
            let quantized = newValue.rounded()
            guard quantized != rasterSize else { return }
            rasterSize = quantized
            requestRender()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 22) {
            ModePickerView(tintMode: $tintMode)
                .equatable()

            header(reset: reset)

            Text("Original SVG colors and strokes — only size is adjustable.")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)

            sliderRow(
                title: "Size",
                valueText: "\(Int(size.rounded()))px",
                value: $size,
                range: 12...64
            )

            Spacer()
            footer(isRendering: isRendering)
        }
    }

    private func reset() {
        size = 24
        rasterSize = 24
        requestRender()
    }

    private func requestRender() {
        renderGeneration += 1
        isRendering = true
        guard !renderBusy else { return }
        kickRender()
    }

    private func kickRender() {
        let generation = renderGeneration
        let targetSize = rasterSize
        // Omit color / gradient / strokeWidth → keep the SVG’s original style.
        let options = Ruyi.Options(
            size: CGSize(width: targetSize, height: targetSize),
            scale: NSScreen.main?.backingScaleFactor ?? 2
        )
        let icons = IconCatalog.icons

        renderBusy = true
        DispatchQueue.global(qos: .userInteractive).async {
            var images = [NSImage?](repeating: nil, count: icons.count)
            DispatchQueue.concurrentPerform(iterations: icons.count) { index in
                images[index] = Ruyi.image(data: icons[index].data, options: options)
            }

            var next: [String: NSImage] = [:]
            next.reserveCapacity(icons.count)
            for (icon, image) in zip(icons, images) {
                if let image {
                    next[icon.name] = image
                }
            }

            DispatchQueue.main.async {
                if generation == renderGeneration {
                    rendered = next
                }
                renderBusy = false
                if generation != renderGeneration {
                    kickRender()
                } else {
                    isRendering = false
                }
            }
        }
    }
}

// MARK: - Solid workspace (same hot path as `main`, isolated state)

private struct SolidWorkspace: View {
    @Binding var tintMode: TintMode

    @State private var color = Color.white
    @State private var hexText = "#FFFFFF"
    @State private var strokeWidth: Double = 2
    @State private var size: Double = 24
    @State private var absoluteStrokeWidth = true
    @State private var rendered: [String: NSImage] = [:]
    @State private var isRendering = false
    @State private var renderGeneration = 0
    @State private var renderBusy = false
    @State private var rasterSize: Double = 24
    @State private var suppressHexToColor = false

    private let defaults = SolidDefaults()

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 300)
                .padding(24)
                .background(Color(nsColor: .init(calibratedWhite: 0.11, alpha: 1)))

            iconGrid
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .init(calibratedWhite: 0.16, alpha: 1)))
        }
        .onAppear(perform: requestRender)
        .onChange(of: color) { _ in
            suppressHexToColor = true
            hexText = color.toHex()
            suppressHexToColor = false
            requestRender()
        }
        .onChange(of: strokeWidth) { _ in requestRender() }
        .onChange(of: size) { newValue in
            let quantized = newValue.rounded()
            guard quantized != rasterSize else { return }
            rasterSize = quantized
            requestRender()
        }
        .onChange(of: absoluteStrokeWidth) { _ in requestRender() }
        .onChange(of: hexText) { newValue in
            guard !suppressHexToColor, let c = Color(hex: newValue) else { return }
            color = c
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 22) {
            ModePickerView(tintMode: $tintMode)
                .equatable()

            header(reset: reset)

            Text("Ruyi renders your SVGs with live size, color and stroke controls.")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)

            SolidColorControls(color: $color, hexText: $hexText)
                .equatable()

            sliderRow(
                title: "Stroke width",
                valueText: "\(format(strokeWidth))px",
                value: $strokeWidth,
                range: 0.5...5
            )

            sliderRow(
                title: "Size",
                valueText: "\(Int(size.rounded()))px",
                value: $size,
                range: 12...64
            )

            Toggle(isOn: $absoluteStrokeWidth) {
                Text("Absolute Stroke width")
                    .foregroundStyle(.white.opacity(0.85))
            }
            .toggleStyle(.switch)

            Spacer()
            footer(isRendering: isRendering)
        }
    }

    private var iconGrid: some View {
        IconGrid(
            icons: IconCatalog.icons,
            rendered: rendered,
            displaySize: size
        )
    }

    private func reset() {
        color = defaults.color
        suppressHexToColor = true
        hexText = defaults.hex
        suppressHexToColor = false
        strokeWidth = defaults.strokeWidth
        size = defaults.size
        rasterSize = defaults.size.rounded()
        absoluteStrokeWidth = defaults.absoluteStrokeWidth
        requestRender()
    }

    private func requestRender() {
        renderGeneration += 1
        isRendering = true
        guard !renderBusy else { return }
        kickRender()
    }

    private func kickRender() {
        let generation = renderGeneration
        let targetSize = rasterSize
        let options = Ruyi.Options(
            size: CGSize(width: targetSize, height: targetSize),
            color: NSColor(color),
            strokeWidth: strokeWidth,
            absoluteStrokeWidth: absoluteStrokeWidth,
            referenceSize: 24,
            scale: NSScreen.main?.backingScaleFactor ?? 2
        )
        let icons = IconCatalog.icons

        renderBusy = true
        DispatchQueue.global(qos: .userInteractive).async {
            var images = [NSImage?](repeating: nil, count: icons.count)
            DispatchQueue.concurrentPerform(iterations: icons.count) { index in
                images[index] = Ruyi.image(data: icons[index].data, options: options)
            }

            var next: [String: NSImage] = [:]
            next.reserveCapacity(icons.count)
            for (icon, image) in zip(icons, images) {
                if let image {
                    next[icon.name] = image
                }
            }

            DispatchQueue.main.async {
                if generation == renderGeneration {
                    rendered = next
                }
                renderBusy = false
                if generation != renderGeneration {
                    kickRender()
                } else {
                    isRendering = false
                }
            }
        }
    }
}

// MARK: - Gradient workspace (own state + render loop)

private struct GradientWorkspace: View {
    @Binding var tintMode: TintMode

    @State private var stop0 = Color(red: 0.95, green: 0.35, blue: 0.45)
    @State private var stop1 = Color(red: 1.0, green: 0.75, blue: 0.2)
    @State private var stop2 = Color(red: 0.35, green: 0.55, blue: 1.0)
    @State private var useMidStop = true
    @State private var midOffset: Double = 0.5
    @State private var linearPreset: LinearDirectionPreset = .topToBottom
    @State private var linearAngle: Double = 90
    @State private var radialCenterX: Double = 0.5
    @State private var radialCenterY: Double = 0.5
    @State private var radialRadius: Double = 0.71
    @State private var strokeWidth: Double = 2
    @State private var size: Double = 24
    @State private var absoluteStrokeWidth = true
    @State private var rendered: [String: NSImage] = [:]
    @State private var isRendering = false
    @State private var renderGeneration = 0
    @State private var renderBusy = false
    @State private var rasterSize: Double = 24
    @State private var showGradientEditor = false
    @State private var workspaceAlive = true

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 300)
                .padding(24)
                .background(Color(nsColor: .init(calibratedWhite: 0.11, alpha: 1)))

            IconGrid(
                icons: IconCatalog.icons,
                rendered: rendered,
                displaySize: size
            )
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .init(calibratedWhite: 0.16, alpha: 1)))
        }
        .onAppear {
            workspaceAlive = true
            requestRender()
        }
        .onDisappear {
            // Invalidate every in-flight callback when leaving gradient mode.
            workspaceAlive = false
            renderGeneration &+= 1
            renderBusy = false
            isRendering = false
            NSColorPanel.shared.orderOut(nil)
        }
        .onChange(of: tintMode) { _ in requestRender() }
        .onChange(of: strokeWidth) { _ in requestRender() }
        .onChange(of: size) { newValue in
            let quantized = newValue.rounded()
            guard quantized != rasterSize else { return }
            rasterSize = quantized
            requestRender()
        }
        .onChange(of: absoluteStrokeWidth) { _ in requestRender() }
        .sheet(isPresented: $showGradientEditor, onDismiss: {
            NSColorPanel.shared.orderOut(nil)
            requestRender()
        }) {
            GradientEditorSheet(
                tintMode: tintMode,
                stop0: $stop0,
                stop1: $stop1,
                stop2: $stop2,
                useMidStop: $useMidStop,
                midOffset: $midOffset,
                linearPreset: $linearPreset,
                linearAngle: $linearAngle,
                radialCenterX: $radialCenterX,
                radialCenterY: $radialCenterY,
                radialRadius: $radialRadius
            )
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 22) {
            ModePickerView(tintMode: $tintMode)
                .equatable()

            header(reset: reset)

            Text("Gradient tint. Edit stops in the sheet; stroke/size stay live.")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)

            GradientSummaryView(
                tintMode: tintMode,
                stop0: stop0,
                stop1: stop1,
                stop2: stop2,
                useMidStop: useMidStop,
                midOffset: midOffset,
                linearPreset: linearPreset,
                linearAngle: linearAngle,
                radialCenterX: radialCenterX,
                radialCenterY: radialCenterY,
                radialRadius: radialRadius,
                onEdit: { showGradientEditor = true }
            )
            .equatable()

            sliderRow(
                title: "Stroke width",
                valueText: "\(format(strokeWidth))px",
                value: $strokeWidth,
                range: 0.5...5
            )

            sliderRow(
                title: "Size",
                valueText: "\(Int(size.rounded()))px",
                value: $size,
                range: 12...64
            )

            Toggle(isOn: $absoluteStrokeWidth) {
                Text("Absolute Stroke width")
                    .foregroundStyle(.white.opacity(0.85))
            }
            .toggleStyle(.switch)

            Spacer()
            footer(isRendering: isRendering)
        }
    }

    private func reset() {
        stop0 = Color(red: 0.95, green: 0.35, blue: 0.45)
        stop1 = Color(red: 1.0, green: 0.75, blue: 0.2)
        stop2 = Color(red: 0.35, green: 0.55, blue: 1.0)
        useMidStop = true
        midOffset = 0.5
        linearPreset = .topToBottom
        linearAngle = 90
        radialCenterX = 0.5
        radialCenterY = 0.5
        radialRadius = 0.71
        strokeWidth = 2
        size = 24
        rasterSize = 24
        absoluteStrokeWidth = true
        requestRender()
    }

    private func requestRender() {
        renderGeneration += 1
        isRendering = true
        guard !renderBusy else { return }
        kickRender()
    }

    private var currentLinearDirection: Ruyi.GradientTint.LinearDirection {
        switch linearPreset {
        case .topToBottom: return .topToBottom
        case .leftToRight: return .leftToRight
        case .topLeftToBottomRight: return .topLeftToBottomRight
        case .angle: return .angle(linearAngle)
        }
    }

    private func currentGradientTint() -> Ruyi.GradientTint {
        var stops: [Ruyi.GradientStop] = [
            .init(offset: 0, color: NSColor(stop0))
        ]
        if useMidStop {
            stops.append(.init(offset: midOffset, color: NSColor(stop1)))
        }
        stops.append(.init(offset: 1, color: NSColor(stop2)))

        switch tintMode {
        case .original, .solid:
            // Unreachable in GradientWorkspace; keep a safe fallback.
            return .linear(stops: stops, direction: .topToBottom)
        case .linear:
            return .linear(stops: stops, direction: currentLinearDirection)
        case .radial:
            return .radial(
                stops: stops,
                center: CGPoint(x: radialCenterX, y: radialCenterY),
                radius: radialRadius,
                focal: nil,
                focalRadius: 0
            )
        }
    }

    private func kickRender() {
        let generation = renderGeneration
        let targetSize = rasterSize
        let options = Ruyi.Options(
            size: CGSize(width: targetSize, height: targetSize),
            color: nil,
            gradient: currentGradientTint(),
            strokeWidth: strokeWidth,
            absoluteStrokeWidth: absoluteStrokeWidth,
            referenceSize: 24,
            scale: NSScreen.main?.backingScaleFactor ?? 2
        )
        let icons = IconCatalog.icons

        renderBusy = true
        DispatchQueue.global(qos: .userInteractive).async {
            var images = [NSImage?](repeating: nil, count: icons.count)
            DispatchQueue.concurrentPerform(iterations: icons.count) { index in
                images[index] = Ruyi.image(data: icons[index].data, options: options)
            }

            var next: [String: NSImage] = [:]
            next.reserveCapacity(icons.count)
            for (icon, image) in zip(icons, images) {
                if let image {
                    next[icon.name] = image
                }
            }

            DispatchQueue.main.async {
                // Workspace was destroyed (user switched back to Solid) — drop everything.
                guard workspaceAlive else { return }
                if generation == renderGeneration {
                    rendered = next
                }
                renderBusy = false
                if generation != renderGeneration {
                    kickRender()
                } else {
                    isRendering = false
                }
            }
        }
    }
}

// MARK: - Shared chrome

private func header(reset: @escaping () -> Void) -> some View {
    HStack {
        Text("Style as you please")
            .font(.system(size: 28, weight: .bold))
            .foregroundStyle(.white)
        Spacer()
        Button(action: reset) {
            Image(systemName: "arrow.counterclockwise")
                .foregroundStyle(.white.opacity(0.85))
        }
        .buttonStyle(.plain)
        .help("Reset")
    }
}

private func footer(isRendering: Bool) -> some View {
    HStack {
        Text("\(IconCatalog.icons.count) icons")
            .font(.system(size: 12))
            .foregroundStyle(.white.opacity(0.45))
        Spacer()
        if isRendering {
            ProgressView()
                .controlSize(.small)
        }
    }
}

private func sliderRow(
    title: String,
    valueText: String,
    value: Binding<Double>,
    range: ClosedRange<Double>
) -> some View {
    VStack(alignment: .leading, spacing: 8) {
        HStack {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
            Spacer()
            Text(valueText)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.white.opacity(0.55))
        }
        Slider(value: value, in: range)
            .tint(Color(red: 0.95, green: 0.35, blue: 0.45))
    }
}

private func format(_ value: Double) -> String {
    String(format: abs(value - value.rounded()) < 0.05 ? "%.0f" : "%.1f", value)
}

private struct SolidDefaults {
    let color = Color.white
    let hex = "#FFFFFF"
    let strokeWidth: Double = 2
    let size: Double = 24
    let absoluteStrokeWidth = true
}

/// Keep ColorPicker out of stroke/size rebuilds (same issue as ModePickerView).
private struct SolidColorControls: View, Equatable {
    @Binding var color: Color
    @Binding var hexText: String

    static func == (lhs: SolidColorControls, rhs: SolidColorControls) -> Bool {
        lhs.color == rhs.color && lhs.hexText == rhs.hexText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Color")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
            HStack(spacing: 10) {
                ColorPicker("", selection: $color, supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 36, height: 28)
                TextField("", text: $hexText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .monospaced))
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
                    .foregroundStyle(.white)
            }
        }
    }
}

private struct IconGrid: View {
    let icons: [IconCatalog.DemoIcon]
    let rendered: [String: NSImage]
    let displaySize: Double

    var body: some View {
        ScrollView {
            let columns = [GridItem(.adaptive(minimum: 72, maximum: 96), spacing: 12)]
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(icons) { icon in
                    IconCell(
                        name: icon.name,
                        image: rendered[icon.name],
                        displaySize: displaySize
                    )
                }
            }
            .padding(8)
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(nsColor: .init(calibratedWhite: 0.13, alpha: 1)))
                )
        )
        .transaction { $0.animation = nil }
    }
}

private struct IconCell: View {
    let name: String
    let image: NSImage?
    let displaySize: Double

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.04))
                    .frame(width: 72, height: 72)
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: displaySize, height: displaySize)
                } else {
                    ProgressView()
                        .controlSize(.mini)
                }
            }
            .frame(width: 72, height: 72)
            Text(name)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.45))
                .lineLimit(1)
        }
    }
}

// MARK: - Gradient summary / editor

private struct GradientSummaryView: View, Equatable {
    let tintMode: TintMode
    let stop0: Color
    let stop1: Color
    let stop2: Color
    let useMidStop: Bool
    let midOffset: Double
    let linearPreset: LinearDirectionPreset
    let linearAngle: Double
    let radialCenterX: Double
    let radialCenterY: Double
    let radialRadius: Double
    let onEdit: () -> Void

    static func == (lhs: GradientSummaryView, rhs: GradientSummaryView) -> Bool {
        lhs.tintMode == rhs.tintMode
            && lhs.stop0 == rhs.stop0
            && lhs.stop1 == rhs.stop1
            && lhs.stop2 == rhs.stop2
            && lhs.useMidStop == rhs.useMidStop
            && lhs.midOffset == rhs.midOffset
            && lhs.linearPreset == rhs.linearPreset
            && lhs.linearAngle == rhs.linearAngle
            && lhs.radialCenterX == rhs.radialCenterX
            && lhs.radialCenterY == rhs.radialCenterY
            && lhs.radialRadius == rhs.radialRadius
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            preview
            Button("Edit gradient…", action: onEdit)
                .buttonStyle(.plain)
                .foregroundStyle(Color(red: 0.95, green: 0.55, blue: 0.6))
                .font(.system(size: 13, weight: .medium))
        }
    }

    private var previewStops: [Gradient.Stop] {
        var stops: [Gradient.Stop] = [.init(color: stop0, location: 0)]
        if useMidStop {
            stops.append(.init(color: stop1, location: midOffset))
        }
        stops.append(.init(color: stop2, location: 1))
        return stops
    }

    private var linearDirection: Ruyi.GradientTint.LinearDirection {
        switch linearPreset {
        case .topToBottom: return .topToBottom
        case .leftToRight: return .leftToRight
        case .topLeftToBottomRight: return .topLeftToBottomRight
        case .angle: return .angle(linearAngle)
        }
    }

    @ViewBuilder
    private var preview: some View {
        switch tintMode {
        case .original, .solid:
            EmptyView()
        case .linear:
            let ends = linearDirection.unitEndpoints
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    LinearGradient(
                        gradient: Gradient(stops: previewStops),
                        startPoint: UnitPoint(x: ends.start.x, y: ends.start.y),
                        endPoint: UnitPoint(x: ends.end.x, y: ends.end.y)
                    )
                )
                .frame(height: 28)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        case .radial:
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    RadialGradient(
                        gradient: Gradient(stops: previewStops),
                        center: UnitPoint(x: radialCenterX, y: radialCenterY),
                        startRadius: 0,
                        endRadius: 40 * radialRadius
                    )
                )
                .frame(height: 56)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        }
    }
}

private struct GradientEditorSheet: View {
    let tintMode: TintMode
    @Binding var stop0: Color
    @Binding var stop1: Color
    @Binding var stop2: Color
    @Binding var useMidStop: Bool
    @Binding var midOffset: Double
    @Binding var linearPreset: LinearDirectionPreset
    @Binding var linearAngle: Double
    @Binding var radialCenterX: Double
    @Binding var radialCenterY: Double
    @Binding var radialRadius: Double
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(tintMode == .linear ? "Linear gradient" : "Radial gradient")
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
                Button("Done") {
                    NSColorPanel.shared.orderOut(nil)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }

            stopRow(title: "Stop 0", color: $stop0)
            Toggle("Mid stop", isOn: $useMidStop)
            if useMidStop {
                stopRow(title: "Stop mid", color: $stop1)
                labeledSlider(
                    "Mid offset",
                    value: $midOffset,
                    text: String(format: "%.2f", midOffset),
                    range: 0.05...0.95
                )
            }
            stopRow(title: "Stop 1", color: $stop2)

            if tintMode == .linear {
                Picker("Direction", selection: $linearPreset) {
                    ForEach(LinearDirectionPreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                if linearPreset == .angle {
                    labeledSlider(
                        "Angle",
                        value: $linearAngle,
                        text: "\(Int(linearAngle.rounded()))°",
                        range: 0...360
                    )
                }
            } else {
                labeledSlider(
                    "Center X",
                    value: $radialCenterX,
                    text: String(format: "%.2f", radialCenterX),
                    range: 0...1
                )
                labeledSlider(
                    "Center Y",
                    value: $radialCenterY,
                    text: String(format: "%.2f", radialCenterY),
                    range: 0...1
                )
                labeledSlider(
                    "Radius",
                    value: $radialRadius,
                    text: String(format: "%.2f", radialRadius),
                    range: 0.1...1.2
                )
            }

            Spacer()
        }
        .padding(24)
        .frame(width: 360, height: 420)
        .preferredColorScheme(.dark)
    }

    private func stopRow(title: String, color: Binding<Color>) -> some View {
        HStack {
            Text(title)
            Spacer()
            ColorPicker("", selection: color, supportsOpacity: true)
                .labelsHidden()
                .frame(width: 36, height: 28)
        }
    }

    private func labeledSlider(
        _ title: String,
        value: Binding<Double>,
        text: String,
        range: ClosedRange<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(text)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: value, in: range)
        }
    }
}

// MARK: - Color helpers

private extension Color {
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt32(s, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self = Color(red: r, green: g, blue: b)
    }

    func toHex() -> String {
        let ns = NSColor(self)
        guard let rgb = ns.usingColorSpace(.sRGB) else { return "#FFFFFF" }
        let r = Int((rgb.redComponent * 255).rounded())
        let g = Int((rgb.greenComponent * 255).rounded())
        let b = Int((rgb.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
