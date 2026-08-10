import { image } from '@kit.ImageKit';
import { ThorVG } from './ThorVG';

/** Rendering options for SVG → PixelMap (aligned with Apple / Android Ruyi). */
export class RuyiOptions {
  /** Output size in density-independent pixels (logical vp). */
  sizeVp: number;
  /** Optional solid tint as packed `0xAARRGGBB`; undefined keeps SVG colors. */
  color?: number;
  /** Optional stroke width in points (see absoluteStrokeWidth). */
  strokeWidth?: number;
  /**
   * When true, strokeWidth is constant in points regardless of sizeVp.
   * When false, stroke scales with sizeVp / referenceSize (Lucide-style).
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
    absoluteStrokeWidth: boolean = true,
    referenceSize: number = 24,
    density: number = 1,
  ) {
    this.sizeVp = sizeVp;
    this.color = color;
    this.strokeWidth = strokeWidth;
    this.absoluteStrokeWidth = absoluteStrokeWidth;
    this.referenceSize = referenceSize;
    this.density = density;
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
    return ThorVG.renderSvg(
      svg,
      sizePx,
      sizePx,
      options.color ?? 0,
      options.strokeWidth,
      options.absoluteStrokeWidth,
      options.sizeVp,
      options.referenceSize,
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
    return ThorVG.renderSvgBatch(
      svgs,
      sizePx,
      sizePx,
      options.color ?? 0,
      options.strokeWidth,
      options.absoluteStrokeWidth,
      options.sizeVp,
      options.referenceSize,
    );
  }
}
