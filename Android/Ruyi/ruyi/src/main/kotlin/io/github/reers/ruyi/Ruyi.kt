package io.github.reers.ruyi

import android.content.Context
import android.graphics.Bitmap
import java.nio.charset.StandardCharsets
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlin.math.sqrt

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

    /** A color stop along a gradient. [offset] is in `0…1`. [color] is `0xAARRGGBB`. */
    data class GradientStop(
        val offset: Float,
        val color: Int,
    )

    /**
     * Icon-wide gradient tint. Does not require gradient tags in the source SVG.
     *
     * Coordinates are normalized to the SVG viewBox (`0…1` on each axis, origin at top-left).
     * Radial radii are fractions of `min(viewWidth, viewHeight)`.
     */
    sealed class GradientTint {
        data class Linear(
            val stops: List<GradientStop>,
            val startX: Float,
            val startY: Float,
            val endX: Float,
            val endY: Float,
        ) : GradientTint()

        data class Radial(
            val stops: List<GradientStop>,
            val centerX: Float,
            val centerY: Float,
            val radius: Float,
            val focalX: Float = centerX,
            val focalY: Float = centerY,
            val focalRadius: Float = 0f,
        ) : GradientTint()

        enum class LinearDirection {
            TopToBottom,
            BottomToTop,
            LeftToRight,
            RightToLeft,
            TopLeftToBottomRight,
            BottomLeftToTopRight,
            ;

            fun unitEndpoints(): FloatArray = when (this) {
                TopToBottom -> floatArrayOf(0.5f, 0f, 0.5f, 1f)
                BottomToTop -> floatArrayOf(0.5f, 1f, 0.5f, 0f)
                LeftToRight -> floatArrayOf(0f, 0.5f, 1f, 0.5f)
                RightToLeft -> floatArrayOf(1f, 0.5f, 0f, 0.5f)
                TopLeftToBottomRight -> floatArrayOf(0f, 0f, 1f, 1f)
                BottomLeftToTopRight -> floatArrayOf(0f, 1f, 1f, 0f)
            }
        }

        companion object {
            /** Custom angle in degrees. `0` = left→right, `90` = top→bottom. */
            fun linearAngle(degrees: Float): FloatArray {
                val rad = degrees * PI / 180.0
                val dx = cos(rad).toFloat()
                val dy = sin(rad).toFloat()
                val extent = (0.5 * sqrt(2.0)).toFloat()
                return floatArrayOf(
                    0.5f - dx * extent,
                    0.5f - dy * extent,
                    0.5f + dx * extent,
                    0.5f + dy * extent,
                )
            }

            fun linear(
                stops: List<GradientStop>,
                direction: LinearDirection = LinearDirection.TopToBottom,
            ): Linear {
                val e = direction.unitEndpoints()
                return Linear(stops, e[0], e[1], e[2], e[3])
            }

            fun linear(
                from: Int,
                to: Int,
                direction: LinearDirection = LinearDirection.TopToBottom,
            ): Linear = linear(
                listOf(GradientStop(0f, from), GradientStop(1f, to)),
                direction,
            )

            fun linear(
                stops: List<GradientStop>,
                angleDegrees: Float,
            ): Linear {
                val e = linearAngle(angleDegrees)
                return Linear(stops, e[0], e[1], e[2], e[3])
            }

            fun radial(
                from: Int,
                to: Int,
                centerX: Float = 0.5f,
                centerY: Float = 0.5f,
                radius: Float = 0.7071f,
            ): Radial = Radial(
                stops = listOf(GradientStop(0f, from), GradientStop(1f, to)),
                centerX = centerX,
                centerY = centerY,
                radius = radius,
            )
        }
    }

    /**
     * Rendering options for SVG → bitmap conversion.
     *
     * Pixel size = [sizeDp] × [density] (rounded). Stroke semantics match Apple Ruyi:
     * - [absoluteStrokeWidth] = true: [strokeWidth] is constant in points regardless of size
     * - [absoluteStrokeWidth] = false: stroke scales with `sizeDp / referenceSize` (default)
     *
     * When [gradient] is set it takes precedence over [color].
     */
    data class Options(
        /** Output size in density-independent pixels (logical). */
        val sizeDp: Float,
        /** Optional solid tint as Android-packed `0xAARRGGBB`; `null` keeps SVG colors. */
        val color: Int? = null,
        /** Optional gradient tint; takes precedence over [color]. */
        val gradient: GradientTint? = null,
        /** Optional stroke width in points (see [absoluteStrokeWidth]). */
        val strokeWidth: Float? = null,
        /**
         * When `true`, [strokeWidth] is constant in points regardless of [sizeDp].
         * When `false`, stroke scales with `sizeDp / referenceSize` (Lucide-style). Default.
         */
        val absoluteStrokeWidth: Boolean = false,
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
        val packed = options.gradient?.pack()
        return ThorVG.renderSvg(
            svg = bytes,
            widthPx = sizePx,
            heightPx = sizePx,
            argb = if (packed != null) 0 else (options.color ?: 0),
            strokeWidth = options.strokeWidth,
            absoluteStrokeWidth = options.absoluteStrokeWidth,
            designSize = options.sizeDp,
            referenceSize = options.referenceSize,
            gradientKind = packed?.kind ?: 0,
            stopOffsets = packed?.offsets,
            stopColors = packed?.colors,
            gradGeom = packed?.geom,
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
        absoluteStrokeWidth: Boolean = false,
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

    private data class PackedGradient(
        val kind: Int,
        val offsets: FloatArray,
        val colors: IntArray,
        val geom: FloatArray,
    )

    private fun GradientTint.pack(): PackedGradient? {
        val stops = when (this) {
            is GradientTint.Linear -> stops
            is GradientTint.Radial -> stops
        }
        if (stops.size < 2) return null
        val offsets = FloatArray(stops.size) { i ->
            min(1f, max(0f, stops[i].offset))
        }
        val colors = IntArray(stops.size) { i -> stops[i].color }
        return when (this) {
            is GradientTint.Linear -> PackedGradient(
                kind = 1,
                offsets = offsets,
                colors = colors,
                geom = floatArrayOf(startX, startY, endX, endY),
            )
            is GradientTint.Radial -> PackedGradient(
                kind = 2,
                offsets = offsets,
                colors = colors,
                geom = floatArrayOf(centerX, centerY, radius, focalX, focalY, focalRadius),
            )
        }
    }

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
