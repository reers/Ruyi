# Ruyi (HarmonyOS)

Open this folder in DevEco Studio.

## Layout

```text
ruyi/       # @reers/ruyi HAR — ArkTS API + NAPI bridge (libruyi.so)
ruyidemo/   # Demo HAP (icon grid)
libs/       # Local @vnixx/thorvg C API HAR (gitignored; for testing)
```

Layering matches Android:

| Layer | Owns |
|-------|------|
| `@vnixx/thorvg` | Trimmed ThorVG C API (`libthorvg.so`) |
| `@reers/ruyi` | NAPI + `Ruyi.image` / `imageBatch` → PixelMap |

## ThorVG dependency

```json5
"@vnixx/thorvg": "1.1.0"
```

```bash
ohpm install
(cd ruyi && ohpm install)
(cd ruyidemo && ohpm install)
```

Optional local HAR fallback (offline): `./scripts/sync_local_thorvg.sh` then temporarily point `ruyi/oh-package.json5` at `file:../libs/thorvg.har`.

## Build

```bash
export DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk
export PATH="/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin:$PATH"
hvigorw assembleHap -p module=ruyidemo@default
```
