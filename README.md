# Ruyi

Cross-platform SVG **load & render** runtime.  
Scale and tint your own SVGs — **no built-in icon set**.

> 如意金箍棒：能大能小 — vector graphics that scale freely.

## What it does

- Render SVG source strings, files, or bundled resources into platform-native images.
- Keep original SVG colors or apply a solid tint with the common `size` / `color` / `strokeWidth` API.
- Override stroke width with either fixed logical units or Lucide-style scaling from a reference size.
- Gradient tint is also available through `GradientTint` for icon-wide linear or radial effects.
- Use the same rendering model across Apple, Android, and HarmonyOS, backed by ThorVG.

## Repository layout

Multi-platform monorepo:

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
Harmony/
  Ruyi/                    # Open this folder in DevEco Studio
    ruyi/                  # ArkTS + NAPI HAR → @reers/ruyi
    ruyidemo/              # Demo HAP
```

## Platforms

<details>
<summary><strong>Apple (SPM)</strong></summary>

### Platforms

- iOS 13+ (arm64 / Simulator arm64)
- macOS 10.15+ (Apple Silicon)
- tvOS 13+ (arm64 / Simulator arm64)
- watchOS 7+ (arm64 / Simulator arm64)
- visionOS 1+ (arm64 / Simulator arm64)

> ThorVG binary ships Apple Silicon slices only (via [`vnixx/thorvg.ruyi`](https://github.com/vnixx/thorvg.ruyi) `1.1.0+`).

### Install

```swift
dependencies: [
    .package(url: "https://github.com/reers/Ruyi.git", from: "1.0.1")
]
```

### Usage

```swift
import Ruyi

let image = Ruyi.image(
    data: svgData,
    options: .init(
        size: CGSize(width: 40, height: 40),
        color: .systemRed,
        strokeWidth: 2
    )
)
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

[ThorVG](https://github.com/thorvg/thorvg) via SPM binary package [`vnixx/thorvg.ruyi`](https://github.com/vnixx/thorvg.ruyi) (CPU raster + SVG + C API).

</details>

<details>
<summary><strong>Android (Maven)</strong></summary>

### Platforms

- Android API 24+ (library); demo targets API 26+
- Native ThorVG ships **arm64-v8a** only (via [`io.github.vnixx:thorvg`](https://central.sonatype.com/artifact/io.github.vnixx/thorvg))

### Install

```kotlin
dependencies {
    implementation("io.github.reers:ruyi:1.0.0")
}
```

### Usage

```kotlin
import io.github.reers.ruyi.Ruyi

val bitmap = Ruyi.image(
    svgString,
    Ruyi.Options(
        sizeDp = 40f,
        color = 0xFFFF0000.toInt(),
        strokeWidth = 2f,
        density = resources.displayMetrics.density,
    ),
)

// or: Ruyi.image(context, "heart", options)
```

### Demo

```bash
cd Android/Ruyi
./gradlew :ruyidemo:installDebug
```

Open `Android/Ruyi` in Android Studio. Sample icons live in `ruyidemo/src/main/assets/icons` (demo only).

### Engine

[ThorVG](https://github.com/thorvg/thorvg) via Maven [`io.github.vnixx:thorvg`](https://central.sonatype.com/artifact/io.github.vnixx/thorvg) `1.1.0+` (CPU raster + SVG + C API Prefab; Kotlin/JNI bridge lives in Ruyi).

### Publishing

See [`Android/Ruyi/PUBLISHING.md`](Android/Ruyi/PUBLISHING.md). Coordinates: **`io.github.reers:ruyi`**.

</details>

<details>
<summary><strong>HarmonyOS (OHPM)</strong></summary>

### Platforms

- HarmonyOS NEXT (API 12+ recommended)
- Native ThorVG + Ruyi bridge ship **arm64-v8a** only (via [`@vnixx/thorvg`](https://ohpm.openharmony.cn/#/cn/detail/@vnixx/thorvg))

### Install

```bash
ohpm install @reers/ruyi
```

Or in `oh-package.json5`:

```json5
"dependencies": {
  "@reers/ruyi": "1.0.0"
}
```

### Usage

```ts
import { Ruyi } from '@reers/ruyi';
import { display } from '@kit.ArkUI';

const density = display.getDefaultDisplaySync().densityDPI / 160;

const pixelMap = await Ruyi.image(svgString, {
  size: 40,
  color: 0xFFFF0000,  // ARGB
  strokeWidth: 2,
  density,
});

const maps = await Ruyi.imageBatch(svgSources, {
  size: 24,
  color: 0xFFFF0000,  // ARGB
  density,
});
```

`svgSources` can be SVG XML strings or `ArrayBuffer`s read from rawfile, cache,
or network responses.

Only `size` is required in Harmony options. Other rendering options can be
omitted; pass the current display density when you want vp output to resolve to
physical pixels.

Engine lazy-inits on first render (no public `engineInit` / `engineTerm`).

### Demo

Open `Harmony/Ruyi` in DevEco Studio, then:

```bash
cd Harmony/Ruyi
export DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk
hvigorw assembleHap -p module=ruyidemo@default
```

More detail: [`Harmony/Ruyi/README.md`](Harmony/Ruyi/README.md).

### Engine

[ThorVG](https://github.com/thorvg/thorvg) via OHPM [`@vnixx/thorvg`](https://ohpm.openharmony.cn/#/cn/detail/@vnixx/thorvg) `1.1.0+` (CPU raster + SVG + C API HAR; ArkTS/NAPI bridge lives in Ruyi).

Coordinates: **`@reers/ruyi`**.

</details>

## License

MIT (see `LICENSE`).
