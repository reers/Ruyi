import AppKit
import Ruyi
import SwiftUI

struct ContentView: View {
    @State private var color = Color.white
    @State private var hexText = "#FFFFFF"
    @State private var strokeWidth: Double = 2
    @State private var size: Double = 24
    @State private var absoluteStrokeWidth = true
    @State private var rendered: [String: NSImage] = [:]
    @State private var isRendering = false
    /// Bumps on every style change; stale async results are dropped.
    @State private var renderGeneration = 0
    @State private var renderBusy = false

    private let defaults = StyleDefaults()

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
        .preferredColorScheme(.dark)
        .onAppear(perform: requestRender)
        .onChange(of: color) { _ in
            syncHexFromColor()
            requestRender()
        }
        .onChange(of: strokeWidth) { _ in requestRender() }
        .onChange(of: size) { _ in requestRender() }
        .onChange(of: absoluteStrokeWidth) { _ in requestRender() }
        .onChange(of: hexText) { newValue in
            if let c = Color(hex: newValue) {
                color = c
            }
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
            // Continuous slider — no step notches.
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
                    VStack(spacing: 8) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.04))
                                .frame(width: 72, height: 72)
                            if let image = rendered[icon.name] {
                                // Follow the live slider size for Lucide-like immediacy;
                                // background re-rasterizes as fast as the CPU allows.
                                Image(nsImage: image)
                                    .resizable()
                                    .interpolation(.high)
                                    .frame(width: size, height: size)
                            } else {
                                ProgressView()
                                    .controlSize(.mini)
                            }
                        }
                        Text(icon.name)
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.45))
                            .lineLimit(1)
                    }
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
    }

    // MARK: - Actions

    private func reset() {
        color = defaults.color
        hexText = defaults.hex
        strokeWidth = defaults.strokeWidth
        size = defaults.size
        absoluteStrokeWidth = defaults.absoluteStrokeWidth
        requestRender()
    }

    private func syncHexFromColor() {
        hexText = color.toHex()
    }

    /// Request an immediate render with the latest style. Overlapping slider events
    /// coalesce to the newest params instead of queuing a backlog.
    private func requestRender() {
        renderGeneration += 1
        isRendering = true
        guard !renderBusy else { return }
        kickRender()
    }

    private func kickRender() {
        let generation = renderGeneration
        let targetSize = size
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
                images[index] = RuyiImage.ruyi(data: icons[index].data, options: options)
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
                    // Slider moved while we were busy — render the latest values now.
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

private struct StyleDefaults {
    let color = Color.white
    let hex = "#FFFFFF"
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
