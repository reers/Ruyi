#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace thorvg_render {

enum class GradKind : int32_t {
    None = 0,
    Linear = 1,
    Radial = 2,
};

struct ColorStop {
    float offset = 0.f;
    uint8_t r = 0;
    uint8_t g = 0;
    uint8_t b = 0;
    uint8_t a = 255;
};

struct RenderRequest {
    const char *svgData = nullptr;
    uint32_t svgLength = 0;
    int widthPx = 0;
    int heightPx = 0;
    int32_t argb = 0;           // 0 = keep SVG colors; else 0xAARRGGBB (ignored if gradient set)
    float strokeWidth = -1.f;   // < 0 = keep SVG strokes
    bool absoluteStroke = false;
    float designSize = 0.f;
    float referenceSize = 24.f;
    GradKind gradKind = GradKind::None;
    std::vector<ColorStop> stops;
    // Normalized 0…1 geometry (linear: sx,sy,ex,ey; radial: cx,cy,r,fx,fy,fr).
    float geom[6] = {0, 0, 0, 0, 0, 0};
    int geomCount = 0;
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
