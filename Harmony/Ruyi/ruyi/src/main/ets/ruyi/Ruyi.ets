import { image } from '@kit.ImageKit';
import { ThorVG } from './ThorVG';

const WHITE_ARGB: number = 0xFFFFFFFF;

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
    if (packed) {
      const mask = await ThorVG.renderSvgRgba(
        svg,
        sizePx,
        sizePx,
        WHITE_ARGB,
        options.strokeWidth,
        options.absoluteStrokeWidth,
        options.sizeVp,
        options.referenceSize,
      );
      if (!mask) {
        return undefined;
      }
      return ThorVG.pixelMapFromRgba(Ruyi.gradientRgbaFromMask(mask, sizePx, sizePx, packed), sizePx, sizePx);
    }
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
    const packed = Ruyi.packGradient(options.gradient);
    if (packed) {
      const masks = await ThorVG.renderSvgBatchRgba(
        svgs,
        sizePx,
        sizePx,
        WHITE_ARGB,
        options.strokeWidth,
        options.absoluteStrokeWidth,
        options.sizeVp,
        options.referenceSize,
      );
      const out: (image.PixelMap | undefined)[] = [];
      for (let i = 0; i < masks.length; i++) {
        const mask = masks[i];
        out.push(mask
          ? ThorVG.pixelMapFromRgba(Ruyi.gradientRgbaFromMask(mask, sizePx, sizePx, packed), sizePx, sizePx)
          : undefined);
      }
      return out;
    }
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

  private static gradientRgbaFromMask(
    maskBuffer: ArrayBuffer,
    widthPx: number,
    heightPx: number,
    gradient: PackedGradient,
  ): ArrayBuffer {
    const mask = new Uint8Array(maskBuffer);
    const out = new Uint8Array(widthPx * heightPx * 4);
    const stops = Ruyi.resolvedStops(gradient);
    if (stops.length < 2) {
      return out.buffer;
    }

    for (let y = 0; y < heightPx; y++) {
      const py = y + 0.5;
      for (let x = 0; x < widthPx; x++) {
        const offset = (y * widthPx + x) * 4;
        const maskAlpha = mask[offset + 3];
        if (maskAlpha === 0) {
          continue;
        }
        const px = x + 0.5;
        const t = gradient.kind === 2
          ? Ruyi.radialParameter(px, py, widthPx, heightPx, gradient.geom)
          : Ruyi.linearParameter(px, py, widthPx, heightPx, gradient.geom);
        Ruyi.writePremulStopColor(out, offset, stops, t, maskAlpha);
      }
    }
    return out.buffer;
  }

  private static resolvedStops(gradient: PackedGradient): ResolvedGradientStop[] {
    const stops: ResolvedGradientStop[] = [];
    const count = Math.min(gradient.offsets.length, gradient.colors.length);
    for (let i = 0; i < count; i++) {
      const argb = gradient.colors[i] >>> 0;
      stops.push(new ResolvedGradientStop(
        Ruyi.clamp01(gradient.offsets[i]),
        (argb >>> 24) & 0xff,
        (argb >>> 16) & 0xff,
        (argb >>> 8) & 0xff,
        argb & 0xff,
      ));
    }
    stops.sort((a: ResolvedGradientStop, b: ResolvedGradientStop) => a.offset - b.offset);
    return stops;
  }

  private static linearParameter(
    px: number,
    py: number,
    widthPx: number,
    heightPx: number,
    geom: Float32Array,
  ): number {
    if (geom.length < 4) {
      return 0;
    }
    const x1 = geom[0] * widthPx;
    const y1 = geom[1] * heightPx;
    const x2 = geom[2] * widthPx;
    const y2 = geom[3] * heightPx;
    const dx = x2 - x1;
    const dy = y2 - y1;
    const len2 = dx * dx + dy * dy;
    if (len2 <= 0.000001) {
      return 1;
    }
    return ((px - x1) * dx + (py - y1) * dy) / len2;
  }

  private static radialParameter(
    px: number,
    py: number,
    widthPx: number,
    heightPx: number,
    geom: Float32Array,
  ): number {
    if (geom.length < 6) {
      return 0;
    }
    const edge = Math.max(1, Math.min(widthPx, heightPx));
    const cx = geom[0] * widthPx;
    const cy = geom[1] * heightPx;
    const radius = Math.max(0, geom[2]) * edge;
    const fx = geom[3] * widthPx;
    const fy = geom[4] * heightPx;
    const focalRadius = Math.max(0, geom[5]) * edge;
    const dr = radius - focalRadius;
    if (Math.abs(dr) <= 0.000001 && Math.abs(cx - fx) <= 0.000001 && Math.abs(cy - fy) <= 0.000001) {
      const pxToCenter = px - cx;
      const pyToCenter = py - cy;
      return radius <= 0.000001 ? 1 : Math.sqrt(pxToCenter * pxToCenter + pyToCenter * pyToCenter) / radius;
    }

    const dx = cx - fx;
    const dy = cy - fy;
    const qx = fx - px;
    const qy = fy - py;
    const a = dx * dx + dy * dy - dr * dr;
    const b = 2 * (qx * dx + qy * dy - focalRadius * dr);
    const c = qx * qx + qy * qy - focalRadius * focalRadius;
    if (Math.abs(a) <= 0.000001) {
      if (Math.abs(b) <= 0.000001) {
        return 0;
      }
      return -c / b;
    }

    const disc = b * b - 4 * a * c;
    if (disc < 0) {
      return 0;
    }
    const root = Math.sqrt(disc);
    const t0 = (-b - root) / (2 * a);
    const t1 = (-b + root) / (2 * a);
    if (t0 >= 0 && t1 >= 0) {
      return Math.min(t0, t1);
    }
    if (t0 >= 0) {
      return t0;
    }
    return t1;
  }

  private static writePremulStopColor(
    out: Uint8Array,
    offset: number,
    stops: ResolvedGradientStop[],
    t: number,
    maskAlpha: number,
  ): void {
    const clamped = Ruyi.clamp01(t);
    let left = stops[0];
    let right = stops[stops.length - 1];
    if (clamped <= left.offset) {
      right = left;
    } else if (clamped >= right.offset) {
      left = right;
    } else {
      for (let i = 1; i < stops.length; i++) {
        if (clamped <= stops[i].offset) {
          left = stops[i - 1];
          right = stops[i];
          break;
        }
      }
    }

    const span = right.offset - left.offset;
    const local = Math.abs(span) <= 0.000001 ? 0 : (clamped - left.offset) / span;
    const stopA = Ruyi.lerp(left.a, right.a, local);
    const alpha = Math.round(stopA * maskAlpha / 255);
    out[offset + 3] = alpha;
    if (alpha === 0) {
      return;
    }
    out[offset] = Math.round(Ruyi.lerp(left.r, right.r, local) * alpha / 255);
    out[offset + 1] = Math.round(Ruyi.lerp(left.g, right.g, local) * alpha / 255);
    out[offset + 2] = Math.round(Ruyi.lerp(left.b, right.b, local) * alpha / 255);
  }

  private static lerp(a: number, b: number, t: number): number {
    return a + (b - a) * t;
  }

  private static clamp01(value: number): number {
    return Math.min(1, Math.max(0, value));
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

class ResolvedGradientStop {
  offset: number;
  a: number;
  r: number;
  g: number;
  b: number;

  constructor(offset: number, a: number, r: number, g: number, b: number) {
    this.offset = offset;
    this.a = a;
    this.r = r;
    this.g = g;
    this.b = b;
  }
}
