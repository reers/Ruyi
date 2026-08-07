import Ruyi
import SwiftUI
import WatchKit

struct ContentView: View {
    @State private var colorIndex = 0
    @State private var strokeWidth: Double = 2
    @State private var size: Double = 28
    @State private var absoluteStrokeWidth = true
    @State private var rendered: [String: UIImage] = [:]
    @State private var isRendering = false
    @State private var renderGeneration = 0
    @State private var renderBusy = false

    private let palette: [Color] = [
        .white,
        Color(red: 0.95, green: 0.35, blue: 0.45),
        Color(red: 0.35, green: 0.55, blue: 0.95),
        Color(red: 0.35, green: 0.8, blue: 0.55)
    ]

    var body: some View {
        TabView {
            iconPage
            controlsPage
        }
        .tabViewStyle(.page)
        .onAppear(perform: requestRender)
        .onChange(of: colorIndex) { _ in requestRender() }
        .onChange(of: strokeWidth) { _ in requestRender() }
        .onChange(of: size) { _ in requestRender() }
        .onChange(of: absoluteStrokeWidth) { _ in requestRender() }
    }

    private var iconPage: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 6)], spacing: 8) {
                ForEach(IconCatalog.icons.prefix(24)) { icon in
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.08))
                            .frame(width: 44, height: 44)
                        if let image = rendered[icon.name] {
                            Image(uiImage: image)
                                .resizable()
                                .interpolation(.high)
                                .frame(width: size, height: size)
                        } else if isRendering {
                            ProgressView()
                                .controlSize(.mini)
                        }
                    }
                }
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Icons")
    }

    private var controlsPage: some View {
        Form {
            Section("Color") {
                HStack {
                    ForEach(palette.indices, id: \.self) { index in
                        Button {
                            colorIndex = index
                        } label: {
                            Circle()
                                .fill(palette[index])
                                .frame(width: 22, height: 22)
                                .overlay(
                                    Circle()
                                        .strokeBorder(.primary, lineWidth: colorIndex == index ? 2 : 0)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Section("Style") {
                Stepper(value: $size, in: 16...40, step: 2) {
                    Text("Size \(Int(size))")
                }
                Stepper(value: $strokeWidth, in: 0.5...4, step: 0.5) {
                    Text("Stroke \(format(strokeWidth))")
                }
                Toggle("Absolute stroke", isOn: $absoluteStrokeWidth)
            }

            Section {
                Text("\(min(24, IconCatalog.icons.count)) / \(IconCatalog.icons.count) icons")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Style")
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
            color: UIColor(palette[colorIndex]),
            strokeWidth: strokeWidth,
            absoluteStrokeWidth: absoluteStrokeWidth,
            referenceSize: 24,
            scale: WKInterfaceDevice.current().screenScale
        )
        let icons = Array(IconCatalog.icons.prefix(24))

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
