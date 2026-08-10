#include <jni.h>

#include <algorithm>
#include <cstdint>
#include <mutex>
#include <vector>

#include "thorvg_capi.h"

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

// Same as Apple Ruyi: lazy init on first render; never expose term to callers.
void ensureEngine() {
    static std::once_flag once;
    std::call_once(once, [] { (void)tvg_engine_init(0); });
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
 * strokeWidth < 0: keep SVG strokes.
 * absoluteStroke != 0: strokeWidth is on-screen points (Ruyi absoluteStrokeWidth).
 * absoluteStroke == 0: strokeWidth is design stroke at referenceSize (Ruyi relative).
 * designSize: logical size (points) of the shorter edge — used for absolute conversion.
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
    jfloat referenceSize
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

    if (tvg_picture_set_size(picture, static_cast<float>(widthPx), static_cast<float>(heightPx)) != TVG_RESULT_SUCCESS) {
        releasePicture();
        return nullptr;
    }

    StyleCtx style;
    if (argb != 0) {
        style.hasColor = true;
        style.a = static_cast<uint8_t>((argb >> 24) & 0xff);
        style.r = static_cast<uint8_t>((argb >> 16) & 0xff);
        style.g = static_cast<uint8_t>((argb >> 8) & 0xff);
        style.b = static_cast<uint8_t>(argb & 0xff);
    }
    if (strokeWidth >= 0.f) {
        style.hasStroke = true;
        // Convert into SVG user units; picture resize scales strokes to pixels.
        if (absoluteStroke) {
            const float edge = std::max(1.f, designSize);
            style.strokeWidth = strokeWidth * (viewEdge / edge);
        } else {
            const float ref = std::max(1.f, referenceSize);
            style.strokeWidth = strokeWidth * (viewEdge / ref);
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
