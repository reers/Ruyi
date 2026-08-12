import Ruyi
import SwiftUI

enum DemoTintMode: String, CaseIterable, Identifiable {
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

enum DemoLinearDirectionPreset: String, CaseIterable, Identifiable {
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

/// Shared Apple demo entry: Original / Solid / Linear / Radial with isolated workspaces.
struct DemoContentView: View {
    @State private var tintMode: DemoTintMode = .original

    var body: some View {
        Group {
            switch tintMode {
            case .original:
                DemoOriginalWorkspace(tintMode: $tintMode)
            case .solid:
                DemoSolidWorkspace(tintMode: $tintMode)
            case .linear, .radial:
                DemoGradientWorkspace(tintMode: $tintMode)
            }
        }
        .id(tintMode)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .preferredColorScheme(.dark)
        .onChange(of: tintMode) { _ in
            DemoPlatform.dismissSystemColorPanel()
        }
    }
}

// MARK: - Mode picker (Equatable — keep out of stroke/size invalidation)

struct DemoModePickerView: View, Equatable {
    @Binding var tintMode: DemoTintMode

    static func == (lhs: DemoModePickerView, rhs: DemoModePickerView) -> Bool {
        lhs.tintMode == rhs.tintMode
    }

    var body: some View {
        Picker("", selection: $tintMode) {
            ForEach(DemoTintMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        #if os(watchOS)
        .pickerStyle(.navigationLink)
        #else
        .pickerStyle(.segmented)
        #endif
        .labelsHidden()
    }
}

// MARK: - Layout shell

private struct DemoWorkspaceShell<Sidebar: View, Canvas: View>: View {
    @ViewBuilder var sidebar: () -> Sidebar
    @ViewBuilder var canvas: () -> Canvas

    var body: some View {
        #if os(watchOS)
        TabView {
            canvas()
            ScrollView {
                sidebar()
                    .padding(.horizontal, 4)
            }
        }
        .tabViewStyle(.page)
        #elseif os(iOS)
        ViewThatFits {
            HStack(spacing: 0) {
                sidebarPane
                canvasPane
            }
            VStack(spacing: 0) {
                canvasPane
                ScrollView {
                    sidebar()
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                }
                .frame(maxHeight: 340)
                .background(DemoPlatform.panelBackground)
            }
        }
        #else
        HStack(spacing: 0) {
            sidebarPane
            canvasPane
        }
        #endif
    }

    private var sidebarPane: some View {
        sidebar()
            .frame(width: DemoPlatform.sidebarWidth)
            .padding(demoSidebarPadding)
            .background(DemoPlatform.panelBackground)
    }

    private var canvasPane: some View {
        canvas()
            .padding(demoCanvasPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DemoPlatform.canvasBackground)
    }

    private var demoSidebarPadding: CGFloat {
        #if os(tvOS)
        28
        #else
        24
        #endif
    }

    private var demoCanvasPadding: CGFloat {
        #if os(iOS)
        12
        #elseif os(tvOS)
        0
        #else
        20
        #endif
    }
}

// MARK: - Original

private struct DemoOriginalWorkspace: View {
    @Binding var tintMode: DemoTintMode

    @State private var size: Double = DemoDefaults.size
    @State private var rendered: [String: RuyiImage] = [:]
    @State private var isRendering = false
    @State private var renderGeneration = 0
    @State private var renderBusy = false
    @State private var rasterSize: Double = DemoDefaults.size

    var body: some View {
        DemoWorkspaceShell {
            VStack(alignment: .leading, spacing: 22) {
                DemoModePickerView(tintMode: $tintMode).equatable()
                DemoHeader(reset: reset)
                Text("Original SVG colors and strokes — only size is adjustable.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
                DemoNumericControl(
                    title: "Size",
                    valueText: "\(Int(size.rounded()))px",
                    value: $size,
                    range: DemoDefaults.sizeRange,
                    step: DemoDefaults.sizeStep
                )
                Spacer(minLength: 0)
                DemoFooter(isRendering: isRendering, iconCount: DemoPlatform.icons.count)
            }
        } canvas: {
            DemoIconGrid(icons: DemoPlatform.icons, rendered: rendered, displaySize: size)
        }
        .onAppear(perform: requestRender)
        .onChange(of: size) { newValue in
            let quantized = newValue.rounded()
            guard quantized != rasterSize else { return }
            rasterSize = quantized
            requestRender()
        }
    }

    private func reset() {
        size = DemoDefaults.size
        rasterSize = DemoDefaults.size
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
            scale: DemoPlatform.screenScale
        )
        let icons = DemoPlatform.icons

        renderBusy = true
        DispatchQueue.global(qos: .userInteractive).async {
            var images = [RuyiImage?](repeating: nil, count: icons.count)
            DispatchQueue.concurrentPerform(iterations: icons.count) { index in
                images[index] = Ruyi.image(data: icons[index].data, options: options)
            }

            var next: [String: RuyiImage] = [:]
            next.reserveCapacity(icons.count)
            for (icon, image) in zip(icons, images) {
                if let image { next[icon.name] = image }
            }

            DispatchQueue.main.async {
                if generation == renderGeneration { rendered = next }
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

// MARK: - Solid

private struct DemoSolidWorkspace: View {
    @Binding var tintMode: DemoTintMode

    @State private var color = Color.white
    @State private var hexText = "#FFFFFF"
    @State private var colorIndex = 0
    @State private var strokeWidth: Double = DemoDefaults.strokeWidth
    @State private var size: Double = DemoDefaults.size
    @State private var absoluteStrokeWidth = true
    @State private var rendered: [String: RuyiImage] = [:]
    @State private var isRendering = false
    @State private var renderGeneration = 0
    @State private var renderBusy = false
    @State private var rasterSize: Double = DemoDefaults.size
    @State private var suppressHexToColor = false

    var body: some View {
        DemoWorkspaceShell {
            VStack(alignment: .leading, spacing: 22) {
                DemoModePickerView(tintMode: $tintMode).equatable()
                DemoHeader(reset: reset)
                Text("Ruyi renders your SVGs with live size, color and stroke controls.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)

                DemoSolidColorControls(
                    color: $color,
                    hexText: $hexText,
                    colorIndex: $colorIndex
                )
                .equatable()

                DemoNumericControl(
                    title: "Stroke width",
                    valueText: "\(demoFormat(strokeWidth))px",
                    value: $strokeWidth,
                    range: DemoDefaults.strokeRange,
                    step: DemoDefaults.strokeStep
                )
                DemoNumericControl(
                    title: "Size",
                    valueText: "\(Int(size.rounded()))px",
                    value: $size,
                    range: DemoDefaults.sizeRange,
                    step: DemoDefaults.sizeStep
                )
                Toggle(isOn: $absoluteStrokeWidth) {
                    Text("Absolute Stroke width")
                        .foregroundStyle(.white.opacity(0.85))
                }
                #if !os(tvOS)
                .toggleStyle(.switch)
                #endif

                Spacer(minLength: 0)
                DemoFooter(isRendering: isRendering, iconCount: DemoPlatform.icons.count)
            }
        } canvas: {
            DemoIconGrid(icons: DemoPlatform.icons, rendered: rendered, displaySize: size)
        }
        .onAppear(perform: requestRender)
        .onChange(of: color) { _ in
            suppressHexToColor = true
            hexText = color.demoHex()
            suppressHexToColor = false
            requestRender()
        }
        .onChange(of: colorIndex) { _ in
            color = DemoPalette.solid[colorIndex].color
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
            guard !suppressHexToColor, let c = Color(demoHex: newValue) else { return }
            color = c
        }
    }

    private func reset() {
        color = .white
        suppressHexToColor = true
        hexText = "#FFFFFF"
        suppressHexToColor = false
        colorIndex = 0
        strokeWidth = DemoDefaults.strokeWidth
        size = DemoDefaults.size
        rasterSize = DemoDefaults.size
        absoluteStrokeWidth = true
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
            color: DemoPlatform.ruyiColor(from: color),
            strokeWidth: strokeWidth,
            absoluteStrokeWidth: absoluteStrokeWidth,
            referenceSize: 24,
            scale: DemoPlatform.screenScale
        )
        let icons = DemoPlatform.icons

        renderBusy = true
        DispatchQueue.global(qos: .userInteractive).async {
            var images = [RuyiImage?](repeating: nil, count: icons.count)
            DispatchQueue.concurrentPerform(iterations: icons.count) { index in
                images[index] = Ruyi.image(data: icons[index].data, options: options)
            }

            var next: [String: RuyiImage] = [:]
            next.reserveCapacity(icons.count)
            for (icon, image) in zip(icons, images) {
                if let image { next[icon.name] = image }
            }

            DispatchQueue.main.async {
                if generation == renderGeneration { rendered = next }
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

// MARK: - Gradient

private struct DemoGradientWorkspace: View {
    @Binding var tintMode: DemoTintMode

    @State private var stop0 = Color(red: 0.95, green: 0.35, blue: 0.45)
    @State private var stop1 = Color(red: 1.0, green: 0.75, blue: 0.2)
    @State private var stop2 = Color(red: 0.35, green: 0.55, blue: 1.0)
    @State private var useMidStop = true
    @State private var midOffset: Double = 0.5
    @State private var linearPreset: DemoLinearDirectionPreset = .topToBottom
    @State private var linearAngle: Double = 90
    @State private var radialCenterX: Double = 0.5
    @State private var radialCenterY: Double = 0.5
    @State private var radialRadius: Double = 0.71
    @State private var strokeWidth: Double = DemoDefaults.strokeWidth
    @State private var size: Double = DemoDefaults.size
    @State private var absoluteStrokeWidth = true
    @State private var rendered: [String: RuyiImage] = [:]
    @State private var isRendering = false
    @State private var renderGeneration = 0
    @State private var renderBusy = false
    @State private var rasterSize: Double = DemoDefaults.size
    @State private var showGradientEditor = false
    @State private var workspaceAlive = true

    var body: some View {
        DemoWorkspaceShell {
            VStack(alignment: .leading, spacing: 22) {
                DemoModePickerView(tintMode: $tintMode).equatable()
                DemoHeader(reset: reset)
                Text("Gradient tint. Edit stops in the sheet; stroke/size stay live.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)

                DemoGradientSummaryView(
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

                DemoNumericControl(
                    title: "Stroke width",
                    valueText: "\(demoFormat(strokeWidth))px",
                    value: $strokeWidth,
                    range: DemoDefaults.strokeRange,
                    step: DemoDefaults.strokeStep
                )
                DemoNumericControl(
                    title: "Size",
                    valueText: "\(Int(size.rounded()))px",
                    value: $size,
                    range: DemoDefaults.sizeRange,
                    step: DemoDefaults.sizeStep
                )
                Toggle(isOn: $absoluteStrokeWidth) {
                    Text("Absolute Stroke width")
                        .foregroundStyle(.white.opacity(0.85))
                }
                #if !os(tvOS)
                .toggleStyle(.switch)
                #endif

                Spacer(minLength: 0)
                DemoFooter(isRendering: isRendering, iconCount: DemoPlatform.icons.count)
            }
        } canvas: {
            DemoIconGrid(icons: DemoPlatform.icons, rendered: rendered, displaySize: size)
        }
        .onAppear {
            workspaceAlive = true
            requestRender()
        }
        .onDisappear {
            workspaceAlive = false
            renderGeneration &+= 1
            renderBusy = false
            isRendering = false
            DemoPlatform.dismissSystemColorPanel()
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
            DemoPlatform.dismissSystemColorPanel()
            requestRender()
        }) {
            DemoGradientEditorSheet(
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
        strokeWidth = DemoDefaults.strokeWidth
        size = DemoDefaults.size
        rasterSize = DemoDefaults.size
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
            .init(offset: 0, color: DemoPlatform.ruyiColor(from: stop0))
        ]
        if useMidStop {
            stops.append(.init(offset: midOffset, color: DemoPlatform.ruyiColor(from: stop1)))
        }
        stops.append(.init(offset: 1, color: DemoPlatform.ruyiColor(from: stop2)))

        switch tintMode {
        case .original, .solid:
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
            scale: DemoPlatform.screenScale
        )
        let icons = DemoPlatform.icons

        renderBusy = true
        DispatchQueue.global(qos: .userInteractive).async {
            var images = [RuyiImage?](repeating: nil, count: icons.count)
            DispatchQueue.concurrentPerform(iterations: icons.count) { index in
                images[index] = Ruyi.image(data: icons[index].data, options: options)
            }

            var next: [String: RuyiImage] = [:]
            next.reserveCapacity(icons.count)
            for (icon, image) in zip(icons, images) {
                if let image { next[icon.name] = image }
            }

            DispatchQueue.main.async {
                guard workspaceAlive else { return }
                if generation == renderGeneration { rendered = next }
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

// MARK: - Defaults / chrome

private enum DemoDefaults {
    static let strokeWidth: Double = 2
    #if os(tvOS)
    static let size: Double = 48
    static let sizeRange: ClosedRange<Double> = 24...96
    static let sizeStep: Double = 8
    #elseif os(watchOS)
    static let size: Double = 28
    static let sizeRange: ClosedRange<Double> = 16...40
    static let sizeStep: Double = 2
    #elseif os(visionOS)
    static let size: Double = 32
    static let sizeRange: ClosedRange<Double> = 16...64
    static let sizeStep: Double = 1
    #else
    static let size: Double = 24
    static let sizeRange: ClosedRange<Double> = 12...64
    static let sizeStep: Double = 1
    #endif

    #if os(watchOS)
    static let strokeRange: ClosedRange<Double> = 0.5...4
    static let strokeStep: Double = 0.5
    #else
    static let strokeRange: ClosedRange<Double> = 0.5...5
    static let strokeStep: Double = 0.5
    #endif
}

private struct DemoHeader: View {
    let reset: () -> Void

    var body: some View {
        HStack {
            Text("Style as you please")
                .font(.system(size: demoTitleSize, weight: .bold))
                .foregroundStyle(.white)
            Spacer()
            Button(action: reset) {
                Image(systemName: "arrow.counterclockwise")
                    .foregroundStyle(.white.opacity(0.85))
            }
            .buttonStyle(.plain)
            #if os(macOS)
            .help("Reset")
            #endif
        }
    }

    private var demoTitleSize: CGFloat {
        #if os(watchOS)
        16
        #elseif os(tvOS) || os(visionOS)
        22
        #else
        28
        #endif
    }
}

private struct DemoFooter: View {
    let isRendering: Bool
    let iconCount: Int

    var body: some View {
        HStack {
            Text("\(iconCount) icons")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.45))
            Spacer()
            if isRendering {
                ProgressView()
                    #if !os(tvOS)
                    .controlSize(.small)
                    #endif
            }
        }
    }
}

private struct DemoNumericControl: View {
    let title: String
    let valueText: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
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
            #if os(tvOS)
            HStack(spacing: 20) {
                Button("-") {
                    value = max(range.lowerBound, value - step)
                }
                .buttonStyle(.bordered)
                ProgressView(value: (value - range.lowerBound) / (range.upperBound - range.lowerBound))
                    .tint(Color(red: 0.95, green: 0.35, blue: 0.45))
                Button("+") {
                    value = min(range.upperBound, value + step)
                }
                .buttonStyle(.bordered)
            }
            #elseif os(watchOS)
            Stepper(value: $value, in: range, step: step) {
                EmptyView()
            }
            .labelsHidden()
            #else
            Slider(value: $value, in: range)
                .tint(Color(red: 0.95, green: 0.35, blue: 0.45))
            #endif
        }
    }
}

private struct DemoSolidColorControls: View, Equatable {
    @Binding var color: Color
    @Binding var hexText: String
    @Binding var colorIndex: Int

    static func == (lhs: DemoSolidColorControls, rhs: DemoSolidColorControls) -> Bool {
        lhs.color == rhs.color && lhs.hexText == rhs.hexText && lhs.colorIndex == rhs.colorIndex
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Color")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
            #if os(tvOS) || os(watchOS)
            HStack(spacing: 12) {
                ForEach(DemoPalette.solid.indices, id: \.self) { index in
                    Button {
                        colorIndex = index
                    } label: {
                        Circle()
                            .fill(DemoPalette.solid[index].color)
                            .frame(width: demoSwatchSize, height: demoSwatchSize)
                            .overlay(
                                Circle()
                                    .strokeBorder(.white, lineWidth: colorIndex == index ? 3 : 0)
                            )
                    }
                    #if os(tvOS)
                    .buttonStyle(.card)
                    #else
                    .buttonStyle(.plain)
                    #endif
                }
            }
            #else
            HStack(spacing: 10) {
                ColorPicker("", selection: $color, supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 36, height: 28)
                TextField("", text: $hexText)
                    #if os(iOS) || os(visionOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    #endif
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .monospaced))
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
                    .foregroundStyle(.white)
            }
            #endif
        }
    }

    private var demoSwatchSize: CGFloat {
        #if os(watchOS)
        22
        #else
        44
        #endif
    }
}

private struct DemoIconGrid: View {
    let icons: [IconCatalog.DemoIcon]
    let rendered: [String: RuyiImage]
    let displaySize: Double

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: gridSpacing) {
                ForEach(icons) { icon in
                    VStack(spacing: 8) {
                        ZStack {
                            RoundedRectangle(cornerRadius: cellCorner)
                                .fill(Color.white.opacity(0.04))
                                .frame(width: cellSize, height: cellSize)
                            if let image = rendered[icon.name] {
                                DemoPlatformImage(image: image, displaySize: displaySize)
                            } else {
                                ProgressView()
                                    #if !os(tvOS)
                                    .controlSize(.mini)
                                    #endif
                            }
                        }
                        .frame(width: cellSize, height: cellSize)
                        #if !os(watchOS)
                        Text(icon.name)
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.45))
                            .lineLimit(1)
                        #endif
                    }
                    #if os(tvOS)
                    .focusable()
                    #endif
                }
            }
            .padding(8)
        }
        #if !os(watchOS) && !os(tvOS)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(DemoPlatform.gridFill)
                )
        )
        #endif
        .transaction { $0.animation = nil }
    }

    private var columns: [GridItem] {
        #if os(watchOS)
        [GridItem(.adaptive(minimum: 44), spacing: 6)]
        #elseif os(tvOS)
        [GridItem(.adaptive(minimum: 120, maximum: 160), spacing: 20)]
        #elseif os(visionOS)
        [GridItem(.adaptive(minimum: 88, maximum: 112), spacing: 12)]
        #else
        [GridItem(.adaptive(minimum: 72, maximum: 96), spacing: 12)]
        #endif
    }

    private var cellSize: CGFloat {
        #if os(watchOS)
        44
        #elseif os(tvOS)
        120
        #elseif os(visionOS)
        88
        #else
        72
        #endif
    }

    private var cellCorner: CGFloat {
        #if os(watchOS)
        8
        #elseif os(tvOS)
        16
        #else
        12
        #endif
    }

    private var gridSpacing: CGFloat {
        #if os(watchOS)
        8
        #elseif os(tvOS)
        24
        #else
        16
        #endif
    }
}

// MARK: - Gradient summary / editor

private struct DemoGradientSummaryView: View, Equatable {
    let tintMode: DemoTintMode
    let stop0: Color
    let stop1: Color
    let stop2: Color
    let useMidStop: Bool
    let midOffset: Double
    let linearPreset: DemoLinearDirectionPreset
    let linearAngle: Double
    let radialCenterX: Double
    let radialCenterY: Double
    let radialRadius: Double
    let onEdit: () -> Void

    static func == (lhs: DemoGradientSummaryView, rhs: DemoGradientSummaryView) -> Bool {
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

private struct DemoGradientEditorSheet: View {
    let tintMode: DemoTintMode
    @Binding var stop0: Color
    @Binding var stop1: Color
    @Binding var stop2: Color
    @Binding var useMidStop: Bool
    @Binding var midOffset: Double
    @Binding var linearPreset: DemoLinearDirectionPreset
    @Binding var linearAngle: Double
    @Binding var radialCenterX: Double
    @Binding var radialCenterY: Double
    @Binding var radialRadius: Double
    @Environment(\.dismiss) private var dismiss

    private var titleText: String {
        tintMode == .linear ? "Linear gradient" : "Radial gradient"
    }

    var body: some View {
        #if os(watchOS)
        NavigationView {
            Form {
                editorFields
            }
            .navigationTitle(tintMode == .linear ? "Linear" : "Radial")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", action: close)
                }
            }
        }
        #elseif os(macOS)
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(titleText)
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
                Button("Done", action: close)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    editorFields
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 380, height: 520)
        .preferredColorScheme(.dark)
        #else
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    editorFields
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(titleText)
            #if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: close)
                        #if os(iOS) || os(visionOS)
                        .keyboardShortcut(.defaultAction)
                        #endif
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #endif
        .preferredColorScheme(.dark)
        #endif
    }

    private func close() {
        DemoPlatform.dismissSystemColorPanel()
        dismiss()
    }

    @ViewBuilder
    private var editorFields: some View {
        stopEditor(title: "Stop 0", color: $stop0)
        Toggle("Mid stop", isOn: $useMidStop)
        if useMidStop {
            stopEditor(title: "Stop mid", color: $stop1)
            DemoNumericControl(
                title: "Mid offset",
                valueText: String(format: "%.2f", midOffset),
                value: $midOffset,
                range: 0.05...0.95,
                step: 0.05
            )
        }
        stopEditor(title: "Stop 1", color: $stop2)

        if tintMode == .linear {
            Picker("Direction", selection: $linearPreset) {
                ForEach(DemoLinearDirectionPreset.allCases) { preset in
                    Text(preset.title).tag(preset)
                }
            }
            if linearPreset == .angle {
                DemoNumericControl(
                    title: "Angle",
                    valueText: "\(Int(linearAngle.rounded()))°",
                    value: $linearAngle,
                    range: 0...360,
                    step: 15
                )
            }
        } else {
            DemoNumericControl(
                title: "Center X",
                valueText: String(format: "%.2f", radialCenterX),
                value: $radialCenterX,
                range: 0...1,
                step: 0.05
            )
            DemoNumericControl(
                title: "Center Y",
                valueText: String(format: "%.2f", radialCenterY),
                value: $radialCenterY,
                range: 0...1,
                step: 0.05
            )
            DemoNumericControl(
                title: "Radius",
                valueText: String(format: "%.2f", radialRadius),
                value: $radialRadius,
                range: 0.1...1.2,
                step: 0.05
            )
        }
    }

    @ViewBuilder
    private func stopEditor(title: String, color: Binding<Color>) -> some View {
        #if os(tvOS) || os(watchOS)
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
            HStack(spacing: 8) {
                ForEach(DemoPalette.gradient.indices, id: \.self) { index in
                    Button {
                        color.wrappedValue = DemoPalette.gradient[index]
                    } label: {
                        Circle()
                            .fill(DemoPalette.gradient[index])
                            .frame(width: 28, height: 28)
                            .overlay(
                                Circle()
                                    .strokeBorder(
                                        .white,
                                        lineWidth: colorsApproximatelyEqual(color.wrappedValue, DemoPalette.gradient[index]) ? 2 : 0
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        #else
        HStack {
            Text(title)
            Spacer()
            ColorPicker("", selection: color, supportsOpacity: true)
                .labelsHidden()
                .frame(width: 36, height: 28)
        }
        #endif
    }

    private func colorsApproximatelyEqual(_ lhs: Color, _ rhs: Color) -> Bool {
        lhs.demoHex() == rhs.demoHex()
    }
}
