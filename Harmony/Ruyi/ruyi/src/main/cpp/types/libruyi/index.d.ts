export const engineInit: (threads?: number) => number;
export const engineTerm: () => number;
export const version: () => string;

/**
 * Render SVG → Promise of ArrayBuffer (premul RGBA8888 bytes, swizzled from
 * ThorVG 0xAARRGGBB). ArkTS wraps as PixelMap RGBA_8888 + PREMUL.
 * Runs off the JS thread.
 *
 * gradientKind: 0=none, 1=linear, 2=radial
 * stopOffsets / stopColors / gradGeom: TypedArrays when gradientKind != 0
 */
export const renderSvg: (
  svg: string | ArrayBuffer,
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
  svgs: string[],
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
) => Promise<ArrayBuffer[]>;
