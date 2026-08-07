# Ruyi

Cross-platform SVG **load & render** runtime for Apple platforms.  
Scale and tint your own SVGs — **no built-in icon set**.

> 如意金箍棒：能大能小 — vector graphics that scale freely.

## Platforms

- iOS 13+ (arm64 / Simulator arm64)
- macOS 10.15+ (Apple Silicon)

> ThorVG binary currently ships Apple Silicon slices only (via [`vnixx/thorvg.swift`](https://github.com/vnixx/thorvg.swift)).

## Install (SPM)

```swift
dependencies: [
    .package(url: "https://github.com/reers/Ruyi.git", from: "0.1.0")
]
```

## Usage

```swift
import Ruyi

let options = Ruyi.Options(
    size: CGSize(width: 24, height: 24),
    color: .systemRed,
    strokeWidth: 2
)

// Namespace API
let image = Ruyi.image(data: svgData, options: options)

// Or RuyiImage extension (UIImage / NSImage typealias)
let icon = RuyiImage.ruyi(data: svgData, options: options)
```

Also:

```swift
Ruyi.image(contentsOf: fileURL, options: ...)
Ruyi.image(named: "icon", in: .module, options: ...)
RuyiImage.ruyi(named: "icon", options: ...)
```

### Do not use Asset Catalog

Ruyi needs the **original SVG source** (file path, bundle resource, or in-memory XML/`Data`).

**Do not put SVGs in an Xcode Asset Catalog.** Assets compile SVG into bitmaps (or Apple’s internal vector form for `UIImage`). Neither exposes the SVG XML, so Ruyi / ThorVG cannot parse them — with or without “Preserve Vector Data”.

Put `.svg` files in the app / package **bundle** (Copy Bundle Resources / SPM `resources`) and load via `Ruyi.image(named:in:)` / `contentsOf:` / `data:`.

Asset Catalog is fine for system `UIImage` / SwiftUI `Image`; use a separate bundle resource for Ruyi.

## Demo

Lucide-style live customizer: color / stroke width / size / absolute stroke width.

Open `RuyiDemo/RuyiDemo.xcodeproj` in Xcode:

| Scheme | Platform |
|--------|----------|
| **RuyiDemo-macOS** | macOS |
| **RuyiDemo-iOS** | iOS Simulator / device |

Sample icons live in `RuyiDemo/Sources/RuyiDemo-macOS/Resources/Icons` (demo only — not part of the Ruyi library).

macOS CLI fallback: `cd RuyiDemo && ./run.sh`

## Engine

[ThorVG](https://github.com/thorvg/thorvg) via SPM binary package [`vnixx/thorvg.swift`](https://github.com/vnixx/thorvg.swift) (CPU raster + SVG + C API).

## License

MIT (see `LICENSE`).
