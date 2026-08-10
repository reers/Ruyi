export const engineInit: (threads?: number) => number;
export const engineTerm: () => number;
export const version: () => string;

/**
 * Render SVG → Promise of ArrayBuffer (uint32 ARGB8888 / little-endian BGRA bytes, premultiplied).
 * Runs off the JS thread.
 */
export const renderSvg: (
  svg: string | ArrayBuffer,
  widthPx: number,
  heightPx: number,
  argb?: number,
  strokeWidth?: number,
  absoluteStroke?: boolean,
  designSize?: number,
  referenceSize?: number
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
  referenceSize?: number
) => Promise<ArrayBuffer[]>;
