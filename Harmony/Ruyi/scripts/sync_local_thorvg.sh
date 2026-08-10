#!/usr/bin/env bash
# Refresh local @vnixx/thorvg C API artifacts for Harmony Ruyi testing
# (until the OHPM package clears review).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Default: sibling clone of thorvg.ruyi monorepo.
if [[ -z "${THORVG_HARMONY:-}" ]]; then
  for candidate in \
    "$ROOT/../../../workspace/thorvg.ruyi/harmony/thorvg" \
    "$HOME/workspace/thorvg.ruyi/harmony/thorvg"
  do
    if [[ -d "$candidate" ]]; then
      THORVG_HARMONY="$(cd "$candidate" && pwd)"
      break
    fi
  done
fi
if [[ -z "${THORVG_HARMONY:-}" || ! -d "${THORVG_HARMONY}" ]]; then
  echo "Set THORVG_HARMONY to thorvg.ruyi/harmony/thorvg"
  exit 1
fi

HAR="${THORVG_HARMONY}/build/default/outputs/default/thorvg.har"
HEADER="${THORVG_HARMONY}/src/main/cpp/include/thorvg_capi.h"
OUT_LIBS="${ROOT}/libs"
OUT_NATIVE="${OUT_LIBS}/native"

if [[ ! -f "$HAR" ]]; then
  echo "Missing HAR: $HAR"
  echo "Build it in thorvg.ruyi/harmony first."
  exit 1
fi
if [[ ! -f "$HEADER" ]]; then
  echo "Missing header: $HEADER"
  exit 1
fi

mkdir -p "${OUT_NATIVE}/include" "${OUT_NATIVE}/arm64-v8a"
cp "$HAR" "${OUT_LIBS}/thorvg.har"
cp "$HEADER" "${OUT_NATIVE}/include/thorvg_capi.h"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT
cd "$WORKDIR"
gzip -dc "$HAR" | tar -xf -
cp package/libs/arm64-v8a/libthorvg.so "${OUT_NATIVE}/arm64-v8a/"
cp package/libs/arm64-v8a/libc++_shared.so "${OUT_NATIVE}/arm64-v8a/" 2>/dev/null || true

echo "Synced local thorvg → ${OUT_LIBS}"
ls -lh "${OUT_LIBS}/thorvg.har" "${OUT_NATIVE}/include/thorvg_capi.h" "${OUT_NATIVE}/arm64-v8a/libthorvg.so"
