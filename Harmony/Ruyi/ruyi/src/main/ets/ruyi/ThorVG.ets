import { image } from '@kit.ImageKit';
import ruyiNative from 'libruyi.so';

/**
 * Internal ThorVG bridge (NAPI → Prefab/HAR `libthorvg.so` C API).
 * Not part of the public Ruyi API — use {@link Ruyi} instead.
 *
 * Native emits premul RGBA8888; PixelMap is RGBA_8888 + PREMUL.
 */
export class ThorVG {
  static version(): string {
    return ruyiNative.version();
  }

  /**
   * Render SVG → PixelMap.
   * Native work is async; buffer is premul RGBA8888 (swizzled in napi).
   */
  static async renderSvg(
    svg: string | ArrayBuffer,
    widthPx: number,
    heightPx: number,
    argb: number = 0,
    strokeWidth?: number,
    absoluteStrokeWidth: boolean = false,
    designSize?: number,
    referenceSize: number = 24,
    gradientKind: number = 0,
    stopOffsets?: Float32Array,
    stopColors?: Int32Array,
    gradGeom?: Float32Array,
  ): Promise<image.PixelMap | undefined> {
    if (widthPx <= 0 || heightPx <= 0) {
      return undefined;
    }
    const nativeBuffer = await ThorVG.renderSvgRgba(
      svg,
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
    );
    if (!nativeBuffer) {
      return undefined;
    }
    return ThorVG.pixelMapFromRgba(nativeBuffer, widthPx, heightPx);
  }

  /**
   * Render SVG → premultiplied RGBA_8888 bytes.
   * Kept separate so Ruyi can use the native result as an alpha mask before
   * wrapping the final ImageKit PixelMap.
   */
  static async renderSvgRgba(
    svg: string | ArrayBuffer,
    widthPx: number,
    heightPx: number,
    argb: number = 0,
    strokeWidth?: number,
    absoluteStrokeWidth: boolean = false,
    designSize?: number,
    referenceSize: number = 24,
    gradientKind: number = 0,
    stopOffsets?: Float32Array,
    stopColors?: Int32Array,
    gradGeom?: Float32Array,
  ): Promise<ArrayBuffer | undefined> {
    if (widthPx <= 0 || heightPx <= 0) {
      return undefined;
    }
    const stroke: number = (strokeWidth === undefined) ? -1 : strokeWidth;
    const design: number = (designSize === undefined) ? Math.min(widthPx, heightPx) : designSize;
    const nativeBuffer: ArrayBuffer | null = await ruyiNative.renderSvg(
      svg,
      widthPx,
      heightPx,
      argb,
      stroke,
      absoluteStrokeWidth,
      design,
      referenceSize,
      gradientKind,
      stopOffsets,
      stopColors,
      gradGeom,
    );
    if (nativeBuffer === null) {
      return undefined;
    }
    return nativeBuffer;
  }

  /** Batch render many SVGs with the same style (one native worker job). */
  static async renderSvgBatch(
    svgs: string[],
    widthPx: number,
    heightPx: number,
    argb: number = 0,
    strokeWidth?: number,
    absoluteStrokeWidth: boolean = false,
    designSize?: number,
    referenceSize: number = 24,
    gradientKind: number = 0,
    stopOffsets?: Float32Array,
    stopColors?: Int32Array,
    gradGeom?: Float32Array,
  ): Promise<(image.PixelMap | undefined)[]> {
    if (svgs.length === 0 || widthPx <= 0 || heightPx <= 0) {
      return [];
    }
    const stroke: number = (strokeWidth === undefined) ? -1 : strokeWidth;
    const design: number = (designSize === undefined) ? Math.min(widthPx, heightPx) : designSize;
    const buffers: ArrayBuffer[] = await ruyiNative.renderSvgBatch(
      svgs,
      widthPx,
      heightPx,
      argb,
      stroke,
      absoluteStrokeWidth,
      design,
      referenceSize,
      gradientKind,
      stopOffsets,
      stopColors,
      gradGeom,
    );
    const out: (image.PixelMap | undefined)[] = [];
    for (let i = 0; i < buffers.length; i++) {
      const buf = buffers[i];
      if (buf === null || buf === undefined || buf.byteLength === 0) {
        out.push(undefined);
      } else {
        out.push(ThorVG.pixelMapFromRgba(buf, widthPx, heightPx));
      }
    }
    return out;
  }

  /** Batch render many SVGs to premultiplied RGBA_8888 bytes. */
  static async renderSvgBatchRgba(
    svgs: string[],
    widthPx: number,
    heightPx: number,
    argb: number = 0,
    strokeWidth?: number,
    absoluteStrokeWidth: boolean = false,
    designSize?: number,
    referenceSize: number = 24,
    gradientKind: number = 0,
    stopOffsets?: Float32Array,
    stopColors?: Int32Array,
    gradGeom?: Float32Array,
  ): Promise<(ArrayBuffer | undefined)[]> {
    if (svgs.length === 0 || widthPx <= 0 || heightPx <= 0) {
      return [];
    }
    const stroke: number = (strokeWidth === undefined) ? -1 : strokeWidth;
    const design: number = (designSize === undefined) ? Math.min(widthPx, heightPx) : designSize;
    const buffers: ArrayBuffer[] = await ruyiNative.renderSvgBatch(
      svgs,
      widthPx,
      heightPx,
      argb,
      stroke,
      absoluteStrokeWidth,
      design,
      referenceSize,
      gradientKind,
      stopOffsets,
      stopColors,
      gradGeom,
    );
    const out: (ArrayBuffer | undefined)[] = [];
    for (let i = 0; i < buffers.length; i++) {
      const buf = buffers[i];
      out.push((buf === null || buf === undefined || buf.byteLength === 0) ? undefined : buf);
    }
    return out;
  }

  static pixelMapFromRgba(
    rgbaBuffer: ArrayBuffer,
    widthPx: number,
    heightPx: number,
  ): image.PixelMap | undefined {
    const opts: image.InitializationOptions = {
      size: { width: widthPx, height: heightPx },
      srcPixelFormat: image.PixelMapFormat.RGBA_8888,
      pixelFormat: image.PixelMapFormat.RGBA_8888,
      editable: false,
      alphaType: image.AlphaType.PREMUL,
    };
    try {
      return image.createPixelMapSync(rgbaBuffer, opts);
    } catch (_e) {
      try {
        const fallback: image.InitializationOptions = {
          size: { width: widthPx, height: heightPx },
          pixelFormat: image.PixelMapFormat.RGBA_8888,
          editable: false,
          alphaType: image.AlphaType.PREMUL,
        };
        return image.createPixelMapSync(rgbaBuffer, fallback);
      } catch (_e2) {
        return undefined;
      }
    }
  }
}
