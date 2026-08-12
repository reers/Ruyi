package io.github.reers.ruyi

import android.graphics.Bitmap
import java.nio.charset.StandardCharsets

/**
 * Internal ThorVG bridge (JNI → Prefab `libthorvg.so` C API).
 *
 * Not part of the public Ruyi API surface — use [Ruyi] instead.
 */
internal object ThorVG {
    init {
        // Prefab shared lib from io.github.vnixx:thorvg, then this module's JNI.
        System.loadLibrary("thorvg")
        System.loadLibrary("ruyi")
    }

    fun version(): String = nativeVersion()

    fun renderSvg(
        svg: ByteArray,
        widthPx: Int,
        heightPx: Int,
        argb: Int = 0,
        strokeWidth: Float? = null,
        absoluteStrokeWidth: Boolean = false,
        designSize: Float = minOf(widthPx, heightPx).toFloat(),
        referenceSize: Float = 24f,
        gradientKind: Int = 0,
        stopOffsets: FloatArray? = null,
        stopColors: IntArray? = null,
        gradGeom: FloatArray? = null,
    ): Bitmap? {
        if (svg.isEmpty() || widthPx <= 0 || heightPx <= 0) return null
        val stroke = strokeWidth ?: -1f
        val pixels = nativeRenderSvg(
            svg,
            widthPx,
            heightPx,
            argb,
            stroke,
            absoluteStrokeWidth,
            designSize,
            referenceSize,
            gradientKind,
            stopOffsets,
            stopColors,
            gradGeom,
        ) ?: return null
        val bitmap = Bitmap.createBitmap(widthPx, heightPx, Bitmap.Config.ARGB_8888)
        bitmap.setHasAlpha(true)
        bitmap.setPixels(pixels, 0, widthPx, 0, 0, widthPx, heightPx)
        return bitmap
    }

    fun renderSvg(
        svg: String,
        widthPx: Int,
        heightPx: Int,
        argb: Int = 0,
        strokeWidth: Float? = null,
        absoluteStrokeWidth: Boolean = false,
        designSize: Float = minOf(widthPx, heightPx).toFloat(),
        referenceSize: Float = 24f,
        gradientKind: Int = 0,
        stopOffsets: FloatArray? = null,
        stopColors: IntArray? = null,
        gradGeom: FloatArray? = null,
    ): Bitmap? = renderSvg(
        svg.toByteArray(StandardCharsets.UTF_8),
        widthPx,
        heightPx,
        argb,
        strokeWidth,
        absoluteStrokeWidth,
        designSize,
        referenceSize,
        gradientKind,
        stopOffsets,
        stopColors,
        gradGeom,
    )

    private external fun nativeVersion(): String

    private external fun nativeRenderSvg(
        svgBytes: ByteArray,
        widthPx: Int,
        heightPx: Int,
        argb: Int,
        strokeWidth: Float,
        absoluteStroke: Boolean,
        designSize: Float,
        referenceSize: Float,
        gradientKind: Int,
        stopOffsets: FloatArray?,
        stopColors: IntArray?,
        gradGeom: FloatArray?,
    ): IntArray?
}
