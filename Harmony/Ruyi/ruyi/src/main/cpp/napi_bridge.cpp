#include <napi/native_api.h>

#include <algorithm>
#include <cstdint>
#include <cstring>
#include <cmath>
#include <limits>
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
    std::vector<std::vector<uint8_t>> rgbaResults; // Premul RGBA8888 per icon; empty = fail
    std::vector<std::vector<uint8_t>> masks; // Premul RGBA8888 masks from ArkTS renderSvgRgba.
    bool ok = true;
};

struct ResolvedStop {
    double offset = 0.0;
    uint8_t a = 255;
    uint8_t r = 0;
    uint8_t g = 0;
    uint8_t b = 0;
};

struct GradientSample {
    double a = 0.0;
    double r = 0.0;
    double g = 0.0;
    double b = 0.0;
};

uint32_t ReadArkTsPackedColor(const void *data, size_t index) {
    auto *bytes = static_cast<const uint8_t *>(data) + index * sizeof(uint32_t);
    return static_cast<uint32_t>(bytes[0]) |
           (static_cast<uint32_t>(bytes[1]) << 8) |
           (static_cast<uint32_t>(bytes[2]) << 16) |
           (static_cast<uint32_t>(bytes[3]) << 24);
}

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

bool ParseArrayBufferBytes(napi_env env, napi_value value, std::vector<uint8_t> &out) {
    bool isArrayBuffer = false;
    napi_is_arraybuffer(env, value, &isArrayBuffer);
    if (!isArrayBuffer) {
        out.clear();
        return false;
    }
    void *data = nullptr;
    size_t len = 0;
    napi_get_arraybuffer_info(env, value, &data, &len);
    if (data == nullptr || len == 0) {
        out.clear();
        return false;
    }
    auto *bytes = static_cast<uint8_t *>(data);
    out.assign(bytes, bytes + len);
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
                bool isColorArray = false;
                napi_is_array(env, args[base + 9], &isColorArray);
                if (isColorArray) {
                    uint32_t cLen = 0;
                    napi_get_array_length(env, args[base + 9], &cLen);
                    const size_t n = std::min(length, static_cast<size_t>(cLen));
                    out.stops.clear();
                    out.stops.reserve(n);
                    for (size_t i = 0; i < n; ++i) {
                        napi_value colorValue = nullptr;
                        napi_get_element(env, args[base + 9], static_cast<uint32_t>(i), &colorValue);
                        int32_t color = 0;
                        napi_get_value_int32(env, colorValue, &color);
                        thorvg_render::ColorStop stop;
                        stop.offset = offsets[i];
                        const uint32_t argb = static_cast<uint32_t>(color);
                        stop.a = static_cast<uint8_t>((argb >> 24) & 0xff);
                        stop.r = static_cast<uint8_t>((argb >> 16) & 0xff);
                        stop.g = static_cast<uint8_t>((argb >> 8) & 0xff);
                        stop.b = static_cast<uint8_t>(argb & 0xff);
                        out.stops.push_back(stop);
                    }
                } else {
                    bool isColors = false;
                    napi_is_typedarray(env, args[base + 9], &isColors);
                    if (!isColors) {
                        return true;
                    }
                    napi_typedarray_type cType = napi_int32_array;
                    size_t cLen = 0;
                    void *cData = nullptr;
                    napi_value cBuf = nullptr;
                    size_t cOff = 0;
                    napi_get_typedarray_info(env, args[base + 9], &cType, &cLen, &cData, &cBuf, &cOff);
                    if ((cType == napi_int32_array || cType == napi_uint32_array) && cData != nullptr) {
                        const size_t n = std::min(length, cLen);
                        out.stops.clear();
                        out.stops.reserve(n);
                        for (size_t i = 0; i < n; ++i) {
                            thorvg_render::ColorStop stop;
                            stop.offset = offsets[i];
                            const uint32_t argb = ReadArkTsPackedColor(cData, i);
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

double Clamp01(double value) {
    if (std::isnan(value)) {
        return value;
    }
    return std::min(1.0, std::max(0.0, value));
}

uint8_t RoundByte(double value) {
    if (!std::isfinite(value)) {
        return 0;
    }
    return static_cast<uint8_t>(std::min(255.0, std::max(0.0, std::floor(value + 0.5))));
}

double JsMax(double a, double b) {
    if (std::isnan(a) || std::isnan(b)) {
        return std::numeric_limits<double>::quiet_NaN();
    }
    return std::max(a, b);
}

double LinearParameter(double px, double py, int32_t widthPx, int32_t heightPx, const RenderArgs &args) {
    if (args.geomCount < 4) {
        return 0.0;
    }
    const double x1 = static_cast<double>(args.geom[0]) * widthPx;
    const double y1 = static_cast<double>(args.geom[1]) * heightPx;
    const double x2 = static_cast<double>(args.geom[2]) * widthPx;
    const double y2 = static_cast<double>(args.geom[3]) * heightPx;
    const double dx = x2 - x1;
    const double dy = y2 - y1;
    const double len2 = dx * dx + dy * dy;
    if (len2 <= 0.000001) {
        return 1.0;
    }
    return ((px - x1) * dx + (py - y1) * dy) / len2;
}

double RadialParameter(double px, double py, int32_t widthPx, int32_t heightPx, const RenderArgs &args) {
    if (args.geomCount < 6) {
        return 0.0;
    }
    const int32_t edge = std::max(1, std::min(widthPx, heightPx));
    const double cx = static_cast<double>(args.geom[0]) * widthPx;
    const double cy = static_cast<double>(args.geom[1]) * heightPx;
    const double radius = JsMax(0.0, static_cast<double>(args.geom[2])) * edge;
    const double fx = static_cast<double>(args.geom[3]) * widthPx;
    const double fy = static_cast<double>(args.geom[4]) * heightPx;
    const double focalRadius = JsMax(0.0, static_cast<double>(args.geom[5])) * edge;
    const double dr = radius - focalRadius;
    if (std::abs(dr) <= 0.000001 && std::abs(cx - fx) <= 0.000001 && std::abs(cy - fy) <= 0.000001) {
        const double pxToCenter = px - cx;
        const double pyToCenter = py - cy;
        return radius <= 0.000001 ? 1.0 : std::sqrt(pxToCenter * pxToCenter + pyToCenter * pyToCenter) / radius;
    }

    const double dx = cx - fx;
    const double dy = cy - fy;
    const double qx = fx - px;
    const double qy = fy - py;
    const double a = dx * dx + dy * dy - dr * dr;
    const double b = 2.0 * (qx * dx + qy * dy - focalRadius * dr);
    const double c = qx * qx + qy * qy - focalRadius * focalRadius;
    if (std::abs(a) <= 0.000001) {
        if (std::abs(b) <= 0.000001) {
            return 0.0;
        }
        return -c / b;
    }

    const double disc = b * b - 4.0 * a * c;
    if (disc < 0.0) {
        return 0.0;
    }
    const double root = std::sqrt(disc);
    const double t0 = (-b - root) / (2.0 * a);
    const double t1 = (-b + root) / (2.0 * a);
    if (t0 >= 0.0 && t1 >= 0.0) {
        return std::min(t0, t1);
    }
    if (t0 >= 0.0) {
        return t0;
    }
    return t1;
}

std::vector<ResolvedStop> ResolveStops(const RenderArgs &args) {
    std::vector<ResolvedStop> stops;
    stops.reserve(args.stops.size());
    for (const auto &stop : args.stops) {
        ResolvedStop resolved;
        resolved.offset = Clamp01(stop.offset);
        resolved.a = stop.a;
        resolved.r = stop.r;
        resolved.g = stop.g;
        resolved.b = stop.b;
        stops.push_back(resolved);
    }
    std::stable_sort(stops.begin(), stops.end(), [](const ResolvedStop &a, const ResolvedStop &b) {
        return a.offset < b.offset;
    });
    return stops;
}

GradientSample SampleGradient(const std::vector<ResolvedStop> &stops, double t) {
    const double clamped = Clamp01(t);
    const ResolvedStop *left = &stops.front();
    const ResolvedStop *right = &stops.back();
    if (clamped <= left->offset) {
        right = left;
    } else if (clamped >= right->offset) {
        left = right;
    } else {
        for (size_t i = 1; i < stops.size(); ++i) {
            if (clamped <= stops[i].offset) {
                left = &stops[i - 1];
                right = &stops[i];
                break;
            }
        }
    }

    const double span = right->offset - left->offset;
    const double local = std::abs(span) <= 0.000001 ? 0.0 : (clamped - left->offset) / span;
    GradientSample sample;
    sample.a = left->a + (right->a - left->a) * local;
    sample.r = left->r + (right->r - left->r) * local;
    sample.g = left->g + (right->g - left->g) * local;
    sample.b = left->b + (right->b - left->b) * local;
    return sample;
}

void WritePremulSampleColor(
    std::vector<uint8_t> &out,
    size_t offset,
    const GradientSample &sample,
    uint8_t maskAlpha
) {
    const uint8_t alpha = RoundByte(sample.a * maskAlpha / 255.0);
    out[offset + 3] = alpha;
    if (alpha == 0) {
        return;
    }
    out[offset] = RoundByte(sample.r * alpha / 255.0);
    out[offset + 1] = RoundByte(sample.g * alpha / 255.0);
    out[offset + 2] = RoundByte(sample.b * alpha / 255.0);
}

std::vector<GradientSample> BuildGradientSamples(
    const RenderArgs &args,
    const std::vector<ResolvedStop> &stops
) {
    const size_t pixelCount = static_cast<size_t>(args.widthPx) * static_cast<size_t>(args.heightPx);
    if (pixelCount == 0 || stops.size() < 2) {
        return {};
    }

    std::vector<GradientSample> samples(pixelCount);
    for (int32_t y = 0; y < args.heightPx; ++y) {
        const double py = y + 0.5;
        const size_t row = static_cast<size_t>(y) * static_cast<size_t>(args.widthPx);
        for (int32_t x = 0; x < args.widthPx; ++x) {
            const size_t pixelIndex = row + static_cast<size_t>(x);
            const double px = x + 0.5;
            const double t = args.gradientKind == 2
                ? RadialParameter(px, py, args.widthPx, args.heightPx, args)
                : LinearParameter(px, py, args.widthPx, args.heightPx, args);
            samples[pixelIndex] = SampleGradient(stops, t);
        }
    }
    return samples;
}

std::vector<uint8_t> ComposeGradientMaskRgba(const std::vector<uint8_t> &mask, const RenderArgs &args) {
    if ((args.gradientKind != 1 && args.gradientKind != 2) ||
        args.stops.size() < 2 ||
        args.widthPx <= 0 ||
        args.heightPx <= 0) {
        return {};
    }

    const size_t pixelCount = static_cast<size_t>(args.widthPx) * static_cast<size_t>(args.heightPx);
    if (pixelCount > (SIZE_MAX / 4) || mask.size() < pixelCount * 4) {
        return {};
    }

    const std::vector<ResolvedStop> stops = ResolveStops(args);
    if (stops.size() < 2) {
        return {};
    }
    const std::vector<GradientSample> samples = BuildGradientSamples(args, stops);
    if (samples.size() < pixelCount) {
        return {};
    }

    std::vector<uint8_t> out(pixelCount * 4, 0);
    for (int32_t y = 0; y < args.heightPx; ++y) {
        const size_t row = static_cast<size_t>(y) * static_cast<size_t>(args.widthPx);
        for (int32_t x = 0; x < args.widthPx; ++x) {
            const size_t pixelIndex = row + static_cast<size_t>(x);
            const size_t offset = pixelIndex * 4;
            const uint8_t maskAlpha = mask[offset + 3];
            if (maskAlpha == 0) {
                continue;
            }
            WritePremulSampleColor(out, offset, samples[pixelIndex], maskAlpha);
        }
    }
    return out;
}

std::vector<uint8_t> ComposeGradientMaskPixels(
    const std::vector<uint32_t> &mask,
    const RenderArgs &args,
    const std::vector<GradientSample> &samples
) {
    if ((args.gradientKind != 1 && args.gradientKind != 2) ||
        args.stops.size() < 2 ||
        args.widthPx <= 0 ||
        args.heightPx <= 0) {
        return {};
    }

    const size_t pixelCount = static_cast<size_t>(args.widthPx) * static_cast<size_t>(args.heightPx);
    if (pixelCount > (SIZE_MAX / 4) || mask.size() < pixelCount || samples.size() < pixelCount) {
        return {};
    }

    std::vector<uint8_t> out(pixelCount * 4, 0);
    for (int32_t y = 0; y < args.heightPx; ++y) {
        const size_t row = static_cast<size_t>(y) * static_cast<size_t>(args.widthPx);
        for (int32_t x = 0; x < args.widthPx; ++x) {
            const size_t pixelIndex = row + static_cast<size_t>(x);
            const uint8_t maskAlpha = static_cast<uint8_t>((mask[pixelIndex] >> 24) & 0xff);
            if (maskAlpha == 0) {
                continue;
            }
            const size_t offset = pixelIndex * 4;
            WritePremulSampleColor(out, offset, samples[pixelIndex], maskAlpha);
        }
    }
    return out;
}

std::vector<uint8_t> ComposeGradientMaskPixels(const std::vector<uint32_t> &mask, const RenderArgs &args) {
    const size_t pixelCount = static_cast<size_t>(args.widthPx) * static_cast<size_t>(args.heightPx);
    if (pixelCount > (SIZE_MAX / 4) || mask.size() < pixelCount) {
        return {};
    }

    const std::vector<ResolvedStop> stops = ResolveStops(args);
    if (stops.size() < 2) {
        return {};
    }
    return ComposeGradientMaskPixels(mask, args, BuildGradientSamples(args, stops));
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

void FinalizeExternalVector(napi_env, void *, void *hint) {
    delete static_cast<std::vector<uint8_t> *>(hint);
}

napi_value BufferFromRgba(napi_env env, std::vector<uint8_t> &&rgba) {
    if (rgba.empty()) {
        napi_value nullVal;
        napi_get_null(env, &nullVal);
        return nullVal;
    }

    auto *owned = new std::vector<uint8_t>(std::move(rgba));
    napi_value buffer;
    const napi_status status = napi_create_external_arraybuffer(
        env,
        owned->data(),
        owned->size(),
        FinalizeExternalVector,
        owned,
        &buffer
    );
    if (status != napi_ok) {
        delete owned;
        napi_value nullVal;
        napi_get_null(env, &nullVal);
        return nullVal;
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

void ExecuteComposeGradientMasks(napi_env, void *data) {
    auto *ctx = static_cast<AsyncCtx *>(data);
    ctx->rgbaResults.clear();
    ctx->rgbaResults.reserve(ctx->masks.size());
    for (const auto &mask : ctx->masks) {
        ctx->rgbaResults.push_back(ComposeGradientMaskRgba(mask, ctx->args));
    }
}

void ExecuteRenderMaskGradient(napi_env, void *data) {
    auto *ctx = static_cast<AsyncCtx *>(data);
    const std::vector<ResolvedStop> stops = ResolveStops(ctx->args);
    const std::vector<GradientSample> samples = BuildGradientSamples(ctx->args, stops);

    RenderArgs maskArgs;
    maskArgs.widthPx = ctx->args.widthPx;
    maskArgs.heightPx = ctx->args.heightPx;
    maskArgs.argb = ctx->args.argb;
    maskArgs.strokeWidth = ctx->args.strokeWidth;
    maskArgs.absoluteStroke = ctx->args.absoluteStroke;
    maskArgs.designSize = ctx->args.designSize;
    maskArgs.referenceSize = ctx->args.referenceSize;

    ctx->rgbaResults.clear();
    ctx->rgbaResults.reserve(ctx->args.svgs.size());
    for (const auto &svg : ctx->args.svgs) {
        const std::vector<uint32_t> mask = RenderOne(maskArgs, svg);
        ctx->rgbaResults.push_back(ComposeGradientMaskPixels(mask, ctx->args, samples));
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

void CompleteSingleRgba(napi_env env, napi_status status, void *data) {
    auto *ctx = static_cast<AsyncCtx *>(data);
    if (status != napi_ok || !ctx->ok || ctx->rgbaResults.empty()) {
        napi_value nullVal;
        napi_get_null(env, &nullVal);
        napi_resolve_deferred(env, ctx->deferred, nullVal);
    } else {
        napi_resolve_deferred(env, ctx->deferred, BufferFromRgba(env, std::move(ctx->rgbaResults[0])));
    }
    napi_delete_async_work(env, ctx->work);
    delete ctx;
}

void CompleteBatchRgba(napi_env env, napi_status status, void *data) {
    auto *ctx = static_cast<AsyncCtx *>(data);
    napi_value arr;
    napi_create_array_with_length(env, ctx->rgbaResults.size(), &arr);
    if (status == napi_ok && ctx->ok) {
        for (size_t i = 0; i < ctx->rgbaResults.size(); ++i) {
            napi_set_element(env, arr, i, BufferFromRgba(env, std::move(ctx->rgbaResults[i])));
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

/**
 * composeGradientMask(maskRgba, widthPx, heightPx, ..., gradient) → Promise<ArrayBuffer|null>
 * This is a direct native translation of Ruyi.gradientRgbaFromMask(): ArkTS
 * still supplies the exact same RGBA mask bytes from renderSvgRgba().
 */
napi_value ComposeGradientMask(napi_env env, napi_callback_info info) {
    size_t argc = 12;
    napi_value args[12] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    napi_value promise = nullptr;
    napi_deferred deferred = nullptr;
    napi_create_promise(env, &deferred, &promise);

    auto *ctx = new AsyncCtx();
    ctx->env = env;
    ctx->deferred = deferred;

    std::vector<uint8_t> mask;
    if (argc < 12 || !ParseArrayBufferBytes(env, args[0], mask) ||
        !ParseCommonArgs(env, args, argc, 1, ctx->args) ||
        (ctx->args.gradientKind != 1 && ctx->args.gradientKind != 2) ||
        ctx->args.stops.size() < 2) {
        napi_value nullVal;
        napi_get_null(env, &nullVal);
        napi_resolve_deferred(env, deferred, nullVal);
        delete ctx;
        return promise;
    }
    ctx->masks.push_back(std::move(mask));

    napi_value resourceName;
    napi_create_string_utf8(env, "Ruyi.composeGradientMask", NAPI_AUTO_LENGTH, &resourceName);
    napi_create_async_work(env, nullptr, resourceName, ExecuteComposeGradientMasks, CompleteSingleRgba, ctx, &ctx->work);
    napi_queue_async_work_with_qos(env, ctx->work, napi_qos_user_initiated);
    return promise;
}

/**
 * composeGradientMasks(maskRgba[], widthPx, heightPx, ..., gradient) → Promise<ArrayBuffer|null[]>
 */
napi_value ComposeGradientMasks(napi_env env, napi_callback_info info) {
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
    if (!isArray || argc < 12 || !ParseCommonArgs(env, args, argc, 1, ctx->args) ||
        (ctx->args.gradientKind != 1 && ctx->args.gradientKind != 2) ||
        ctx->args.stops.size() < 2) {
        napi_value arr;
        napi_create_array_with_length(env, 0, &arr);
        napi_resolve_deferred(env, deferred, arr);
        delete ctx;
        return promise;
    }

    uint32_t len = 0;
    napi_get_array_length(env, args[0], &len);
    ctx->masks.reserve(len);
    for (uint32_t i = 0; i < len; ++i) {
        napi_value item;
        napi_get_element(env, args[0], i, &item);
        std::vector<uint8_t> mask;
        (void)ParseArrayBufferBytes(env, item, mask);
        ctx->masks.push_back(std::move(mask));
    }

    napi_value resourceName;
    napi_create_string_utf8(env, "Ruyi.composeGradientMasks", NAPI_AUTO_LENGTH, &resourceName);
    napi_create_async_work(env, nullptr, resourceName, ExecuteComposeGradientMasks, CompleteBatchRgba, ctx, &ctx->work);
    napi_queue_async_work_with_qos(env, ctx->work, napi_qos_user_initiated);
    return promise;
}

/**
 * renderSvgMaskGradient(svg, widthPx, heightPx, maskArgb, ..., gradient)
 * Strictly equivalent to ArkTS:
 *   renderSvgRgba(svg, maskArgb) -> composeGradientMask(maskRgba, gradient)
 * but both phases stay inside one native worker job.
 *
 * This is intentionally not the same implementation strategy as Android/iOS.
 * Those ports can pass gradients into ThorVG shape paints and return the final
 * image. Harmony previously needed a post-raster mask tint to match Ruyi's
 * icon-wide gradient semantics, and doing that in ArkTS made large icons pay for
 * both per-pixel JS work and large NAPI buffer round-trips. This worker preserves
 * the verified mask algorithm while keeping the hot pixel path in C++.
 */
napi_value RenderSvgMaskGradient(napi_env env, napi_callback_info info) {
    size_t argc = 12;
    napi_value args[12] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    napi_value promise = nullptr;
    napi_deferred deferred = nullptr;
    napi_create_promise(env, &deferred, &promise);

    auto *ctx = new AsyncCtx();
    ctx->env = env;
    ctx->deferred = deferred;

    if (argc < 12 || !ParseSvgArg(env, args[0], ctx->args.svgs.emplace_back()) ||
        !ParseCommonArgs(env, args, argc, 1, ctx->args) ||
        (ctx->args.gradientKind != 1 && ctx->args.gradientKind != 2) ||
        ctx->args.stops.size() < 2) {
        napi_value nullVal;
        napi_get_null(env, &nullVal);
        napi_resolve_deferred(env, deferred, nullVal);
        delete ctx;
        return promise;
    }

    napi_value resourceName;
    napi_create_string_utf8(env, "Ruyi.renderSvgMaskGradient", NAPI_AUTO_LENGTH, &resourceName);
    napi_create_async_work(env, nullptr, resourceName, ExecuteRenderMaskGradient, CompleteSingleRgba, ctx, &ctx->work);
    napi_queue_async_work_with_qos(env, ctx->work, napi_qos_user_initiated);
    return promise;
}

/**
 * Batch renderSvgMaskGradient — one native worker job for many SVGs.
 */
napi_value RenderSvgBatchMaskGradient(napi_env env, napi_callback_info info) {
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
    if (!isArray || argc < 12 || !ParseCommonArgs(env, args, argc, 1, ctx->args) ||
        (ctx->args.gradientKind != 1 && ctx->args.gradientKind != 2) ||
        ctx->args.stops.size() < 2) {
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
    napi_create_string_utf8(env, "Ruyi.renderSvgBatchMaskGradient", NAPI_AUTO_LENGTH, &resourceName);
    napi_create_async_work(env, nullptr, resourceName, ExecuteRenderMaskGradient, CompleteBatchRgba, ctx, &ctx->work);
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
        {"composeGradientMask", nullptr, ComposeGradientMask, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"composeGradientMasks", nullptr, ComposeGradientMasks, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"renderSvgMaskGradient", nullptr, RenderSvgMaskGradient, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"renderSvgBatchMaskGradient", nullptr, RenderSvgBatchMaskGradient, nullptr, nullptr, nullptr, napi_default, nullptr},
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
