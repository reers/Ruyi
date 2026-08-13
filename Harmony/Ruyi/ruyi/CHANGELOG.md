# Changelog

## 1.0.2

- Add solid and icon-wide linear / radial gradient tinting.
- Add object-style `RuyiOptionsInit` with `size`, optional `color`, `gradient`, `strokeWidth`, `referenceSize`, and `density`.
- Move Harmony gradient mask composition and batch rendering hot paths into native C++ for smoother live updates.
- Allow `Ruyi.imageBatch` to render SVG XML strings or `ArrayBuffer` sources.

## 1.0.0

- Initial OHPM release of `@reers/ruyi` for HarmonyOS.
- ArkTS API: `Ruyi.image` / `Ruyi.imageBatch` / `Ruyi.version` → `PixelMap`.
- In-module NAPI bridge (`libruyi.so`) over `@vnixx/thorvg` C API.
- Engine lazy-inits on first render (aligned with Apple / Android Ruyi).
