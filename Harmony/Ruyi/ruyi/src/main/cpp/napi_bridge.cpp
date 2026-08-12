#include <napi/native_api.h>

#include <algorithm>
#include <cstdint>
#include <cstring>
#include <string>
#include <vector>

#include "render_core.h"

namespace {

struct RenderArgs {
    std::vector<std::string> svgs;
    int32_t widthPx = 0;
    int32_t heightPx = 0;
    int32_t argb = 0;
    float strokeWidth = -1.f;
    bool absoluteStroke = false;
    float designSize = 0.f;
    float referenceSize = 24.f;
    int32_t gradientKind = 0; // 0 none, 1 linear, 2 radial
    std::vector<thorvg_render::ColorStop> stops;
    float geom[6] = {0, 0, 0, 0, 0, 0};
    int geomCount = 0;
};

struct AsyncCtx {
    napi_env env = nullptr;
    napi_async_work work = nullptr;
    napi_deferred deferred = nullptr;
    RenderArgs args;
    std::vector<std::vector<uint32_t>> results; // ARGB8888 per icon; empty = fail
    bool ok = true;
};

bool ParseSvgArg(napi_env env, napi_value value, std::string &out) {
    bool isArrayBuffer = false;
    napi_is_arraybuffer(env, value, &isArrayBuffer);
    if (isArrayBuffer) {
        void *data = nullptr;
        size_t len = 0;
        napi_get_arraybuffer_info(env, value, &data, &len);
        if (data == nullptr || len == 0) {
            return false;
        }
        out.assign(static_cast<char *>(data), static_cast<char *>(data) + len);
        return true;
    }
    size_t len = 0;
    napi_get_value_string_utf8(env, value, nullptr, 0, &len);
    if (len == 0) {
        out.clear();
        return true;
    }
    out.resize(len + 1);
    napi_get_value_string_utf8(env, value, out.data(), out.size(), &len);
    out.resize(len);
    return true;
}

bool ParseCommonArgs(napi_env env, napi_value *args, size_t argc, size_t base, RenderArgs &out) {
    if (argc < base + 2) {
        return false;
    }
    napi_get_value_int32(env, args[base], &out.widthPx);
    napi_get_value_int32(env, args[base + 1], &out.heightPx);
    if (argc >= base + 3) napi_get_value_int32(env, args[base + 2], &out.argb);
    if (argc >= base + 4) {
        double stroke = -1.0;
        napi_get_value_double(env, args[base + 3], &stroke);
        out.strokeWidth = static_cast<float>(stroke);
    }
    if (argc >= base + 5) napi_get_value_bool(env, args[base + 4], &out.absoluteStroke);
    if (argc >= base + 6) {
        double design = 0.0;
        napi_get_value_double(env, args[base + 5], &design);
        out.designSize = static_cast<float>(design);
    }
    if (argc >= base + 7) {
        double ref = 24.0;
        napi_get_value_double(env, args[base + 6], &ref);
        out.referenceSize = static_cast<float>(ref);
    }
    // Optional gradient: kind, Float32Array offsets, Int32Array colors, Float32Array geom.
    if (argc >= base + 8) {
        napi_get_value_int32(env, args[base + 7], &out.gradientKind);
    }
    if (argc >= base + 11 && out.gradientKind != 0) {
        bool isTyped = false;
        napi_is_typedarray(env, args[base + 8], &isTyped);
        if (isTyped) {
            napi_typedarray_type type = napi_float32_array;
            size_t length = 0;
            void *data = nullptr;
            napi_value arrayBuffer = nullptr;
            size_t byteOffset = 0;
            napi_get_typedarray_info(env, args[base + 8], &type, &length, &data, &arrayBuffer, &byteOffset);
            if (type == napi_float32_array && data != nullptr && length > 0) {
                auto *offsets = static_cast<float *>(data);
                bool isColors = false;
                napi_is_typedarray(env, args[base + 9], &isColors);
                if (isColors) {
                    napi_typedarray_type cType = napi_int32_array;
                    size_t cLen = 0;
                    void *cData = nullptr;
                    napi_value cBuf = nullptr;
                    size_t cOff = 0;
                    napi_get_typedarray_info(env, args[base + 9], &cType, &cLen, &cData, &cBuf, &cOff);
                    if ((cType == napi_int32_array || cType == napi_uint32_array) && cData != nullptr) {
                        // Must read as unsigned: 0xAARRGGBB with AA>=0x80 is negative as int32,
                        // and arithmetic >> corrupts R/G channels (hard two-tone gradients).
                        auto *colors = static_cast<const uint32_t *>(cData);
                        const size_t n = std::min(length, cLen);
                        out.stops.clear();
                        out.stops.reserve(n);
                        for (size_t i = 0; i < n; ++i) {
                            thorvg_render::ColorStop stop;
                            stop.offset = offsets[i];
                            const uint32_t argb = colors[i];
                            stop.a = static_cast<uint8_t>((argb >> 24) & 0xff);
                            stop.r = static_cast<uint8_t>((argb >> 16) & 0xff);
                            stop.g = static_cast<uint8_t>((argb >> 8) & 0xff);
                            stop.b = static_cast<uint8_t>(argb & 0xff);
                            out.stops.push_back(stop);
                        }
                    }
                }
            }
        }
        bool isGeom = false;
        napi_is_typedarray(env, args[base + 10], &isGeom);
        if (isGeom) {
            napi_typedarray_type gType = napi_float32_array;
            size_t gLen = 0;
            void *gData = nullptr;
            napi_value gBuf = nullptr;
            size_t gOff = 0;
            napi_get_typedarray_info(env, args[base + 10], &gType, &gLen, &gData, &gBuf, &gOff);
            if (gType == napi_float32_array && gData != nullptr) {
                auto *geom = static_cast<float *>(gData);
                out.geomCount = static_cast<int>(std::min(gLen, size_t{6}));
                for (int i = 0; i < out.geomCount; ++i) {
                    out.geom[i] = geom[i];
                }
            }
        }
    }
    if (out.designSize <= 0.f) {
        out.designSize = static_cast<float>(std::min(out.widthPx, out.heightPx));
    }
    return out.widthPx > 0 && out.heightPx > 0;
}

std::vector<uint32_t> RenderOne(const RenderArgs &args, const std::string &svg) {
    thorvg_render::RenderRequest req;
    req.svgData = svg.data();
    req.svgLength = static_cast<uint32_t>(svg.size());
    req.widthPx = args.widthPx;
    req.heightPx = args.heightPx;
    req.argb = args.argb;
    req.strokeWidth = args.strokeWidth;
    req.absoluteStroke = args.absoluteStroke;
    req.designSize = args.designSize;
    req.referenceSize = args.referenceSize;
    req.gradKind = static_cast<thorvg_render::GradKind>(args.gradientKind);
    req.stops = args.stops;
    req.geomCount = args.geomCount;
    for (int i = 0; i < 6; ++i) {
        req.geom[i] = args.geom[i];
    }
    return thorvg_render::renderSvg(req);
}

napi_value BufferFromPixels(napi_env env, const std::vector<uint32_t> &pixels) {
    if (pixels.empty()) {
        napi_value nullVal;
        napi_get_null(env, &nullVal);
        return nullVal;
    }
    void *outData = nullptr;
    napi_value buffer;
    const size_t byteLen = pixels.size() * sizeof(uint32_t);
    napi_create_arraybuffer(env, byteLen, &outData, &buffer);
    if (outData == nullptr) {
        napi_value nullVal;
        napi_get_null(env, &nullVal);
        return nullVal;
    }
    // ThorVG: premul 0xAARRGGBB words → premul RGBA bytes for RGBA_8888+PREMUL.
    auto *dst = static_cast<uint8_t *>(outData);
    for (size_t i = 0; i < pixels.size(); ++i) {
        const uint32_t argb = pixels[i];
        const size_t o = i * 4;
        dst[o + 0] = static_cast<uint8_t>((argb >> 16) & 0xff); // R
        dst[o + 1] = static_cast<uint8_t>((argb >> 8) & 0xff);  // G
        dst[o + 2] = static_cast<uint8_t>(argb & 0xff);         // B
        dst[o + 3] = static_cast<uint8_t>((argb >> 24) & 0xff); // A
    }
    return buffer;
}

void ExecuteRender(napi_env, void *data) {
    auto *ctx = static_cast<AsyncCtx *>(data);
    ctx->results.clear();
    ctx->results.reserve(ctx->args.svgs.size());
    for (const auto &svg : ctx->args.svgs) {
        ctx->results.push_back(RenderOne(ctx->args, svg));
    }
}

void CompleteSingle(napi_env env, napi_status status, void *data) {
    auto *ctx = static_cast<AsyncCtx *>(data);
    if (status != napi_ok || !ctx->ok || ctx->results.empty()) {
        napi_value nullVal;
        napi_get_null(env, &nullVal);
        napi_resolve_deferred(env, ctx->deferred, nullVal);
    } else {
        napi_resolve_deferred(env, ctx->deferred, BufferFromPixels(env, ctx->results[0]));
    }
    napi_delete_async_work(env, ctx->work);
    delete ctx;
}

void CompleteBatch(napi_env env, napi_status status, void *data) {
    auto *ctx = static_cast<AsyncCtx *>(data);
    napi_value arr;
    napi_create_array_with_length(env, ctx->results.size(), &arr);
    if (status == napi_ok && ctx->ok) {
        for (size_t i = 0; i < ctx->results.size(); ++i) {
            napi_set_element(env, arr, i, BufferFromPixels(env, ctx->results[i]));
        }
    }
    napi_resolve_deferred(env, ctx->deferred, arr);
    napi_delete_async_work(env, ctx->work);
    delete ctx;
}

napi_value EngineInit(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    int32_t threads = 0;
    if (argc >= 1) {
        napi_get_value_int32(env, args[0], &threads);
    }
    int rc = thorvg_render::engineInit(static_cast<unsigned>(threads < 0 ? 0 : threads));
    napi_value result;
    napi_create_int32(env, rc, &result);
    return result;
}

napi_value EngineTerm(napi_env env, napi_callback_info) {
    int rc = thorvg_render::engineTerm();
    napi_value result;
    napi_create_int32(env, rc, &result);
    return result;
}

napi_value Version(napi_env env, napi_callback_info) {
    const std::string ver = thorvg_render::version();
    napi_value result;
    napi_create_string_utf8(env, ver.c_str(), ver.size(), &result);
    return result;
}

/**
 * renderSvg(...) → Promise<ArrayBuffer|null>
 * Heavy work runs on libuv/worker thread so slider UI stays responsive.
 */
napi_value RenderSvg(napi_env env, napi_callback_info info) {
    size_t argc = 12;
    napi_value args[12] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    napi_value promise = nullptr;
    napi_deferred deferred = nullptr;
    napi_create_promise(env, &deferred, &promise);

    auto *ctx = new AsyncCtx();
    ctx->env = env;
    ctx->deferred = deferred;

    if (argc < 3 || !ParseSvgArg(env, args[0], ctx->args.svgs.emplace_back()) ||
        !ParseCommonArgs(env, args, argc, 1, ctx->args)) {
        napi_value nullVal;
        napi_get_null(env, &nullVal);
        napi_resolve_deferred(env, deferred, nullVal);
        delete ctx;
        return promise;
    }

    napi_value resourceName;
    napi_create_string_utf8(env, "Ruyi.renderSvg", NAPI_AUTO_LENGTH, &resourceName);
    napi_create_async_work(env, nullptr, resourceName, ExecuteRender, CompleteSingle, ctx, &ctx->work);
    napi_queue_async_work_with_qos(env, ctx->work, napi_qos_user_initiated);
    return promise;
}

/**
 * renderSvgBatch(svgs: string[], widthPx, heightPx, ...) → Promise<ArrayBuffer|null[]>
 */
napi_value RenderSvgBatch(napi_env env, napi_callback_info info) {
    size_t argc = 12;
    napi_value args[12] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    napi_value promise = nullptr;
    napi_deferred deferred = nullptr;
    napi_create_promise(env, &deferred, &promise);

    auto *ctx = new AsyncCtx();
    ctx->env = env;
    ctx->deferred = deferred;

    bool isArray = false;
    napi_is_array(env, args[0], &isArray);
    if (!isArray || argc < 3 || !ParseCommonArgs(env, args, argc, 1, ctx->args)) {
        napi_value arr;
        napi_create_array_with_length(env, 0, &arr);
        napi_resolve_deferred(env, deferred, arr);
        delete ctx;
        return promise;
    }

    uint32_t len = 0;
    napi_get_array_length(env, args[0], &len);
    ctx->args.svgs.reserve(len);
    for (uint32_t i = 0; i < len; ++i) {
        napi_value item;
        napi_get_element(env, args[0], i, &item);
        std::string svg;
        if (ParseSvgArg(env, item, svg)) {
            ctx->args.svgs.push_back(std::move(svg));
        } else {
            ctx->args.svgs.emplace_back();
        }
    }

    napi_value resourceName;
    napi_create_string_utf8(env, "Ruyi.renderSvgBatch", NAPI_AUTO_LENGTH, &resourceName);
    napi_create_async_work(env, nullptr, resourceName, ExecuteRender, CompleteBatch, ctx, &ctx->work);
    napi_queue_async_work_with_qos(env, ctx->work, napi_qos_user_initiated);
    return promise;
}

napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        {"engineInit", nullptr, EngineInit, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"engineTerm", nullptr, EngineTerm, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"version", nullptr, Version, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"renderSvg", nullptr, RenderSvg, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"renderSvgBatch", nullptr, RenderSvgBatch, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}

}  // namespace

static napi_module g_module = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "ruyi",
    .nm_priv = nullptr,
    .reserved = {0},
};

extern "C" __attribute__((constructor)) void RegisterRuyiModule(void) {
    napi_module_register(&g_module);
}
