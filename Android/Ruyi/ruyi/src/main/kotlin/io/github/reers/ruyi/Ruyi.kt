package io.github.reers.ruyi

import android.content.Context
import android.graphics.Bitmap
import java.nio.charset.StandardCharsets
import kotlin.math.roundToInt

/**
 * Cross-platform SVG load & render runtime (Android).
 *
 * Ships no built-in icons — pass your own SVG data / assets.
 * Kotlin API over ThorVG C API via an in-module JNI bridge
 * (`io.github.vnixx:thorvg` Prefab).
 */
object Ruyi {

    /** ThorVG engine version string. */
    @JvmStatic
    fun version(): String = ThorVG.version()

    /**
     * Rendering options for SVG → bitmap conversion.
     *
     * Pixel size = [sizeDp] × [density] (rounded). Stroke semantics match Apple Ruyi:
     * - [absoluteStrokeWidth] = true: [strokeWidth] is constant in points regardless of size
     * - [absoluteStrokeWidth] = false: stroke scales with `sizeDp / referenceSize`
     */
    data class Options(
        /** Output size in density-independent pixels (logical). */
        val sizeDp: Float,
        /** Optional solid tint as Android-packed `0xAARRGGBB`; `null` keeps SVG colors. */
        val color: Int? = null,
        /** Optional stroke width in points (see [absoluteStrokeWidth]). */
        val strokeWidth: Float? = null,
        /**
         * When `true`, [strokeWidth] is constant in points regardless of [sizeDp].
         * When `false`, stroke scales with `sizeDp / referenceSize` (Lucide-style).
         */
        val absoluteStrokeWidth: Boolean = true,
        /** Design-size baseline used when [absoluteStrokeWidth] is `false`. Default 24. */
        val referenceSize: Float = 24f,
        /** Screen density. Use `Resources.displayMetrics.density` for device pixels. */
        val density: Float = 1f,
    )

    @JvmStatic
    fun image(svg: String, options: Options): Bitmap? =
        image(svg.toByteArray(StandardCharsets.UTF_8), options)

    @JvmStatic
    fun image(bytes: ByteArray, options: Options): Bitmap? {
        if (bytes.isEmpty() || options.sizeDp <= 0f || options.density <= 0f) return null
        val sizePx = (options.sizeDp * options.density).roundToInt().coerceAtLeast(1)
        return ThorVG.renderSvg(
            svg = bytes,
            widthPx = sizePx,
            heightPx = sizePx,
            argb = options.color ?: 0,
            strokeWidth = options.strokeWidth,
            absoluteStrokeWidth = options.absoluteStrokeWidth,
            designSize = options.sizeDp,
            referenceSize = options.referenceSize,
        )
    }

    /**
     * Load an SVG from `assets/` by name.
     *
     * Tries [assetName] as-is, then `[assetName].svg`, then under `icons/`.
     */
    @JvmStatic
    fun image(context: Context, assetName: String, options: Options): Bitmap? {
        val data = readAssetBytes(context, assetName) ?: return null
        return image(data, options)
    }

    /** Convenience: square icon with density from [context]. */
    @JvmStatic
    @JvmOverloads
    fun image(
        context: Context,
        assetName: String,
        sizeDp: Float,
        color: Int? = null,
        strokeWidth: Float? = null,
        absoluteStrokeWidth: Boolean = true,
        referenceSize: Float = 24f,
    ): Bitmap? = image(
        context,
        assetName,
        Options(
            sizeDp = sizeDp,
            color = color,
            strokeWidth = strokeWidth,
            absoluteStrokeWidth = absoluteStrokeWidth,
            referenceSize = referenceSize,
            density = context.resources.displayMetrics.density,
        ),
    )

    private fun readAssetBytes(context: Context, assetName: String): ByteArray? {
        val candidates = buildList {
            add(assetName)
            if (!assetName.endsWith(".svg", ignoreCase = true)) {
                add("$assetName.svg")
            }
            val base = assetName.removePrefix("icons/")
            add("icons/$base")
            if (!base.endsWith(".svg", ignoreCase = true)) {
                add("icons/$base.svg")
            }
        }.distinct()

        for (path in candidates) {
            try {
                return context.assets.open(path).use { it.readBytes() }
            } catch (_: Exception) {
                // try next
            }
        }
        return null
    }
}
