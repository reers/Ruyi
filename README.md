# Ruyi

Cross-platform SVG **load & render** runtime.  
Scale and tint your own SVGs — **no built-in icon set**.

> 如意金箍棒：能大能小 — vector graphics that scale freely.

## Repository layout

MMKV-style multi-platform monorepo:

```text
Package.swift              # SPM entry (path → Apple/Sources/Ruyi)
Apple/
  Sources/Ruyi/            # Swift API
  Tests/RuyiTests/
  RuyiDemo/                # XcodeGen demos (iOS / macOS / tvOS / watchOS / visionOS)
Android/
  Ruyi/                    # Open this folder in Android Studio
    ruyi/                  # Kotlin library → io.github.reers:ruyi
    ruyidemo/              # Compose demo
```

---

## Apple (SPM)

### Platforms

- iOS 13+ (arm64 / Simulator arm64)
- macOS 10.15+ (Apple Silicon)
- tvOS 13+ (arm64 / Simulator arm64)
- watchOS 7+ (arm64 / Simulator arm64)
- visionOS 1+ (arm64 / Simulator arm64)

> ThorVG binary ships Apple Silicon slices only (via [`vnixx/thorvg.swift`](https://github.com/vnixx/thorvg.swift) `0.0.3+`).

### Install

```swift
dependencies: [
    .package(url: "https://github.com/reers/Ruyi.git", from: "0.1.0")
]
```

### Usage

```swift
import Ruyi

let options = Ruyi.Options(
    size: CGSize(width: 24, height: 24),
    color: .systemRed,
    strokeWidth: 2
)

let image = Ruyi.image(data: svgData, options: options)
```

Also:

```swift
Ruyi.image(contentsOf: fileURL, options: ...)
Ruyi.image(named: "icon", in: .module, options: ...)
```

### Do not use Asset Catalog

Ruyi needs the **original SVG source** (file path, bundle resource, or in-memory XML/`Data`).

**Do not put SVGs in an Xcode Asset Catalog.** Assets compile SVG into bitmaps (or Apple’s internal vector form for `UIImage`). Neither exposes the SVG XML, so Ruyi / ThorVG cannot parse them — with or without “Preserve Vector Data”.

Put `.svg` files in the app / package **bundle** (Copy Bundle Resources / SPM `resources`) and load via `Ruyi.image(named:in:)` / `contentsOf:` / `data:`.

### Demo

Open `Apple/RuyiDemo/RuyiDemo.xcodeproj` in Xcode:

| Scheme | Platform |
|--------|----------|
| **RuyiDemo-macOS** | macOS |
| **RuyiDemo-iOS** | iOS Simulator / device |
| **RuyiDemo-tvOS** | tvOS Simulator / device |
| **RuyiDemo-watchOS** | watchOS Simulator / device |
| **RuyiDemo-visionOS** | visionOS Simulator / device |

```bash
cd Apple/RuyiDemo && xcodegen generate
```

macOS CLI fallback: `cd Apple/RuyiDemo && ./run.sh`

### Engine

[ThorVG](https://github.com/thorvg/thorvg) via SPM binary package [`vnixx/thorvg.swift`](https://github.com/vnixx/thorvg.swift) (CPU raster + SVG + C API).

---

## Android (Maven)

### Platforms

- Android API 24+ (library); demo targets API 26+
- Native ThorVG ships **arm64-v8a** only (via [`io.github.vnixx:thorvg`](https://central.sonatype.com/artifact/io.github.vnixx/thorvg))

### Install

```kotlin
dependencies {
    implementation("io.github.reers:ruyi:0.0.1")
}
```

> Until the first Central publish, use a local project dependency or `publishToMavenLocal` (see [`Android/Ruyi/PUBLISHING.md`](Android/Ruyi/PUBLISHING.md)).

### Usage

```kotlin
import io.github.reers.ruyi.Ruyi

val options = Ruyi.Options(
    sizeDp = 24f,
    color = 0xFFFF0000.toInt(),
    strokeWidth = 2f,
    density = resources.displayMetrics.density,
)

val bitmap = Ruyi.image(svgString, options)
// or: Ruyi.image(context, "heart", options)
```

### Demo

```bash
cd Android/Ruyi
./gradlew :ruyidemo:installDebug
```

Open `Android/Ruyi` in Android Studio. Sample icons live in `ruyidemo/src/main/assets/icons` (demo only).

### Engine

[ThorVG](https://github.com/thorvg/thorvg) via Maven [`io.github.vnixx:thorvg`](https://github.com/vnixx/thorvg.android) (CPU raster + SVG + C API + JNI).

### Publishing

See [`Android/Ruyi/PUBLISHING.md`](Android/Ruyi/PUBLISHING.md). Coordinates: **`io.github.reers:ruyi`**.

---

## License

MIT (see `LICENSE`).
