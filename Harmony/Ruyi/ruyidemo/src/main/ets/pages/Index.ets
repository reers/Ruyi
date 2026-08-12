import { Ruyi, RuyiOptions, GradientStop, GradientTint } from '@reers/ruyi';
import { image } from '@kit.ImageKit';
import { display } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { buffer } from '@kit.ArkTS';

interface IconItem {
  name: string;
  svg: string;
}

type TintMode = 'original' | 'solid' | 'linear' | 'radial';

/** Harmony colors are #AARRGGBB (not CSS #RRGGBBAA). Match Apple/iOS demo. */
namespace DemoColor {
  export const canvas = '#FF292929';
  export const panel = '#FF1C1C1C';
  export const cell = '#FF3A3A3A';
  export const white = '#FFFFFFFF';
  export const white85 = '#D9FFFFFF';
  export const white70 = '#B3FFFFFF';
  export const white55 = '#8CFFFFFF';
  export const white45 = '#73FFFFFF';
  export const white08 = '#14FFFFFF';
  export const white20 = '#33FFFFFF';
  export const white35 = '#59FFFFFF';
  export const accent = '#FFF25973';
  export const accentSoft = '#FFF28C99';
}

const PALETTE: number[] = [
  0xFFF25973,
  0xFFFFBF33,
  0xFF598CFF,
  0xFF59CC8C,
  0xFFFFFFFF,
  0xFFB366F2,
];

@Entry
@Component
struct Index {
  @State icons: IconItem[] = [];
  @State tintMode: TintMode = 'original';
  @State engineVersion: string = '';
  @State density: number = 3;

  aboutToAppear(): void {
    try {
      const d = display.getDefaultDisplaySync();
      this.density = d.densityDPI / 160;
    } catch (_e) {
      this.density = 3;
    }
    this.engineVersion = Ruyi.version();
    this.loadIcons();
  }

  private async loadIcons(): Promise<void> {
    const ctx = getContext(this) as common.UIAbilityContext;
    const rm = ctx.resourceManager;
    const names = [
      'arrow-right', 'battery', 'bell', 'bluetooth', 'camera', 'check',
      'cloud', 'code', 'download', 'gift', 'heart', 'home',
    ];
    const loaded: IconItem[] = [];
    for (const name of names) {
      try {
        const bytes = await rm.getRawFileContent(`icons/${name}.svg`);
        const svg = buffer.from(bytes.buffer).toString('utf-8');
        loaded.push({ name, svg });
      } catch (_e) {
        // skip missing
      }
    }
    this.icons = loaded;
  }

  private selectMode(mode: TintMode): void {
    if (this.tintMode !== mode) {
      this.tintMode = mode;
    }
  }

  build() {
    Column() {
      if (this.icons.length === 0) {
        Text('loading…')
          .fontSize(14)
          .fontColor(DemoColor.white55)
          .width('100%')
          .height('100%')
          .textAlign(TextAlign.Center)
      } else if (this.tintMode === 'original') {
        // Isolated workspaces (Android key / iOS .id): hard remount on mode change.
        OriginalWorkspace({
          icons: this.icons,
          engineVersion: this.engineVersion,
          density: this.density,
          tintMode: this.tintMode,
          onModeChange: (m: TintMode) => this.selectMode(m),
        })
          .id('ws-original')
          .layoutWeight(1)
      } else if (this.tintMode === 'solid') {
        SolidWorkspace({
          icons: this.icons,
          engineVersion: this.engineVersion,
          density: this.density,
          tintMode: this.tintMode,
          onModeChange: (m: TintMode) => this.selectMode(m),
        })
          .id('ws-solid')
          .layoutWeight(1)
      } else if (this.tintMode === 'linear') {
        GradientWorkspace({
          icons: this.icons,
          engineVersion: this.engineVersion,
          density: this.density,
          tintMode: this.tintMode,
          onModeChange: (m: TintMode) => this.selectMode(m),
        })
          .id('ws-linear')
          .layoutWeight(1)
      } else {
        GradientWorkspace({
          icons: this.icons,
          engineVersion: this.engineVersion,
          density: this.density,
          tintMode: this.tintMode,
          onModeChange: (m: TintMode) => this.selectMode(m),
        })
          .id('ws-radial')
          .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(DemoColor.canvas)
  }
}

function flushRelease(maps: (image.PixelMap | undefined)[]): void {
  for (let i = 0; i < maps.length; i++) {
    const pm = maps[i];
    if (!pm) {
      continue;
    }
    try {
      pm.release();
    } catch (_e) {
      // ignore
    }
  }
}

function mapsToList(maps: Record<string, image.PixelMap>): image.PixelMap[] {
  const keys = Object.keys(maps);
  const out: image.PixelMap[] = [];
  for (let i = 0; i < keys.length; i++) {
    out.push(maps[keys[i]]);
  }
  return out;
}

@Component
struct OriginalWorkspace {
  @Prop icons: IconItem[] = [];
  @Prop engineVersion: string = '';
  @Prop density: number = 3;
  @Prop tintMode: TintMode = 'original';
  onModeChange: (mode: TintMode) => void = (_m: TintMode) => {};

  @State pixelMaps: Record<string, image.PixelMap> = {};
  @State sizeVp: number = 40;
  @State status: string = 'ready';
  private pending: boolean = false;
  private rendering: boolean = false;
  private token: number = 0;
  private releaseTimer: number = -1;
  private awaitingRelease: image.PixelMap[] = [];

  aboutToAppear(): void {
    this.scheduleRender();
  }

  aboutToDisappear(): void {
    this.token++;
    this.pending = false;
    if (this.releaseTimer !== -1) {
      clearTimeout(this.releaseTimer);
      this.releaseTimer = -1;
    }
    flushRelease(this.awaitingRelease);
    this.awaitingRelease = [];
    flushRelease(mapsToList(this.pixelMaps));
    this.pixelMaps = {};
  }

  private scheduleRender(): void {
    this.pending = true;
    if (!this.rendering) {
      this.drainRender();
    }
  }

  private async drainRender(): Promise<void> {
    if (this.rendering) {
      return;
    }
    this.rendering = true;
    const token = this.token;
    try {
      while (this.pending) {
        this.pending = false;
        await this.renderCurrent(token);
        if (token !== this.token) {
          break;
        }
      }
    } finally {
      this.rendering = false;
      if (this.pending && token === this.token) {
        this.drainRender();
      }
    }
  }

  private async renderCurrent(token: number): Promise<void> {
    if (this.icons.length === 0) {
      return;
    }
    const options = new RuyiOptions(Math.round(this.sizeVp), undefined, undefined, false, 24, this.density);
    const maps = await Ruyi.imageBatch(this.icons.map((i: IconItem) => i.svg), options);
    if (token !== this.token) {
      flushRelease(maps);
      return;
    }
    const next: Record<string, image.PixelMap> = {};
    let ok = 0;
    for (let i = 0; i < this.icons.length; i++) {
      if (maps[i]) {
        next[this.icons[i].name] = maps[i] as image.PixelMap;
        ok++;
      }
    }
    const old = this.pixelMaps;
    this.pixelMaps = next;
    this.status =
      `ok · original · ${ok}/${this.icons.length} · ${Math.round(this.sizeVp)}vp · ThorVG ${this.engineVersion}`;
    this.deferRelease(mapsToList(old));
  }

  private deferRelease(maps: image.PixelMap[]): void {
    if (maps.length === 0) {
      return;
    }
    for (let i = 0; i < maps.length; i++) {
      this.awaitingRelease.push(maps[i]);
    }
    if (this.releaseTimer !== -1) {
      clearTimeout(this.releaseTimer);
    }
    this.releaseTimer = setTimeout(() => {
      this.releaseTimer = -1;
      const batch = this.awaitingRelease;
      this.awaitingRelease = [];
      flushRelease(batch);
    }, 48);
  }

  build() {
    Column() {
      this.iconGrid()
      ControlPanel({
        tintMode: this.tintMode,
        onModeChange: this.onModeChange,
        status: this.status,
        blurb: 'Original SVG colors and strokes — only size is adjustable.',
        onReset: () => {
          this.sizeVp = 40;
          this.scheduleRender();
        },
      }) {
        SharedSlider({
          title: 'Size',
          valueText: `${Math.round(this.sizeVp)}vp`,
          value: this.sizeVp,
          min: 16,
          max: 72,
          step: 1,
          onChange: (v: number) => {
            this.sizeVp = Math.round(v);
            this.scheduleRender();
          },
        })
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  iconGrid() {
    Grid() {
      ForEach(this.icons, (item: IconItem) => {
        GridItem() {
          Column() {
            if (this.pixelMaps[item.name]) {
              Image(this.pixelMaps[item.name])
                .width(Math.min(this.sizeVp, 76))
                .height(Math.min(this.sizeVp, 76))
                .objectFit(ImageFit.Contain)
                .syncLoad(true)
            }
          }
          .width(88)
          .height(88)
          .justifyContent(FlexAlign.Center)
          .backgroundColor(DemoColor.cell)
          .borderRadius(12)
          .padding(6)
        }
      }, (item: IconItem) => item.name)
    }
    .columnsTemplate('1fr 1fr 1fr')
    .columnsGap(12)
    .rowsGap(12)
    .padding(12)
    .layoutWeight(1)
    .width('100%')
    .backgroundColor(DemoColor.canvas)
  }
}

@Component
struct SolidWorkspace {
  @Prop icons: IconItem[] = [];
  @Prop engineVersion: string = '';
  @Prop density: number = 3;
  @Prop tintMode: TintMode = 'solid';
  onModeChange: (mode: TintMode) => void = (_m: TintMode) => {};

  @State pixelMaps: Record<string, image.PixelMap> = {};
  @State sizeVp: number = 40;
  @State strokePt: number = 2;
  @State hue: number = 0;
  @State absoluteStroke: boolean = false;
  @State status: string = 'ready';
  private pending: boolean = false;
  private rendering: boolean = false;
  private token: number = 0;
  private releaseTimer: number = -1;
  private awaitingRelease: image.PixelMap[] = [];

  aboutToAppear(): void {
    this.scheduleRender();
  }

  aboutToDisappear(): void {
    this.token++;
    this.pending = false;
    if (this.releaseTimer !== -1) {
      clearTimeout(this.releaseTimer);
      this.releaseTimer = -1;
    }
    flushRelease(this.awaitingRelease);
    this.awaitingRelease = [];
    flushRelease(mapsToList(this.pixelMaps));
    this.pixelMaps = {};
  }

  private scheduleRender(): void {
    this.pending = true;
    if (!this.rendering) {
      this.drainRender();
    }
  }

  private async drainRender(): Promise<void> {
    if (this.rendering) {
      return;
    }
    this.rendering = true;
    const token = this.token;
    try {
      while (this.pending) {
        this.pending = false;
        await this.renderCurrent(token);
        if (token !== this.token) {
          break;
        }
      }
    } finally {
      this.rendering = false;
      if (this.pending && token === this.token) {
        this.drainRender();
      }
    }
  }

  private async renderCurrent(token: number): Promise<void> {
    if (this.icons.length === 0) {
      return;
    }
    const options = new RuyiOptions(
      Math.round(this.sizeVp),
      hsvToArgb(this.hue, 0.75, 1),
      this.strokePt,
      this.absoluteStroke,
      24,
      this.density,
    );
    const maps = await Ruyi.imageBatch(this.icons.map((i: IconItem) => i.svg), options);
    if (token !== this.token) {
      flushRelease(maps);
      return;
    }
    const next: Record<string, image.PixelMap> = {};
    let ok = 0;
    for (let i = 0; i < this.icons.length; i++) {
      if (maps[i]) {
        next[this.icons[i].name] = maps[i] as image.PixelMap;
        ok++;
      }
    }
    const old = this.pixelMaps;
    this.pixelMaps = next;
    this.status =
      `ok · solid · ${ok}/${this.icons.length} · ${Math.round(this.sizeVp)}vp · ThorVG ${this.engineVersion}`;
    this.deferRelease(mapsToList(old));
  }

  private deferRelease(maps: image.PixelMap[]): void {
    if (maps.length === 0) {
      return;
    }
    for (let i = 0; i < maps.length; i++) {
      this.awaitingRelease.push(maps[i]);
    }
    if (this.releaseTimer !== -1) {
      clearTimeout(this.releaseTimer);
    }
    this.releaseTimer = setTimeout(() => {
      this.releaseTimer = -1;
      const batch = this.awaitingRelease;
      this.awaitingRelease = [];
      flushRelease(batch);
    }, 48);
  }

  build() {
    Column() {
      this.iconGrid()
      ControlPanel({
        tintMode: this.tintMode,
        onModeChange: this.onModeChange,
        status: this.status,
        blurb: 'Solid tint with live size, color and stroke controls.',
        onReset: () => {
          this.sizeVp = 40;
          this.strokePt = 2;
          this.hue = 0;
          this.absoluteStroke = false;
          this.scheduleRender();
        },
      }) {
        SharedSlider({
          title: 'Hue',
          valueText: `${Math.round(this.hue)}°`,
          value: this.hue,
          min: 0,
          max: 360,
          step: 1,
          onChange: (v: number) => {
            this.hue = v;
            this.scheduleRender();
          },
        })
        Row() {
          Text('Absolute Stroke width')
            .fontSize(13)
            .fontColor(DemoColor.white70)
          Blank()
          Toggle({ type: ToggleType.Switch, isOn: this.absoluteStroke })
            .selectedColor(DemoColor.white35)
            .onChange((v: boolean) => {
              this.absoluteStroke = v;
              this.scheduleRender();
            })
        }
        .width('100%')
        SharedSlider({
          title: 'Stroke',
          valueText: `${this.strokePt.toFixed(1)}pt`,
          value: this.strokePt,
          min: 0.5,
          max: 5,
          step: 0.1,
          onChange: (v: number) => {
            this.strokePt = v;
            this.scheduleRender();
          },
        })
        SharedSlider({
          title: 'Size',
          valueText: `${Math.round(this.sizeVp)}vp`,
          value: this.sizeVp,
          min: 16,
          max: 72,
          step: 1,
          onChange: (v: number) => {
            this.sizeVp = Math.round(v);
            this.scheduleRender();
          },
        })
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  iconGrid() {
    Grid() {
      ForEach(this.icons, (item: IconItem) => {
        GridItem() {
          Column() {
            if (this.pixelMaps[item.name]) {
              Image(this.pixelMaps[item.name])
                .width(Math.min(this.sizeVp, 76))
                .height(Math.min(this.sizeVp, 76))
                .objectFit(ImageFit.Contain)
                .syncLoad(true)
            }
          }
          .width(88)
          .height(88)
          .justifyContent(FlexAlign.Center)
          .backgroundColor(DemoColor.cell)
          .borderRadius(12)
          .padding(6)
        }
      }, (item: IconItem) => item.name)
    }
    .columnsTemplate('1fr 1fr 1fr')
    .columnsGap(12)
    .rowsGap(12)
    .padding(12)
    .layoutWeight(1)
    .width('100%')
    .backgroundColor(DemoColor.canvas)
  }
}

@Component
struct GradientWorkspace {
  @Prop icons: IconItem[] = [];
  @Prop engineVersion: string = '';
  @Prop density: number = 3;
  @Prop tintMode: TintMode = 'linear';
  onModeChange: (mode: TintMode) => void = (_m: TintMode) => {};

  @State pixelMaps: Record<string, image.PixelMap> = {};
  @State sizeVp: number = 40;
  @State strokePt: number = 2;
  @State absoluteStroke: boolean = false;
  @State showEditor: boolean = false;
  @State stop0: number = 0xFFF25973;
  @State stop1: number = 0xFFFFBF33;
  @State stop2: number = 0xFF598CFF;
  @State useMid: boolean = true;
  @State midOffset: number = 0.5;
  @State angle: number = 90;
  @State centerX: number = 0.5;
  @State centerY: number = 0.5;
  @State radius: number = 0.71;
  @State status: string = 'ready';
  /** Mirrored committed stops for the summary bar (must match raster, not live editor). */
  @State previewOffsets: number[] = [0, 0.5, 1];
  @State previewColors: number[] = [0xFFF25973, 0xFFFFBF33, 0xFF598CFF];
  private committedKind: number = 1;
  private committedOffsets: number[] = [0, 0.5, 1];
  private committedColors: number[] = [0xFFF25973, 0xFFFFBF33, 0xFF598CFF];
  private committedGeom: number[] = [];
  private pending: boolean = false;
  private rendering: boolean = false;
  private token: number = 0;
  private releaseTimer: number = -1;
  private awaitingRelease: image.PixelMap[] = [];
  /** Canvas preview — same geometric endpoints as Android/iOS (not ArkUI angle). */
  private previewSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private previewCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.previewSettings);

  aboutToAppear(): void {
    this.commitGradient();
    this.scheduleRender();
  }

  aboutToDisappear(): void {
    this.token++;
    this.pending = false;
    if (this.releaseTimer !== -1) {
      clearTimeout(this.releaseTimer);
      this.releaseTimer = -1;
    }
    flushRelease(this.awaitingRelease);
    this.awaitingRelease = [];
    flushRelease(mapsToList(this.pixelMaps));
    this.pixelMaps = {};
  }

  private commitGradient(): void {
    const g = this.buildGradient();
    this.committedKind = g.kind;
    this.committedOffsets = g.stops.map((s: GradientStop) => s.offset);
    this.committedColors = g.stops.map((s: GradientStop) => s.color);
    this.committedGeom = g.geom.slice();
    // Keep summary bar in sync with what imageBatch actually paints.
    this.previewOffsets = this.committedOffsets.slice();
    this.previewColors = this.committedColors.slice();
  }

  private buildGradient(): GradientTint {
    const stops: GradientStop[] = [new GradientStop(0, this.stop0)];
    if (this.useMid) {
      stops.push(new GradientStop(this.midOffset, this.stop1));
    }
    stops.push(new GradientStop(1, this.stop2));
    return this.tintMode === 'linear'
      ? GradientTint.linearAngle(stops, this.angle)
      : GradientTint.radial(stops, this.centerX, this.centerY, this.radius);
  }

  private committedTint(): GradientTint {
    const stops: GradientStop[] = [];
    for (let i = 0; i < this.committedOffsets.length; i++) {
      stops.push(new GradientStop(this.committedOffsets[i], this.committedColors[i]));
    }
    return new GradientTint(this.committedKind, stops, this.committedGeom.slice());
  }

  private scheduleRender(): void {
    this.pending = true;
    if (!this.rendering) {
      this.drainRender();
    }
  }

  private async drainRender(): Promise<void> {
    if (this.rendering) {
      return;
    }
    this.rendering = true;
    const token = this.token;
    try {
      while (this.pending) {
        this.pending = false;
        await this.renderCurrent(token);
        if (token !== this.token) {
          break;
        }
      }
    } finally {
      this.rendering = false;
      if (this.pending && token === this.token) {
        this.drainRender();
      }
    }
  }

  private async renderCurrent(token: number): Promise<void> {
    if (this.icons.length === 0 || this.showEditor) {
      return;
    }
    const options = new RuyiOptions(
      Math.round(this.sizeVp),
      undefined,
      this.strokePt,
      this.absoluteStroke,
      24,
      this.density,
      this.committedTint(),
    );
    const maps = await Ruyi.imageBatch(this.icons.map((i: IconItem) => i.svg), options);
    if (token !== this.token) {
      flushRelease(maps);
      return;
    }
    const next: Record<string, image.PixelMap> = {};
    let ok = 0;
    for (let i = 0; i < this.icons.length; i++) {
      if (maps[i]) {
        next[this.icons[i].name] = maps[i] as image.PixelMap;
        ok++;
      }
    }
    const old = this.pixelMaps;
    this.pixelMaps = next;
    this.status =
      `ok · ${this.tintMode} · ${ok}/${this.icons.length} · ${Math.round(this.sizeVp)}vp · ThorVG ${this.engineVersion}`;
    this.deferRelease(mapsToList(old));
  }

  private deferRelease(maps: image.PixelMap[]): void {
    if (maps.length === 0) {
      return;
    }
    for (let i = 0; i < maps.length; i++) {
      this.awaitingRelease.push(maps[i]);
    }
    if (this.releaseTimer !== -1) {
      clearTimeout(this.releaseTimer);
    }
    this.releaseTimer = setTimeout(() => {
      this.releaseTimer = -1;
      const batch = this.awaitingRelease;
      this.awaitingRelease = [];
      flushRelease(batch);
    }, 48);
  }

  private stopColor(which: number): number {
    if (which === 0) {
      return this.stop0;
    }
    if (which === 1) {
      return this.stop1;
    }
    return this.stop2;
  }

  private pickStop(which: number, color: number): void {
    if (which === 0) {
      this.stop0 = color;
    } else if (which === 1) {
      this.stop1 = color;
    } else {
      this.stop2 = color;
    }
    this.redrawGradientPreview();
  }

  private previewColorStops(): Array<[string, number]> {
    // Outside the editor: show committed colors (same as raster).
    // Inside the editor: show live picks so the bar tracks swatches.
    const out: Array<[string, number]> = [];
    if (this.showEditor) {
      out.push([argbToCss(this.stop0), 0]);
      if (this.useMid) {
        out.push([argbToCss(this.stop1), this.midOffset]);
      }
      out.push([argbToCss(this.stop2), 1]);
      return out;
    }
    for (let i = 0; i < this.previewColors.length; i++) {
      out.push([argbToCss(this.previewColors[i]), this.previewOffsets[i]]);
    }
    return out;
  }

  /** Paint the summary bar with the same unit-square geometry as the raster. */
  private redrawGradientPreview(): void {
    const w = this.previewCtx.width;
    const h = this.previewCtx.height;
    if (w <= 0 || h <= 0) {
      return;
    }
    const ctx = this.previewCtx;
    ctx.clearRect(0, 0, w, h);
    if (this.tintMode !== 'linear') {
      return;
    }
    // Match Android GradientPreview: linearAngle → scale onto bar size.
    const ends = GradientTint.linearAngle(
      [new GradientStop(0, 0), new GradientStop(1, 0)],
      this.angle,
    ).geom;
    const grad = ctx.createLinearGradient(
      ends[0] * w, ends[1] * h,
      ends[2] * w, ends[3] * h,
    );
    const stops = this.previewColorStops();
    for (let i = 0; i < stops.length; i++) {
      grad.addColorStop(stops[i][1], stops[i][0]);
    }
    ctx.fillStyle = grad;
    ctx.fillRect(0, 0, w, h);
  }

  build() {
    Column() {
      this.iconGrid()
      ControlPanel({
        tintMode: this.tintMode,
        onModeChange: this.onModeChange,
        status: this.status,
        blurb: 'Gradient tint. Edit stops in the panel; stroke/size stay live.',
        onReset: () => {
          this.sizeVp = 40;
          this.strokePt = 2;
          this.absoluteStroke = false;
          this.stop0 = 0xFFF25973;
          this.stop1 = 0xFFFFBF33;
          this.stop2 = 0xFF598CFF;
          this.useMid = true;
          this.midOffset = 0.5;
          this.angle = 90;
          this.centerX = 0.5;
          this.centerY = 0.5;
          this.radius = 0.71;
          this.showEditor = false;
          this.commitGradient();
          this.redrawGradientPreview();
          this.scheduleRender();
        },
      }) {
        this.gradientControls()
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  iconGrid() {
    Grid() {
      ForEach(this.icons, (item: IconItem) => {
        GridItem() {
          Column() {
            if (this.pixelMaps[item.name]) {
              Image(this.pixelMaps[item.name])
                .width(Math.min(this.sizeVp, 76))
                .height(Math.min(this.sizeVp, 76))
                .objectFit(ImageFit.Contain)
                .syncLoad(true)
            }
          }
          .width(88)
          .height(88)
          .justifyContent(FlexAlign.Center)
          .backgroundColor(DemoColor.cell)
          .borderRadius(12)
          .padding(6)
        }
      }, (item: IconItem) => item.name)
    }
    .columnsTemplate('1fr 1fr 1fr')
    .columnsGap(12)
    .rowsGap(12)
    .padding(12)
    .layoutWeight(1)
    .width('100%')
    .backgroundColor(DemoColor.canvas)
  }

  @Builder
  gradientControls() {
    if (this.tintMode === 'linear') {
      // Canvas + linearAngle endpoints (Android/iOS style). ArkUI's angle-based
      // .linearGradient jumps visually on a short bar and uses a different
      // angle convention — geometric endpoints rotate uniformly with the slider.
      Canvas(this.previewCtx)
        .width('100%')
        .height(28)
        .borderRadius(8)
        .border({ width: 1, color: DemoColor.white08 })
        .onReady(() => {
          this.redrawGradientPreview();
        })
        .onAreaChange((_old: Area, area: Area) => {
          this.redrawGradientPreview();
        })
    } else {
      Column()
        .width('100%')
        .height(56)
        .borderRadius(8)
        .radialGradient({
          center: [`${Math.round(this.centerX * 100)}%`, `${Math.round(this.centerY * 100)}%`],
          radius: `${Math.round(this.radius * 60)}%`,
          colors: this.previewColorStops(),
        })
        .border({ width: 1, color: DemoColor.white08 })
    }

    Text(this.showEditor ? 'Done editing' : 'Edit gradient…')
      .fontSize(14)
      .fontColor(DemoColor.accentSoft)
      .margin({ top: 4 })
      .onClick(() => {
        if (this.showEditor) {
          this.commitGradient();
          this.showEditor = false;
          this.redrawGradientPreview();
          this.scheduleRender();
        } else {
          this.showEditor = true;
          this.redrawGradientPreview();
        }
      })

    if (this.showEditor) {
      this.gradientEditor()
    }

    Row() {
      Text('Absolute Stroke width')
        .fontSize(13)
        .fontColor(DemoColor.white70)
      Blank()
      Toggle({ type: ToggleType.Switch, isOn: this.absoluteStroke })
        .selectedColor(DemoColor.white35)
        .onChange((v: boolean) => {
          this.absoluteStroke = v;
          this.scheduleRender();
        })
    }
    .width('100%')

    SharedSlider({
      title: 'Stroke',
      valueText: `${this.strokePt.toFixed(1)}pt`,
      value: this.strokePt,
      min: 0.5,
      max: 5,
      step: 0.1,
      onChange: (v: number) => {
        this.strokePt = v;
        this.scheduleRender();
      },
    })
    SharedSlider({
      title: 'Size',
      valueText: `${Math.round(this.sizeVp)}vp`,
      value: this.sizeVp,
      min: 16,
      max: 72,
      step: 1,
      onChange: (v: number) => {
        this.sizeVp = Math.round(v);
        this.scheduleRender();
      },
    })
  }

  @Builder
  gradientEditor() {
    Column({ space: 8 }) {
      Text('Stop 0').fontSize(12).fontColor(DemoColor.white70)
      this.colorRow(0)
      Row() {
        Text('Mid stop').fontSize(13).fontColor(DemoColor.white70)
        Blank()
        Toggle({ type: ToggleType.Switch, isOn: this.useMid })
          .selectedColor(DemoColor.accent)
          .onChange((v: boolean) => {
            this.useMid = v;
            this.redrawGradientPreview();
          })
      }.width('100%')
      if (this.useMid) {
        Text('Stop mid').fontSize(12).fontColor(DemoColor.white70)
        this.colorRow(1)
        SharedSlider({
          title: 'Mid offset',
          valueText: this.midOffset.toFixed(2),
          value: this.midOffset,
          min: 0.05,
          max: 0.95,
          step: 0.05,
          onChange: (v: number) => {
            this.midOffset = v;
            this.redrawGradientPreview();
          },
        })
      }
      Text('Stop 1').fontSize(12).fontColor(DemoColor.white70)
      this.colorRow(2)
      if (this.tintMode === 'linear') {
        SharedSlider({
          title: 'Angle',
          valueText: `${Math.round(this.angle)}°`,
          value: this.angle,
          min: 0,
          max: 360,
          // Continuous like Android — step 15 made the preview jump in chunks.
          step: 1,
          onChange: (v: number) => {
            this.angle = v;
            this.redrawGradientPreview();
          },
        })
      } else {
        SharedSlider({
          title: 'Center X',
          valueText: this.centerX.toFixed(2),
          value: this.centerX,
          min: 0,
          max: 1,
          step: 0.05,
          onChange: (v: number) => {
            this.centerX = v;
          },
        })
        SharedSlider({
          title: 'Center Y',
          valueText: this.centerY.toFixed(2),
          value: this.centerY,
          min: 0,
          max: 1,
          step: 0.05,
          onChange: (v: number) => {
            this.centerY = v;
          },
        })
        SharedSlider({
          title: 'Radius',
          valueText: this.radius.toFixed(2),
          value: this.radius,
          min: 0.1,
          max: 1.2,
          step: 0.05,
          onChange: (v: number) => {
            this.radius = v;
          },
        })
      }
      Text('Apply gradient')
        .fontSize(14)
        .fontColor(DemoColor.accentSoft)
        .onClick(() => {
          this.commitGradient();
          this.showEditor = false;
          this.scheduleRender();
        })
    }
    .width('100%')
  }

  @Builder
  colorRow(which: number) {
    Row({ space: 10 }) {
      ForEach(PALETTE, (c: number) => {
        Column() {
          Column()
            .width(28)
            .height(28)
            .borderRadius(14)
            .backgroundColor(argbToCss(c))
            .border({
              width: this.stopColor(which) === c ? 3 : 1,
              color: this.stopColor(which) === c ? DemoColor.white : DemoColor.white20,
            })
        }
        .width(40)
        .height(40)
        .justifyContent(FlexAlign.Center)
        .onClick(() => this.pickStop(which, c))
      }, (c: number) => `swatch-${which}-${c >>> 0}-${this.stopColor(which) >>> 0}`)
    }
    .width('100%')
    .padding({ top: 4, bottom: 4 })
  }
}

@Component
struct ControlPanel {
  @Prop tintMode: TintMode = 'original';
  onModeChange: (mode: TintMode) => void = (_m: TintMode) => {};
  @Prop status: string = '';
  @Prop blurb: string = '';
  onReset: () => void = () => {};
  @BuilderParam controls: () => void;

  build() {
    Scroll() {
      Column({ space: 8 }) {
        Row({ space: 8 }) {
          this.modeChip('Original', 'original')
          this.modeChip('Solid', 'solid')
          this.modeChip('Linear', 'linear')
          this.modeChip('Radial', 'radial')
        }
        .width('100%')

        Row() {
          Text('Style as you please')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor(DemoColor.white)
          Blank()
          Text('Reset')
            .fontSize(14)
            .fontColor(DemoColor.white85)
            .onClick(() => this.onReset())
        }
        .width('100%')

        Text(this.blurb)
          .fontSize(13)
          .fontColor(DemoColor.white55)
        Text(this.status)
          .fontSize(12)
          .fontColor(DemoColor.white45)
          .fontFamily('monospace')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        this.controls()
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 16, bottom: 24 })
    }
    .scrollBar(BarState.Off)
    .constraintSize({ maxHeight: '48%' })
    .backgroundColor(DemoColor.panel)
  }

  @Builder
  modeChip(label: string, mode: TintMode) {
    Text(label)
      .fontSize(13)
      .fontColor(this.tintMode === mode ? DemoColor.white : DemoColor.white85)
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      .backgroundColor(this.tintMode === mode ? DemoColor.accent : DemoColor.white08)
      .borderRadius(16)
      .onClick(() => this.onModeChange(mode))
  }
}

@Component
struct SharedSlider {
  @Prop title: string = '';
  @Prop valueText: string = '';
  @Prop value: number = 0;
  @Prop min: number = 0;
  @Prop max: number = 1;
  @Prop step: number = 1;
  onChange: (v: number) => void = (_v: number) => {};

  build() {
    Column() {
      Row() {
        Text(this.title)
          .fontSize(12)
          .fontColor(DemoColor.white70)
        Blank()
        Text(this.valueText)
          .fontSize(12)
          .fontColor(DemoColor.white85)
      }
      .width('100%')
      Slider({ value: this.value, min: this.min, max: this.max, step: this.step })
        .blockColor(DemoColor.white)
        .selectedColor(DemoColor.accent)
        .trackColor(DemoColor.white20)
        .onChange((v: number) => this.onChange(v))
    }
    .width('100%')
  }
}

function argbToCss(argb: number): string {
  const u = argb >>> 0;
  const r = (u >>> 16) & 0xff;
  const g = (u >>> 8) & 0xff;
  const b = u & 0xff;
  return `#${r.toString(16).padStart(2, '0')}${g.toString(16).padStart(2, '0')}${b.toString(16).padStart(2, '0')}`;
}

function hsvToArgb(hue: number, sat: number, value: number): number {
  const h = (((hue % 360) + 360) % 360) / 60;
  const c = value * sat;
  const x = c * (1 - Math.abs(h % 2 - 1));
  const m = value - c;
  let r1 = 0;
  let g1 = 0;
  let b1 = 0;
  const sector = Math.floor(h);
  if (sector === 0) {
    r1 = c; g1 = x; b1 = 0;
  } else if (sector === 1) {
    r1 = x; g1 = c; b1 = 0;
  } else if (sector === 2) {
    r1 = 0; g1 = c; b1 = x;
  } else if (sector === 3) {
    r1 = 0; g1 = x; b1 = c;
  } else if (sector === 4) {
    r1 = x; g1 = 0; b1 = c;
  } else {
    r1 = c; g1 = 0; b1 = x;
  }
  const r = Math.round((r1 + m) * 255);
  const g = Math.round((g1 + m) * 255);
  const b = Math.round((b1 + m) * 255);
  return (0xFF << 24) | (r << 16) | (g << 8) | b;
}
