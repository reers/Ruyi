# @reers/ruyi

HarmonyOS SVG **load & render** runtime (ArkTS API + NAPI over ThorVG C API).

Ships no built-in icons — pass your own SVG strings / rawfile assets.  
Scale and tint via `RuyiOptions` (aligned with Apple / Android Ruyi).

Depends on [`@vnixx/thorvg`](https://ohpm.openharmony.cn/#/cn/detail/@vnixx/thorvg) for the trimmed ThorVG native library.

## Install

```bash
ohpm install @reers/ruyi
```

Or in `oh-package.json5`:

```json5
"dependencies": {
  "@reers/ruyi": "1.0.0"
}
```

## Usage

```ts
import { Ruyi, RuyiOptions } from '@reers/ruyi';
import { display } from '@kit.ArkUI';

const density = display.getDefaultDisplaySync().densityDPI / 160;
const options = new RuyiOptions(
  24,                 // sizeVp
  0xFFFF0000,         // color ARGB (optional)
  2,                  // strokeWidth pt (optional)
  true,               // absoluteStrokeWidth
  24,                 // referenceSize
  density,
);

const pixelMap = await Ruyi.image(svgString, options);
// or batch:
const maps = await Ruyi.imageBatch(svgStrings, options);
```

Engine lazy-inits on first render (no public `engineInit` / `engineTerm`).

## Contents

| Item | Value |
|------|--------|
| Public API | `Ruyi` / `RuyiOptions` → `PixelMap` |
| Native | `libruyi.so` (NAPI bridge) |
| Engine dep | `@vnixx/thorvg` → `libthorvg.so` |
| ABI | arm64-v8a |

## Source

[reers/Ruyi](https://github.com/reers/Ruyi) → `Harmony/Ruyi/ruyi`

## License

MIT — see `LICENSE`.
