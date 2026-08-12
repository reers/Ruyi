import AppKit
import Ruyi
import SwiftUI

private enum TintMode: String, CaseIterable, Identifiable {
    case solid
    case linear
    case radial

    var id: String { rawValue }

    var title: String {
        switch self {
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
    @State private var tintMode: TintMode = .solid
    @State private var color = Color.white
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

    private let defaults = StyleDefaults()

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                sidebar
                    .padding(24)
            }
            .frame(width: 320)
            .background(Color(nsColor: .init(calibratedWhite: 0.11, alpha: 1)))

            iconGrid
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .init(calibratedWhite: 0.16, alpha: 1)))
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: requestRender)
        .onChange(of: tintMode) { _ in requestRender() }
        .onChange(of: color) { _ in
            suppressHexToColor = true
            syncHexFromColor()
            suppressHexToColor = false
            requestRender()
        }
        .onChange(of: stop0) { _ in requestRender() }
        .onChange(of: stop1) { _ in requestRender() }
        .onChange(of: stop2) { _ in requestRender() }
        .onChange(of: useMidStop) { _ in requestRender() }
        .onChange(of: midOffset) { _ in requestRender() }
        .onChange(of: linearPreset) { _ in requestRender() }
        .onChange(of: linearAngle) { _ in requestRender() }
        .onChange(of: radialCenterX) { _ in requestRender() }
        .onChange(of: radialCenterY) { _ in requestRender() }
        .onChange(of: radialRadius) { _ in requestRender() }
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

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 22) {
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

            Text("Ruyi renders your SVGs with live size, color and stroke controls.")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                Text("Tint")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                Picker("", selection: $tintMode) {
                    ForEach(TintMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            switch tintMode {
            case .solid:
                solidColorControls
            case .linear:
                gradientStopsControls
                linearGeometryControls
                gradientPreview
            case .radial:
                gradientStopsControls
                radialGeometryControls
                gradientPreview
            }

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
    }

    private var solidColorControls: some View {
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

    private var gradientStopsControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            stopRow(title: "Stop 0", color: $stop0)
            Toggle(isOn: $useMidStop) {
                Text("Mid stop")
                    .foregroundStyle(.white.opacity(0.85))
            }
            .toggleStyle(.switch)
            if useMidStop {
                stopRow(title: "Stop mid", color: $stop1)
                sliderRow(
                    title: "Mid offset",
                    valueText: String(format: "%.2f", midOffset),
                    value: $midOffset,
                    range: 0.05...0.95
                )
            }
            stopRow(title: "Stop 1", color: $stop2)
        }
    }

    private func stopRow(title: String, color: Binding<Color>) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
            Spacer()
            ColorPicker("", selection: color, supportsOpacity: true)
                .labelsHidden()
                .frame(width: 36, height: 28)
        }
    }

    private var linearGeometryControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Direction")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                Picker("", selection: $linearPreset) {
                    ForEach(LinearDirectionPreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            if linearPreset == .angle {
                sliderRow(
                    title: "Angle",
                    valueText: "\(Int(linearAngle.rounded()))°",
                    value: $linearAngle,
                    range: 0...360
                )
            }
        }
    }

    private var radialGeometryControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            sliderRow(
                title: "Center X",
                valueText: String(format: "%.2f", radialCenterX),
                value: $radialCenterX,
                range: 0...1
            )
            sliderRow(
                title: "Center Y",
                valueText: String(format: "%.2f", radialCenterY),
                value: $radialCenterY,
                range: 0...1
            )
            sliderRow(
                title: "Radius",
                valueText: String(format: "%.2f", radialRadius),
                value: $radialRadius,
                range: 0.1...1.2
            )
        }
    }

    private var gradientPreview: some View {
        Group {
            switch tintMode {
            case .solid:
                EmptyView()
            case .linear:
                let ends = currentLinearDirection.unitEndpoints
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(stops: previewGradientStops),
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
                            gradient: Gradient(stops: previewGradientStops),
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

    private var previewGradientStops: [Gradient.Stop] {
        var stops: [Gradient.Stop] = [.init(color: stop0, location: 0)]
        if useMidStop {
            stops.append(.init(color: stop1, location: midOffset))
        }
        stops.append(.init(color: stop2, location: 1))
        return stops
    }

    private var currentLinearDirection: Ruyi.GradientTint.LinearDirection {
        switch linearPreset {
        case .topToBottom: return .topToBottom
        case .leftToRight: return .leftToRight
        case .topLeftToBottomRight: return .topLeftToBottomRight
        case .angle: return .angle(linearAngle)
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

    // MARK: - Grid

    private var iconGrid: some View {
        ScrollView {
            let columns = [GridItem(.adaptive(minimum: 72, maximum: 96), spacing: 12)]
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(IconCatalog.icons) { icon in
                    IconCell(
                        name: icon.name,
                        image: rendered[icon.name],
                        displaySize: size
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

    // MARK: - Actions

    private func reset() {
        tintMode = defaults.tintMode
        color = defaults.color
        stop0 = defaults.stop0
        stop1 = defaults.stop1
        stop2 = defaults.stop2
        useMidStop = defaults.useMidStop
        midOffset = defaults.midOffset
        linearPreset = defaults.linearPreset
        linearAngle = defaults.linearAngle
        radialCenterX = defaults.radialCenterX
        radialCenterY = defaults.radialCenterY
        radialRadius = defaults.radialRadius
        suppressHexToColor = true
        hexText = defaults.hex
        suppressHexToColor = false
        strokeWidth = defaults.strokeWidth
        size = defaults.size
        rasterSize = defaults.size.rounded()
        absoluteStrokeWidth = defaults.absoluteStrokeWidth
        requestRender()
    }

    private func syncHexFromColor() {
        hexText = color.toHex()
    }

    private func requestRender() {
        renderGeneration += 1
        isRendering = true
        guard !renderBusy else { return }
        kickRender()
    }

    private func currentGradientTint() -> Ruyi.GradientTint? {
        var stops: [Ruyi.GradientStop] = [
            .init(offset: 0, color: NSColor(stop0))
        ]
        if useMidStop {
            stops.append(.init(offset: midOffset, color: NSColor(stop1)))
        }
        stops.append(.init(offset: 1, color: NSColor(stop2)))

        switch tintMode {
        case .solid:
            return nil
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
        let gradient = currentGradientTint()
        let solid: NSColor? = tintMode == .solid ? NSColor(color) : nil
        let options = Ruyi.Options(
            size: CGSize(width: targetSize, height: targetSize),
            color: solid,
            gradient: gradient,
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

    private func format(_ value: Double) -> String {
        String(format: abs(value - value.rounded()) < 0.05 ? "%.0f" : "%.1f", value)
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

private struct StyleDefaults {
    let tintMode: TintMode = .solid
    let color = Color.white
    let hex = "#FFFFFF"
    let stop0 = Color(red: 0.95, green: 0.35, blue: 0.45)
    let stop1 = Color(red: 1.0, green: 0.75, blue: 0.2)
    let stop2 = Color(red: 0.35, green: 0.55, blue: 1.0)
    let useMidStop = true
    let midOffset: Double = 0.5
    let linearPreset: LinearDirectionPreset = .topToBottom
    let linearAngle: Double = 90
    let radialCenterX: Double = 0.5
    let radialCenterY: Double = 0.5
    let radialRadius: Double = 0.71
    let strokeWidth: Double = 2
    let size: Double = 24
    let absoluteStrokeWidth = true
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
