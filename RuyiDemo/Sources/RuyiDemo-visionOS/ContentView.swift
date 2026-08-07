import Ruyi
import SwiftUI
import UIKit

struct ContentView: View {
    @State private var color = Color.white
    @State private var hexText = "#FFFFFF"
    @State private var strokeWidth: Double = 2
    @State private var size: Double = 32
    @State private var absoluteStrokeWidth = true
    @State private var rendered: [String: UIImage] = [:]
    @State private var isRendering = false
    @State private var renderGeneration = 0
    @State private var renderBusy = false

    private let defaults = StyleDefaults()

    var body: some View {
        HStack(spacing: 0) {
            iconGrid
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(white: 0.16))

            controls
                .padding(24)
                .frame(width: 320)
                .background(Color(white: 0.11))
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

    private var controls: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Style as you please")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                Spacer()
                Button(action: reset) {
                    Image(systemName: "arrow.counterclockwise")
                        .foregroundStyle(.white.opacity(0.85))
                }
                .buttonStyle(.plain)
            }

            Text("Ruyi on visionOS — live size, color and stroke.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Text("Color")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 72, alignment: .leading)
                ColorPicker("", selection: $color, supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 36, height: 28)
                TextField("", text: $hexText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(size: 13, design: .monospaced))
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
                    .foregroundStyle(.white)
            }

            sliderRow(title: "Stroke width", valueText: "\(format(strokeWidth))px", value: $strokeWidth, range: 0.5...5)
            sliderRow(title: "Size", valueText: "\(Int(size.rounded()))px", value: $size, range: 16...64)

            Toggle(isOn: $absoluteStrokeWidth) {
                Text("Absolute Stroke width")
                    .foregroundStyle(.white.opacity(0.85))
            }
            .toggleStyle(.switch)

            HStack {
                Text("\(IconCatalog.icons.count) icons")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.45))
                Spacer()
                if isRendering {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func sliderRow(
        title: String,
        valueText: String,
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.caption.weight(.medium))
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

    private var iconGrid: some View {
        ScrollView {
            let columns = [GridItem(.adaptive(minimum: 88, maximum: 112), spacing: 12)]
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(IconCatalog.icons) { icon in
                    VStack(spacing: 8) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.white.opacity(0.04))
                                .frame(width: 88, height: 88)
                            if let image = rendered[icon.name] {
                                Image(uiImage: image)
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
    }

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
            color: UIColor(color),
            strokeWidth: strokeWidth,
            absoluteStrokeWidth: absoluteStrokeWidth,
            referenceSize: 24,
            scale: 2
        )
        let icons = IconCatalog.icons

        renderBusy = true
        DispatchQueue.global(qos: .userInteractive).async {
            var images = [UIImage?](repeating: nil, count: icons.count)
            DispatchQueue.concurrentPerform(iterations: icons.count) { index in
                images[index] = Ruyi.image(data: icons[index].data, options: options)
            }

            var next: [String: UIImage] = [:]
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

private struct StyleDefaults {
    let color = Color.white
    let hex = "#FFFFFF"
    let strokeWidth: Double = 2
    let size: Double = 32
    let absoluteStrokeWidth = true
}

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
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard ui.getRed(&r, green: &g, blue: &b, alpha: &a) else { return "#FFFFFF" }
        return String(
            format: "#%02X%02X%02X",
            Int((r * 255).rounded()),
            Int((g * 255).rounded()),
            Int((b * 255).rounded())
        )
    }
}
