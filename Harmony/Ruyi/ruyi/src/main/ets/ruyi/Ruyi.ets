import { image } from '@kit.ImageKit';
import { ThorVG } from './ThorVG';

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
    const extent = 0.5 * Math.SQRT2;
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

/** Rendering options for SVG → PixelMap (aligned with Apple / Android Ruyi). */
export class RuyiOptions {
  /** Output size in density-independent pixels (logical vp). */
  sizeVp: number;
  /** Optional solid tint as packed `0xAARRGGBB`; undefined keeps SVG colors. */
  color?: number;
  /** Optional gradient tint; takes precedence over color. */
  gradient?: GradientTint;
  /** Optional stroke width in points (see absoluteStrokeWidth). */
  strokeWidth?: number;
  /**
   * When true, strokeWidth is constant in points regardless of sizeVp.
   * When false, stroke scales with sizeVp / referenceSize (Lucide-style). Default.
   */
  absoluteStrokeWidth: boolean;
  /** Design-size baseline used when absoluteStrokeWidth is false. Default 24. */
  referenceSize: number;
  /** Screen density. Use display.densityDPI / 160 for device pixels. */
  density: number;

  constructor(
    sizeVp: number,
    color?: number,
    strokeWidth?: number,
    absoluteStrokeWidth: boolean = false,
    referenceSize: number = 24,
    density: number = 1,
    gradient?: GradientTint,
  ) {
    this.sizeVp = sizeVp;
    this.color = color;
    this.strokeWidth = strokeWidth;
    this.absoluteStrokeWidth = absoluteStrokeWidth;
    this.referenceSize = referenceSize;
    this.density = density;
    this.gradient = gradient;
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

  static async image(svg: string | ArrayBuffer, options: RuyiOptions): Promise<image.PixelMap | undefined> {
    if (options.sizeVp <= 0 || options.density <= 0) {
      return undefined;
    }
    const sizePx = Math.max(1, Math.round(options.sizeVp * options.density));
    const packed = Ruyi.packGradient(options.gradient);
    return ThorVG.renderSvg(
      svg,
      sizePx,
      sizePx,
      packed ? 0 : (options.color ?? 0),
      options.strokeWidth,
      options.absoluteStrokeWidth,
      options.sizeVp,
      options.referenceSize,
      packed?.kind ?? 0,
      packed?.offsets,
      packed?.colors,
      packed?.geom,
    );
  }

  /** Batch helper for demos / icon grids (one native worker job). */
  static async imageBatch(
    svgs: string[],
    options: RuyiOptions,
  ): Promise<(image.PixelMap | undefined)[]> {
    if (svgs.length === 0 || options.sizeVp <= 0 || options.density <= 0) {
      return [];
    }
    const sizePx = Math.max(1, Math.round(options.sizeVp * options.density));
    const packed = Ruyi.packGradient(options.gradient);
    return ThorVG.renderSvgBatch(
      svgs,
      sizePx,
      sizePx,
      packed ? 0 : (options.color ?? 0),
      options.strokeWidth,
      options.absoluteStrokeWidth,
      options.sizeVp,
      options.referenceSize,
      packed?.kind ?? 0,
      packed?.offsets,
      packed?.colors,
      packed?.geom,
    );
  }

  private static packGradient(gradient?: GradientTint): PackedGradient | undefined {
    if (!gradient || gradient.stops.length < 2) {
      return undefined;
    }
    const offsets = new Float32Array(gradient.stops.length);
    const colors = new Int32Array(gradient.stops.length);
    for (let i = 0; i < gradient.stops.length; i++) {
      offsets[i] = Math.min(1, Math.max(0, gradient.stops[i].offset));
      colors[i] = gradient.stops[i].color | 0;
    }
    const geom = new Float32Array(gradient.geom.length);
    for (let i = 0; i < gradient.geom.length; i++) {
      geom[i] = gradient.geom[i];
    }
    return { kind: gradient.kind, offsets, colors, geom };
  }
}

interface PackedGradient {
  kind: number;
  offsets: Float32Array;
  colors: Int32Array;
  geom: Float32Array;
}
