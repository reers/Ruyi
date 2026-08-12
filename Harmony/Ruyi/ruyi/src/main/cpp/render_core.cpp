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
    GradKind gradKind = GradKind::None;
    std::vector<Tvg_Color_Stop> stops;
    float x1 = 0, y1 = 0, x2 = 0, y2 = 0;
    float cx = 0, cy = 0, radius = 0, fx = 0, fy = 0, fr = 0;
};

Tvg_Gradient makeGradient(const StyleCtx &ctx) {
    if (ctx.stops.size() < 2) {
        return nullptr;
    }
    Tvg_Gradient grad = nullptr;
    if (ctx.gradKind == GradKind::Linear) {
        grad = tvg_linear_gradient_new();
        if (grad == nullptr) {
            return nullptr;
        }
        (void)tvg_linear_gradient_set(grad, ctx.x1, ctx.y1, ctx.x2, ctx.y2);
    } else if (ctx.gradKind == GradKind::Radial) {
        grad = tvg_radial_gradient_new();
        if (grad == nullptr) {
            return nullptr;
        }
        (void)tvg_radial_gradient_set(grad, ctx.cx, ctx.cy, ctx.radius, ctx.fx, ctx.fy, ctx.fr);
    } else {
        return nullptr;
    }
    (void)tvg_gradient_set_color_stops(grad, ctx.stops.data(), static_cast<uint32_t>(ctx.stops.size()));
    return grad;
}

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

    // Match Apple/Android: only override width when the shape already has a stroke.
    if (ctx->hasStroke && ctx->strokeWidth >= 0.f && strokeW > 0.f) {
        (void)tvg_shape_set_stroke_width(paint, ctx->strokeWidth);
        strokeW = ctx->strokeWidth;
    }

    uint8_t fr = 0, fg = 0, fb = 0, fa = 0;
    const bool hasOpaqueFill =
        tvg_shape_get_fill_color(paint, &fr, &fg, &fb, &fa) == TVG_RESULT_SUCCESS && fa > 0;
    const bool hasStroke = strokeW > 0.f;

    if (ctx->gradKind != GradKind::None && ctx->stops.size() >= 2) {
        if (hasOpaqueFill) {
            if (Tvg_Gradient fillGrad = makeGradient(*ctx)) {
                (void)tvg_shape_set_gradient(paint, fillGrad);
            }
        }
        if (hasStroke) {
            if (Tvg_Gradient strokeGrad = makeGradient(*ctx)) {
                (void)tvg_shape_set_stroke_gradient(paint, strokeGrad);
            }
        }
    } else if (ctx->hasColor) {
        if (hasOpaqueFill) {
            (void)tvg_shape_set_fill_color(paint, ctx->r, ctx->g, ctx->b, ctx->a);
        }
        if (hasStroke) {
            (void)tvg_shape_set_stroke_color(paint, ctx->r, ctx->g, ctx->b, ctx->a);
        }
    }
    return true;
}

}  // namespace

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
    const float w = std::max(1.f, contentW);
    const float h = std::max(1.f, contentH);

    if (tvg_picture_set_size(picture, static_cast<float>(req.widthPx), static_cast<float>(req.heightPx))
        != TVG_RESULT_SUCCESS) {
        releasePicture();
        return {};
    }

    StyleCtx style;
    if ((req.gradKind == GradKind::Linear || req.gradKind == GradKind::Radial) &&
        req.stops.size() >= 2) {
        style.gradKind = req.gradKind;
        style.stops.reserve(req.stops.size());
        for (const auto &s : req.stops) {
            Tvg_Color_Stop stop{};
            stop.offset = std::min(1.f, std::max(0.f, s.offset));
            stop.r = s.r;
            stop.g = s.g;
            stop.b = s.b;
            stop.a = s.a;
            style.stops.push_back(stop);
        }
        std::sort(style.stops.begin(), style.stops.end(), [](const Tvg_Color_Stop &a, const Tvg_Color_Stop &b) {
            return a.offset < b.offset;
        });
        if (req.gradKind == GradKind::Linear && req.geomCount >= 4) {
            style.x1 = req.geom[0] * w;
            style.y1 = req.geom[1] * h;
            style.x2 = req.geom[2] * w;
            style.y2 = req.geom[3] * h;
        } else if (req.gradKind == GradKind::Radial && req.geomCount >= 6) {
            style.cx = req.geom[0] * w;
            style.cy = req.geom[1] * h;
            style.radius = std::max(0.f, req.geom[2]) * viewEdge;
            style.fx = req.geom[3] * w;
            style.fy = req.geom[4] * h;
            style.fr = std::max(0.f, req.geom[5]) * viewEdge;
        } else {
            style.gradKind = GradKind::None;
            style.stops.clear();
        }
    }

    if (style.gradKind == GradKind::None && req.argb != 0) {
        style.hasColor = true;
        const uint32_t argb = static_cast<uint32_t>(req.argb);
        style.a = static_cast<uint8_t>((argb >> 24) & 0xff);
        style.r = static_cast<uint8_t>((argb >> 16) & 0xff);
        style.g = static_cast<uint8_t>((argb >> 8) & 0xff);
        style.b = static_cast<uint8_t>(argb & 0xff);
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

    if (style.hasColor || style.hasStroke || style.gradKind != GradKind::None) {
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
