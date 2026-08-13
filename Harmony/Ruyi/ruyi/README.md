# @reers/ruyi

HarmonyOS SVG **load & render** runtime (ArkTS API + NAPI over ThorVG C API).

Ships no built-in icons — pass your own SVG strings or rawfile bytes.
Scale and tint via object-style options (aligned with Apple / Android Ruyi).

Depends on [`@vnixx/thorvg`](https://ohpm.openharmony.cn/#/cn/detail/@vnixx/thorvg) for the trimmed ThorVG native library.

## Install

```bash
ohpm install @reers/ruyi
```

Or in `oh-package.json5`:

```json5
"dependencies": {
  "@reers/ruyi": "1.0.2"
}
```

## Usage

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

const maps = await Ruyi.imageBatch(svgSources, {
  size: 24,
  color: 0xFFFF0000,  // ARGB
  strokeWidth: 2,
  absoluteStrokeWidth: true,
  referenceSize: 24,
  density,
});
```

`svgSources` can be SVG XML strings or `ArrayBuffer`s read from rawfile, cache,
or network responses.

Engine lazy-inits on first render (no public `engineInit` / `engineTerm`).

## Contents

| Item | Value |
|------|--------|
| Public API | `Ruyi` / `RuyiOptionsInit` / `RuyiOptions` → `PixelMap` |
| Native | `libruyi.so` (NAPI bridge) |
| Engine dep | `@vnixx/thorvg` → `libthorvg.so` |
| ABI | arm64-v8a |

## Source

[reers/Ruyi](https://github.com/reers/Ruyi) → `Harmony/Ruyi/ruyi`

## License

MIT — see `LICENSE`.
