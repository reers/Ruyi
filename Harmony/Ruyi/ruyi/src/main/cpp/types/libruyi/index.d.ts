export const engineInit: (threads?: number) => number;
export const engineTerm: () => number;
export const version: () => string;

export type SvgSource = string | ArrayBuffer;

/**
 * Render SVG → Promise of ArrayBuffer (premul RGBA8888 bytes, swizzled from
 * ThorVG 0xAARRGGBB). ArkTS wraps as PixelMap RGBA_8888 + PREMUL.
 * Runs off the JS thread.
 *
 * gradientKind: 0=none, 1=linear, 2=radial
 * stopOffsets / stopColors / gradGeom: TypedArrays when gradientKind != 0
 */
export const renderSvg: (
  svg: SvgSource,
  widthPx: number,
  heightPx: number,
  argb?: number,
  strokeWidth?: number,
  absoluteStroke?: boolean,
  designSize?: number,
  referenceSize?: number,
  gradientKind?: number,
  stopOffsets?: Float32Array,
  stopColors?: Int32Array,
  gradGeom?: Float32Array
) => Promise<ArrayBuffer | null>;

/**
 * Batch render — one worker job for many SVGs (same style params).
 */
export const renderSvgBatch: (
  svgs: SvgSource[],
  widthPx: number,
  heightPx: number,
  argb?: number,
  strokeWidth?: number,
  absoluteStroke?: boolean,
  designSize?: number,
  referenceSize?: number,
  gradientKind?: number,
  stopOffsets?: Float32Array,
  stopColors?: Int32Array,
  gradGeom?: Float32Array
) => Promise<(ArrayBuffer | null)[]>;

/**
 * Apply an icon-wide gradient to an existing premul RGBA_8888 mask. This is the
 * native equivalent of the previous ArkTS gradientRgbaFromMask hot loop.
 */
export const composeGradientMask: (
  mask: ArrayBuffer,
  widthPx: number,
  heightPx: number,
  argb: number,
  strokeWidth: number,
  absoluteStroke: boolean,
  designSize: number,
  referenceSize: number,
  gradientKind: number,
  stopOffsets: Float32Array,
  stopColors: number[],
  gradGeom: Float32Array
) => Promise<ArrayBuffer | null>;

/**
 * Batch version of composeGradientMask — one worker job for many mask buffers.
 */
export const composeGradientMasks: (
  masks: (ArrayBuffer | undefined)[],
  widthPx: number,
  heightPx: number,
  argb: number,
  strokeWidth: number,
  absoluteStroke: boolean,
  designSize: number,
  referenceSize: number,
  gradientKind: number,
  stopOffsets: Float32Array,
  stopColors: number[],
  gradGeom: Float32Array
) => Promise<(ArrayBuffer | null)[]>;

/**
 * Render SVG as a white alpha mask, then apply an icon-wide gradient in native
 * code. Output is premul RGBA_8888 bytes ready for ImageKit PixelMap.
 */
export const renderSvgMaskGradient: (
  svg: SvgSource,
  widthPx: number,
  heightPx: number,
  maskArgb: number,
  strokeWidth: number,
  absoluteStroke: boolean,
  designSize: number,
  referenceSize: number,
  gradientKind: number,
  stopOffsets: Float32Array,
  stopColors: number[],
  gradGeom: Float32Array
) => Promise<ArrayBuffer | null>;

/**
 * Batch version of renderSvgMaskGradient — one worker job for many SVGs.
 */
export const renderSvgBatchMaskGradient: (
  svgs: SvgSource[],
  widthPx: number,
  heightPx: number,
  maskArgb: number,
  strokeWidth: number,
  absoluteStroke: boolean,
  designSize: number,
  referenceSize: number,
  gradientKind: number,
  stopOffsets: Float32Array,
  stopColors: number[],
  gradGeom: Float32Array
) => Promise<(ArrayBuffer | null)[]>;
