import Ruyi
import SwiftUI
import UIKit

struct ContentView: View {
    @State private var colorIndex = 0
    @State private var strokeWidth: Double = 2
    @State private var size: Double = 48
    @State private var absoluteStrokeWidth = true
    @State private var rendered: [String: UIImage] = [:]
    @State private var isRendering = false
    @State private var renderGeneration = 0
    @State private var renderBusy = false

    private let palette: [(name: String, color: Color)] = [
        ("White", .white),
        ("Red", Color(red: 0.95, green: 0.35, blue: 0.45)),
        ("Blue", Color(red: 0.35, green: 0.55, blue: 0.95)),
        ("Green", Color(red: 0.35, green: 0.8, blue: 0.55)),
        ("Yellow", Color(red: 0.95, green: 0.8, blue: 0.3))
    ]

    var body: some View {
        HStack(spacing: 0) {
            iconGrid
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(white: 0.16))

            controls
                .frame(width: 420)
                .padding(28)
                .background(Color(white: 0.11))
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: requestRender)
        .onChange(of: colorIndex) { _ in requestRender() }
        .onChange(of: strokeWidth) { _ in requestRender() }
        .onChange(of: size) { _ in requestRender() }
        .onChange(of: absoluteStrokeWidth) { _ in requestRender() }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 28) {
            Text("Style as you please")
                .font(.title2.bold())
                .foregroundStyle(.white)

            Text("Focus the controls with the Siri Remote. Icons re-render live via Ruyi.")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 12) {
                Text("Color")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                HStack(spacing: 16) {
                    ForEach(palette.indices, id: \.self) { index in
                        Button {
                            colorIndex = index
                        } label: {
                            Circle()
                                .fill(palette[index].color)
                                .frame(width: 44, height: 44)
                                .overlay(
                                    Circle()
                                        .strokeBorder(.white, lineWidth: colorIndex == index ? 3 : 0)
                                )
                        }
                        .buttonStyle(.card)
                    }
                }
            }

            adjuster(title: "Stroke width", value: $strokeWidth, range: 0.5...5, step: 0.5) {
                "\(format(strokeWidth))px"
            }
            adjuster(title: "Size", value: $size, range: 24...96, step: 8) {
                "\(Int(size))px"
            }

            Toggle("Absolute Stroke width", isOn: $absoluteStrokeWidth)
                .foregroundStyle(.white.opacity(0.85))

            HStack {
                Text("\(IconCatalog.icons.count) icons")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.45))
                Spacer()
                if isRendering {
                    ProgressView()
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func adjuster(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        text: () -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Text(text())
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.55))
            }
            HStack(spacing: 20) {
                Button("-") {
                    value.wrappedValue = max(range.lowerBound, value.wrappedValue - step)
                }
                .buttonStyle(.bordered)
                ProgressView(value: (value.wrappedValue - range.lowerBound) / (range.upperBound - range.lowerBound))
                    .tint(Color(red: 0.95, green: 0.35, blue: 0.45))
                Button("+") {
                    value.wrappedValue = min(range.upperBound, value.wrappedValue + step)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var iconGrid: some View {
        ScrollView {
            let columns = [GridItem(.adaptive(minimum: 120, maximum: 160), spacing: 20)]
            LazyVGrid(columns: columns, spacing: 24) {
                ForEach(IconCatalog.icons) { icon in
                    VStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.white.opacity(0.04))
                                .frame(width: 120, height: 120)
                            if let image = rendered[icon.name] {
                                Image(uiImage: image)
                                    .resizable()
                                    .interpolation(.high)
                                    .frame(width: size, height: size)
                            } else {
                                ProgressView()
                            }
                        }
                        Text(icon.name)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.45))
                            .lineLimit(1)
                    }
                    .focusable()
                }
            }
            .padding(24)
        }
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
            color: UIColor(palette[colorIndex].color),
            strokeWidth: strokeWidth,
            absoluteStrokeWidth: absoluteStrokeWidth,
            referenceSize: 24,
            scale: UIScreen.main.scale
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
