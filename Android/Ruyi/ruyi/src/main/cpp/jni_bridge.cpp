#include <jni.h>

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <mutex>
#include <vector>

#include "thorvg_capi.h"

namespace {

enum class GradKind : int32_t {
    None = 0,
    Linear = 1,
    Radial = 2,
};

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
    // Resolved into SVG content units.
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

    // Match Apple: only override width when the shape already has a stroke.
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

void ensureEngine() {
    static std::once_flag once;
    std::call_once(once, [] { (void)tvg_engine_init(0); });
}

bool fillStops(
    JNIEnv *env,
    jfloatArray stopOffsets,
    jintArray stopColors,
    std::vector<Tvg_Color_Stop> &out
) {
    if (stopOffsets == nullptr || stopColors == nullptr) {
        return false;
    }
    const jsize nOff = env->GetArrayLength(stopOffsets);
    const jsize nCol = env->GetArrayLength(stopColors);
    const jsize n = std::min(nOff, nCol);
    if (n < 2) {
        return false;
    }
    std::vector<jfloat> offsets(static_cast<size_t>(n));
    std::vector<jint> colors(static_cast<size_t>(n));
    env->GetFloatArrayRegion(stopOffsets, 0, n, offsets.data());
    env->GetIntArrayRegion(stopColors, 0, n, colors.data());
    out.clear();
    out.reserve(static_cast<size_t>(n));
    for (jsize i = 0; i < n; ++i) {
        const float offset = std::min(1.f, std::max(0.f, offsets[static_cast<size_t>(i)]));
        const jint argb = colors[static_cast<size_t>(i)];
        Tvg_Color_Stop stop{};
        stop.offset = offset;
        stop.a = static_cast<uint8_t>((argb >> 24) & 0xff);
        stop.r = static_cast<uint8_t>((argb >> 16) & 0xff);
        stop.g = static_cast<uint8_t>((argb >> 8) & 0xff);
        stop.b = static_cast<uint8_t>(argb & 0xff);
        out.push_back(stop);
    }
    std::sort(out.begin(), out.end(), [](const Tvg_Color_Stop &a, const Tvg_Color_Stop &b) {
        return a.offset < b.offset;
    });
    return out.size() >= 2;
}

}  // namespace

extern "C" {

JNIEXPORT jstring JNICALL
Java_io_github_reers_ruyi_ThorVG_nativeVersion(JNIEnv *env, jclass) {
    uint32_t major = 0;
    uint32_t minor = 0;
    uint32_t micro = 0;
    const char *version = nullptr;
    if (tvg_engine_version(&major, &minor, &micro, &version) != TVG_RESULT_SUCCESS || version == nullptr) {
        return env->NewStringUTF("unknown");
    }
    return env->NewStringUTF(version);
}

/**
 * Render SVG → ARGB_8888 premultiplied pixels (Android 0xAARRGGBB).
 *
 * gradientKind: 0=none, 1=linear, 2=radial (takes precedence over solid argb).
 * stopOffsets / stopColors: parallel arrays (ARGB ints); need ≥2 stops for gradient.
 * gradGeom: linear [sx,sy,ex,ey] or radial [cx,cy,r,fx,fy,fr] in normalized 0…1 units.
 */
JNIEXPORT jintArray JNICALL
Java_io_github_reers_ruyi_ThorVG_nativeRenderSvg(
    JNIEnv *env,
    jclass,
    jbyteArray svgBytes,
    jint widthPx,
    jint heightPx,
    jint argb,
    jfloat strokeWidth,
    jboolean absoluteStroke,
    jfloat designSize,
    jfloat referenceSize,
    jint gradientKind,
    jfloatArray stopOffsets,
    jintArray stopColors,
    jfloatArray gradGeom
) {
    if (svgBytes == nullptr || widthPx <= 0 || heightPx <= 0) {
        return nullptr;
    }

    const jsize length = env->GetArrayLength(svgBytes);
    if (length <= 0) {
        return nullptr;
    }

    jbyte *bytes = env->GetByteArrayElements(svgBytes, nullptr);
    if (bytes == nullptr) {
        return nullptr;
    }

    ensureEngine();

    Tvg_Paint picture = tvg_picture_new();
    if (picture == nullptr) {
        env->ReleaseByteArrayElements(svgBytes, bytes, JNI_ABORT);
        return nullptr;
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
        reinterpret_cast<const char *>(bytes),
        static_cast<uint32_t>(length),
        "svg",
        nullptr,
        true
    );
    env->ReleaseByteArrayElements(svgBytes, bytes, JNI_ABORT);
    if (load != TVG_RESULT_SUCCESS) {
        releasePicture();
        return nullptr;
    }

    float contentW = 0.f;
    float contentH = 0.f;
    (void)tvg_picture_get_size(picture, &contentW, &contentH);
    const float viewEdge = std::max(1.f, std::min(contentW, contentH));
    const float w = std::max(1.f, contentW);
    const float h = std::max(1.f, contentH);

    if (tvg_picture_set_size(picture, static_cast<float>(widthPx), static_cast<float>(heightPx)) != TVG_RESULT_SUCCESS) {
        releasePicture();
        return nullptr;
    }

    StyleCtx style;
    if (gradientKind == static_cast<jint>(GradKind::Linear) ||
        gradientKind == static_cast<jint>(GradKind::Radial)) {
        if (fillStops(env, stopOffsets, stopColors, style.stops) && gradGeom != nullptr) {
            const jsize geomLen = env->GetArrayLength(gradGeom);
            std::vector<jfloat> geom(static_cast<size_t>(std::max(geomLen, 0)));
            if (geomLen > 0) {
                env->GetFloatArrayRegion(gradGeom, 0, geomLen, geom.data());
            }
            if (gradientKind == static_cast<jint>(GradKind::Linear) && geomLen >= 4) {
                style.gradKind = GradKind::Linear;
                style.x1 = geom[0] * w;
                style.y1 = geom[1] * h;
                style.x2 = geom[2] * w;
                style.y2 = geom[3] * h;
            } else if (gradientKind == static_cast<jint>(GradKind::Radial) && geomLen >= 6) {
                style.gradKind = GradKind::Radial;
                style.cx = geom[0] * w;
                style.cy = geom[1] * h;
                style.radius = std::max(0.f, geom[2]) * viewEdge;
                style.fx = geom[3] * w;
                style.fy = geom[4] * h;
                style.fr = std::max(0.f, geom[5]) * viewEdge;
            }
        }
    }

    if (style.gradKind == GradKind::None && argb != 0) {
        style.hasColor = true;
        style.a = static_cast<uint8_t>((argb >> 24) & 0xff);
        style.r = static_cast<uint8_t>((argb >> 16) & 0xff);
        style.g = static_cast<uint8_t>((argb >> 8) & 0xff);
        style.b = static_cast<uint8_t>(argb & 0xff);
    }

    if (strokeWidth >= 0.f) {
        style.hasStroke = true;
        if (absoluteStroke) {
            const float edge = std::max(1.f, designSize);
            style.strokeWidth = strokeWidth * (viewEdge / edge);
        } else {
            const float ref = std::max(1.f, referenceSize);
            style.strokeWidth = strokeWidth * (viewEdge / ref);
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
        return nullptr;
    }

    const int pixelCount = widthPx * heightPx;
    std::vector<uint32_t> buffer(static_cast<size_t>(pixelCount), 0);

    if (tvg_swcanvas_set_target(
            canvas,
            buffer.data(),
            static_cast<uint32_t>(widthPx),
            static_cast<uint32_t>(widthPx),
            static_cast<uint32_t>(heightPx),
            TVG_COLORSPACE_ARGB8888
        ) != TVG_RESULT_SUCCESS) {
        tvg_canvas_destroy(canvas);
        releasePicture();
        return nullptr;
    }

    if (tvg_canvas_add(canvas, picture) != TVG_RESULT_SUCCESS) {
        tvg_canvas_destroy(canvas);
        releasePicture();
        return nullptr;
    }
    pictureOwnedByCanvas = true;

    if (tvg_canvas_update(canvas) != TVG_RESULT_SUCCESS ||
        tvg_canvas_draw(canvas, true) != TVG_RESULT_SUCCESS ||
        tvg_canvas_sync(canvas) != TVG_RESULT_SUCCESS) {
        tvg_canvas_destroy(canvas);
        return nullptr;
    }

    tvg_canvas_destroy(canvas);

    jintArray out = env->NewIntArray(pixelCount);
    if (out == nullptr) {
        return nullptr;
    }
    env->SetIntArrayRegion(out, 0, pixelCount, reinterpret_cast<const jint *>(buffer.data()));
    return out;
}

}  // extern "C"
