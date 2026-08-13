# Ruyi

Cross-platform SVG **load & render** runtime.  
Scale and tint your own SVGs — **no built-in icon set**.

> 如意金箍棒：能大能小 — vector graphics that scale freely.

## What it does

- Render SVG source strings, files, or bundled resources into platform-native images.
- Keep original SVG colors, apply a solid tint, or apply an icon-wide linear / radial gradient tint.
- Override stroke width with either fixed logical units or Lucide-style scaling from a reference size.
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

---

## Apple (SPM)

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
        gradient: .linear(
            stops: [
                Ruyi.GradientStop(
                    offset: 0,
                    color: RuyiColor(red: 0.95, green: 0.35, blue: 0.45, alpha: 1)
                ),
                Ruyi.GradientStop(
                    offset: 1,
                    color: RuyiColor(red: 0.35, green: 0.55, blue: 1.0, alpha: 1)
                ),
            ],
            direction: .angle(90)
        ),
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

---

## Android (Maven)

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
        gradient = Ruyi.GradientTint.linear(
            stops = listOf(
                Ruyi.GradientStop(0f, 0xFFF25973.toInt()),
                Ruyi.GradientStop(1f, 0xFF598CFF.toInt()),
            ),
            angleDegrees = 90f,
        ),
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

---

## HarmonyOS (OHPM)

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
import { Ruyi, GradientStop, GradientTint } from '@reers/ruyi';
import { display } from '@kit.ArkUI';

const density = display.getDefaultDisplaySync().densityDPI / 160;

const pixelMap = await Ruyi.image(svgString, {
  size: 40,
  strokeWidth: 2,
  density,
  gradient: GradientTint.linearAngle([
    new GradientStop(0, 0xFFF25973),
    new GradientStop(1, 0xFF598CFF),
  ], 90),
});

const maps = await Ruyi.imageBatch(svgStrings, {
  size: 24,
  color: 0xFFFF0000,  // ARGB
  density,
});
```

Only `size` is required in Harmony options. `color`, `gradient`, `strokeWidth`,
`absoluteStrokeWidth`, `referenceSize`, and `density` can be omitted; pass the
current display density when you want vp output to resolve to physical pixels.

Engine lazy-inits on first render (no public `engineInit` / `engineTerm`).

Gradient tint on Harmony uses a native mask-composition path. Apple and Android
can inject gradients into ThorVG paints directly, while Harmony renders a white
alpha mask and applies the icon-wide gradient in C++ before creating the
`PixelMap`. This keeps the result aligned with the public API semantics and
avoids per-pixel ArkTS work during live size / stroke updates.

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

---

## License

MIT (see `LICENSE`).
