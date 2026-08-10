#include "render_core.h"

#include <algorithm>
#include <mutex>
#include <vector>

#include "thorvg_capi.h"

namespace thorvg_render {
namespace {

struct StyleCtx {
    bool hasColor = false;
    uint8_t r = 0;
    uint8_t g = 0;
    uint8_t b = 0;
    uint8_t a = 255;
    bool hasStroke = false;
    float strokeWidth = 0.f;
};

bool applyStyle(Tvg_Paint paint, void *data) {
    if (paint == nullptr || data == nullptr) {
        return true;
    }
    auto *ctx = static_cast<StyleCtx *>(data);

    Tvg_Type type = TVG_TYPE_UNDEF;
    if (tvg_paint_get_type(paint, &type) != TVG_RESULT_SUCCESS || type != TVG_TYPE_SHAPE) {
        return true;
    }

    float strokeW = 0.f;
    (void)tvg_shape_get_stroke_width(paint, &strokeW);

    if (ctx->hasStroke && ctx->strokeWidth >= 0.f) {
        (void)tvg_shape_set_stroke_width(paint, ctx->strokeWidth);
        strokeW = ctx->strokeWidth;
    }

    if (ctx->hasColor) {
        uint8_t fr = 0, fg = 0, fb = 0, fa = 0;
        if (tvg_shape_get_fill_color(paint, &fr, &fg, &fb, &fa) == TVG_RESULT_SUCCESS && fa > 0) {
            (void)tvg_shape_set_fill_color(paint, ctx->r, ctx->g, ctx->b, ctx->a);
        }
        if (strokeW > 0.f) {
            (void)tvg_shape_set_stroke_color(paint, ctx->r, ctx->g, ctx->b, ctx->a);
        }
    }
    return true;
}

}  // namespace

// Same as Apple / Android Ruyi: lazy init on first render.
void ensureEngine() {
    static std::once_flag once;
    std::call_once(once, [] { (void)tvg_engine_init(0); });
}

int engineInit(unsigned threads) {
    return static_cast<int>(tvg_engine_init(threads));
}

int engineTerm() {
    return static_cast<int>(tvg_engine_term());
}

std::string version() {
    uint32_t major = 0;
    uint32_t minor = 0;
    uint32_t micro = 0;
    const char *ver = nullptr;
    if (tvg_engine_version(&major, &minor, &micro, &ver) != TVG_RESULT_SUCCESS || ver == nullptr) {
        return "unknown";
    }
    return ver;
}

std::vector<uint32_t> renderSvg(const RenderRequest &req) {
    if (req.svgData == nullptr || req.svgLength == 0 || req.widthPx <= 0 || req.heightPx <= 0) {
        return {};
    }

    ensureEngine();

    Tvg_Paint picture = tvg_picture_new();
    if (picture == nullptr) {
        return {};
    }

    bool pictureOwnedByCanvas = false;
    auto releasePicture = [&]() {
        if (!pictureOwnedByCanvas && picture != nullptr) {
            tvg_paint_rel(picture);
            picture = nullptr;
        }
    };

    const auto load = tvg_picture_load_data(
        picture,
        req.svgData,
        req.svgLength,
        "svg",
        nullptr,
        true
    );
    if (load != TVG_RESULT_SUCCESS) {
        releasePicture();
        return {};
    }

    float contentW = 0.f;
    float contentH = 0.f;
    (void)tvg_picture_get_size(picture, &contentW, &contentH);
    const float viewEdge = std::max(1.f, std::min(contentW, contentH));

    if (tvg_picture_set_size(picture, static_cast<float>(req.widthPx), static_cast<float>(req.heightPx))
        != TVG_RESULT_SUCCESS) {
        releasePicture();
        return {};
    }

    StyleCtx style;
    if (req.argb != 0) {
        style.hasColor = true;
        style.a = static_cast<uint8_t>((req.argb >> 24) & 0xff);
        style.r = static_cast<uint8_t>((req.argb >> 16) & 0xff);
        style.g = static_cast<uint8_t>((req.argb >> 8) & 0xff);
        style.b = static_cast<uint8_t>(req.argb & 0xff);
    }
    if (req.strokeWidth >= 0.f) {
        style.hasStroke = true;
        if (req.absoluteStroke) {
            const float edge = std::max(1.f, req.designSize > 0.f ? req.designSize
                                                                  : static_cast<float>(std::min(req.widthPx, req.heightPx)));
            style.strokeWidth = req.strokeWidth * (viewEdge / edge);
        } else {
            const float ref = std::max(1.f, req.referenceSize);
            style.strokeWidth = req.strokeWidth * (viewEdge / ref);
        }
    }

    if (style.hasColor || style.hasStroke) {
        Tvg_Accessor accessor = tvg_accessor_new();
        if (accessor != nullptr) {
            (void)tvg_accessor_set(accessor, picture, applyStyle, &style);
            tvg_accessor_del(accessor);
        }
    }

    Tvg_Canvas canvas = tvg_swcanvas_create(TVG_ENGINE_OPTION_NONE);
    if (canvas == nullptr) {
        releasePicture();
        return {};
    }

    const int pixelCount = req.widthPx * req.heightPx;
    std::vector<uint32_t> buffer(static_cast<size_t>(pixelCount), 0);

    if (tvg_swcanvas_set_target(
            canvas,
            buffer.data(),
            static_cast<uint32_t>(req.widthPx),
            static_cast<uint32_t>(req.widthPx),
            static_cast<uint32_t>(req.heightPx),
            TVG_COLORSPACE_ARGB8888
        ) != TVG_RESULT_SUCCESS) {
        tvg_canvas_destroy(canvas);
        releasePicture();
        return {};
    }

    if (tvg_canvas_add(canvas, picture) != TVG_RESULT_SUCCESS) {
        tvg_canvas_destroy(canvas);
        releasePicture();
        return {};
    }
    pictureOwnedByCanvas = true;

    if (tvg_canvas_update(canvas) != TVG_RESULT_SUCCESS ||
        tvg_canvas_draw(canvas, true) != TVG_RESULT_SUCCESS ||
        tvg_canvas_sync(canvas) != TVG_RESULT_SUCCESS) {
        tvg_canvas_destroy(canvas);
        return {};
    }

    tvg_canvas_destroy(canvas);
    return buffer;
}

}  // namespace thorvg_render
