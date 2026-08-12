import { image } from '@kit.ImageKit';
import ruyiNative from 'libruyi.so';

/**
 * Internal ThorVG bridge (NAPI → Prefab/HAR `libthorvg.so` C API).
 * Not part of the public Ruyi API — use {@link Ruyi} instead.
 */
export class ThorVG {
  static version(): string {
    return ruyiNative.version();
  }

  /**
   * Render SVG → PixelMap.
   * Native work is async (worker thread); PixelMap creation uses BGRA_8888 directly.
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
    return ThorVG.pixelMapFromNative(nativeBuffer, widthPx, heightPx);
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
        out.push(ThorVG.pixelMapFromNative(buf, widthPx, heightPx));
      }
    }
    return out;
  }

  /**
   * ThorVG writes uint32 0xAARRGGBB; on little-endian memory that is B,G,R,A —
   * which matches Harmony `BGRA_8888` + PREMUL.
   */
  private static pixelMapFromNative(
    argbBuffer: ArrayBuffer,
    widthPx: number,
    heightPx: number,
  ): image.PixelMap | undefined {
    const opts: image.InitializationOptions = {
      size: { width: widthPx, height: heightPx },
      pixelFormat: image.PixelMapFormat.BGRA_8888,
      editable: false,
      alphaType: image.AlphaType.PREMUL,
    };
    try {
      return image.createPixelMapSync(argbBuffer, opts);
    } catch (_e) {
      return undefined;
    }
  }
}
