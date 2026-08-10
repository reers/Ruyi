# Changelog

## 1.0.0

- Initial OHPM release of `@reers/ruyi` for HarmonyOS.
- ArkTS API: `Ruyi.image` / `Ruyi.imageBatch` / `Ruyi.version` → `PixelMap`.
- In-module NAPI bridge (`libruyi.so`) over `@vnixx/thorvg` C API.
- Engine lazy-inits on first render (aligned with Apple / Android Ruyi).
