import { image } from '@kit.ImageKit';
import { ThorVG } from './ThorVG';

const WHITE_ARGB: number = 0xFFFFFFFF;

export type RuyiSvgSource = string | ArrayBuffer;

/** A color stop along a gradient. offset is in 0…1. color is 0xAARRGGBB. */
export class GradientStop {
  offset: number;
  color: number;

  constructor(offset: number, color: number) {
    this.offset = offset;
    this.color = color;
  }
}

/**
 * Icon-wide gradient tint (normalized viewBox coords).
 * kind: 1=linear, 2=radial
 * geom: linear [sx,sy,ex,ey] or radial [cx,cy,r,fx,fy,fr]
 */
export class GradientTint {
  kind: number;
  stops: GradientStop[];
  geom: number[];

  constructor(kind: number, stops: GradientStop[], geom: number[]) {
    this.kind = kind;
    this.stops = stops;
    this.geom = geom;
  }

  static linear(stops: GradientStop[], startX: number, startY: number, endX: number, endY: number): GradientTint {
    return new GradientTint(1, stops, [startX, startY, endX, endY]);
  }

  static linearAngle(stops: GradientStop[], degrees: number): GradientTint {
    const rad = degrees * Math.PI / 180;
    const dx = Math.cos(rad);
    const dy = Math.sin(rad);
    // CSS-style "cover the box" half-length: axis-aligned angles (0/90/…) span
    // edge-to-edge so both endpoints are visible; diagonals still reach the
    // corners. A fixed 0.5·√2 only fit 45° and pushed the end stops off-canvas
    // for vertical/horizontal gradients (icons looked washed toward the mid stop).
    const extent = 0.5 * (Math.abs(dx) + Math.abs(dy));
    return GradientTint.linear(
      stops,
      0.5 - dx * extent,
      0.5 - dy * extent,
      0.5 + dx * extent,
      0.5 + dy * extent,
    );
  }

  static radial(
    stops: GradientStop[],
    centerX: number = 0.5,
    centerY: number = 0.5,
    radius: number = 0.7071,
    focalX: number = centerX,
    focalY: number = centerY,
    focalRadius: number = 0,
  ): GradientTint {
    return new GradientTint(2, stops, [centerX, centerY, radius, focalX, focalY, focalRadius]);
  }
}

/** Object-style rendering options for business code. */
export interface RuyiOptionsInit {
  /** Output size in vp (Harmony logical pixels). */
  size: number;
  /** Optional solid tint as packed `0xAARRGGBB`; undefined keeps SVG colors. */
  color?: number;
  /** Optional gradient tint; takes precedence over color. */
  gradient?: GradientTint;
  /** Optional stroke width in points (see absoluteStrokeWidth). */
  strokeWidth?: number;
  /**
   * When true, strokeWidth is constant in points regardless of size.
   * When false, stroke scales with size / referenceSize (Lucide-style). Default.
   */
  absoluteStrokeWidth?: boolean;
  /** Design-size baseline used when absoluteStrokeWidth is false. Default 24. */
  referenceSize?: number;
  /** Screen density. Use display.densityDPI / 160 for device pixels. Default 1. */
  density?: number;
}

/** Rendering options for SVG → PixelMap (aligned with Apple / Android Ruyi). */
export class RuyiOptions {
  /** Output size in vp (Harmony logical pixels). */
  size: number;
  /** Optional solid tint as packed `0xAARRGGBB`; undefined keeps SVG colors. */
  color?: number;
  /** Optional gradient tint; takes precedence over color. */
  gradient?: GradientTint;
  /** Optional stroke width in points (see absoluteStrokeWidth). */
  strokeWidth?: number;
  /**
   * When true, strokeWidth is constant in points regardless of size.
   * When false, stroke scales with size / referenceSize (Lucide-style). Default.
   */
  absoluteStrokeWidth: boolean;
  /** Design-size baseline used when absoluteStrokeWidth is false. Default 24. */
  referenceSize: number;
  /** Screen density. Use display.densityDPI / 160 for device pixels. */
  density: number;

  constructor(options: RuyiOptionsInit) {
    this.size = options.size;
    this.color = options.color;
    this.strokeWidth = options.strokeWidth;
    this.absoluteStrokeWidth = options.absoluteStrokeWidth ?? false;
    this.referenceSize = options.referenceSize ?? 24;
    this.density = options.density ?? 1;
    this.gradient = options.gradient;
  }

  static from(options: RuyiOptionsInit): RuyiOptions {
    return new RuyiOptions(options);
  }
}

/**
 * Cross-platform SVG load & render runtime (HarmonyOS).
 *
 * Ships no built-in icons — pass your own SVG data / rawfile assets.
 * ArkTS API over ThorVG C API via an in-module NAPI bridge
 * (`@vnixx/thorvg` Prefab/HAR).
 *
 * Engine is lazy-inited on first render (same as Apple / Android Ruyi).
 */
export class Ruyi {
  /** ThorVG engine version string. */
  static version(): string {
    return ThorVG.version();
  }

  static async image(svg: RuyiSvgSource, options: RuyiOptionsInit): Promise<image.PixelMap | undefined> {
    const opts = RuyiOptions.from(options);
    if (opts.size <= 0 || opts.density <= 0) {
      return undefined;
    }
    const sizePx = Math.max(1, Math.round(opts.size * opts.density));
    const packed = Ruyi.packGradient(opts.gradient);
    if (packed) {
      // Harmony intentionally uses a mask-composition path for gradient tint.
      // Android and Apple currently inject gradients into ThorVG fill/stroke
      // paints directly, but that paints each shape independently. The Ruyi
      // public API expects one icon-wide gradient over the final alpha mask, so
      // we render a white mask first and then sample the gradient once in native
      // code. Keeping both phases in C++ also avoids large ArrayBuffer hops and
      // ArkTS per-pixel work during live size/stroke slider updates.
      const rgba = await ThorVG.renderSvgMaskGradientRgba(
        svg,
        sizePx,
        sizePx,
        WHITE_ARGB,
        opts.strokeWidth,
        opts.absoluteStrokeWidth,
        opts.size,
        opts.referenceSize,
        packed.kind,
        packed.offsets,
        packed.colors,
        packed.geom,
      );
      return rgba ? await ThorVG.pixelMapFromRgba(rgba, sizePx, sizePx) : undefined;
    }
    return ThorVG.renderSvg(
      svg,
      sizePx,
      sizePx,
      opts.color ?? 0,
      opts.strokeWidth,
      opts.absoluteStrokeWidth,
      opts.size,
      opts.referenceSize,
    );
  }

  /** Batch helper for demos / icon grids (one native worker job). */
  static async imageBatch(
    svgs: RuyiSvgSource[],
    options: RuyiOptionsInit,
  ): Promise<(image.PixelMap | undefined)[]> {
    const opts = RuyiOptions.from(options);
    if (svgs.length === 0 || opts.size <= 0 || opts.density <= 0) {
      return [];
    }
    const sizePx = Math.max(1, Math.round(opts.size * opts.density));
    const packed = Ruyi.packGradient(opts.gradient);
    if (packed) {
      // See image(...): batch gradient rendering follows the same Harmony-only
      // mask-composition path, but keeps the whole grid in one native worker job.
      const buffers = await ThorVG.renderSvgBatchMaskGradientRgba(
        svgs,
        sizePx,
        sizePx,
        WHITE_ARGB,
        opts.strokeWidth,
        opts.absoluteStrokeWidth,
        opts.size,
        opts.referenceSize,
        packed.kind,
        packed.offsets,
        packed.colors,
        packed.geom,
      );
      return ThorVG.pixelMapsFromRgbaBuffers(buffers, sizePx, sizePx);
    }
    return ThorVG.renderSvgBatch(
      svgs,
      sizePx,
      sizePx,
      opts.color ?? 0,
      opts.strokeWidth,
      opts.absoluteStrokeWidth,
      opts.size,
      opts.referenceSize,
    );
  }

  private static packGradient(gradient?: GradientTint): PackedGradient | undefined {
    if (!gradient || gradient.stops.length < 2) {
      return undefined;
    }
    const offsets = new Float32Array(gradient.stops.length);
    // ArkTS has no Uint32Array union ergonomics here; Int32 stores the same bits.
    // Native reads them as uint32_t so AA>=0x80 stays correct.
    const colors = new Int32Array(gradient.stops.length);
    for (let i = 0; i < gradient.stops.length; i++) {
      offsets[i] = Math.min(1, Math.max(0, gradient.stops[i].offset));
      colors[i] = gradient.stops[i].color | 0;
    }
    const geom = new Float32Array(gradient.geom.length);
    for (let i = 0; i < gradient.geom.length; i++) {
      geom[i] = gradient.geom[i];
    }
    return new PackedGradient(gradient.kind, offsets, colors, geom);
  }
}

class PackedGradient {
  kind: number;
  offsets: Float32Array;
  colors: Int32Array;
  geom: Float32Array;

  constructor(kind: number, offsets: Float32Array, colors: Int32Array, geom: Float32Array) {
    this.kind = kind;
    this.offsets = offsets;
    this.colors = colors;
    this.geom = geom;
  }
}
