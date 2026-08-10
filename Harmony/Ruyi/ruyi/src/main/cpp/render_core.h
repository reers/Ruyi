#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace thorvg_render {

struct RenderRequest {
    const char *svgData = nullptr;
    uint32_t svgLength = 0;
    int widthPx = 0;
    int heightPx = 0;
    int32_t argb = 0;           // 0 = keep SVG colors; else 0xAARRGGBB
    float strokeWidth = -1.f;   // < 0 = keep SVG strokes
    bool absoluteStroke = true;
    float designSize = 0.f;
    float referenceSize = 24.f;
};

/** Ensure software engine started (idempotent). */
void ensureEngine();

int engineInit(unsigned threads);
int engineTerm();
std::string version();

/**
 * Render SVG → ARGB8888 premultiplied pixels (same packing as Android 0xAARRGGBB).
 * Empty vector means failure.
 */
std::vector<uint32_t> renderSvg(const RenderRequest &req);

}  // namespace thorvg_render
