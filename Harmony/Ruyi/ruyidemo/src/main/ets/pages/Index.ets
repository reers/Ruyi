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

@Entry
@Component
struct Index {
  @State status: string = 'loading…';
  @State icons: IconItem[] = [];
  @State pixelMaps: Record<string, image.PixelMap> = {};
  @State tintMode: TintMode = 'original';
  @State sizeVp: number = 40;
  @State strokePt: number = 2;
  @State hue: number = 0;
  @State absoluteStroke: boolean = false;
  @State engineVersion: string = '';
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
  private density: number = 3;
  private pending: boolean = false;
  private rendering: boolean = false;
  private workspaceToken: number = 0;

  aboutToAppear(): void {
    try {
      const d = display.getDefaultDisplaySync();
      this.density = d.densityDPI / 160;
    } catch (_e) {
      this.density = 3;
    }
    this.engineVersion = Ruyi.version();
    this.loadIcons().then(() => {
      this.scheduleRender();
    });
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
    this.status = loaded.length === 0
      ? 'no icons in rawfile'
      : `ready · Ruyi / ThorVG ${this.engineVersion}`;
  }

  private setMode(mode: TintMode): void {
    if (this.tintMode === mode) {
      return;
    }
    // Invalidate in-flight work when leaving a workspace (Apple-style isolation).
    this.workspaceToken++;
    this.pending = false;
    this.tintMode = mode;
    this.showEditor = false;
    this.scheduleRender();
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
    const token = this.workspaceToken;
    try {
      while (this.pending) {
        this.pending = false;
        if (this.icons.length === 0 || this.showEditor) {
          continue;
        }
        await this.renderCurrent(token);
        if (token !== this.workspaceToken) {
          break;
        }
      }
    } finally {
      this.rendering = false;
      if (this.pending && token === this.workspaceToken) {
        this.drainRender();
      }
    }
  }

  private buildOptions(): RuyiOptions {
    const size = Math.round(this.sizeVp);
    if (this.tintMode === 'original') {
      return new RuyiOptions(size, undefined, undefined, false, 24, this.density);
    }
    if (this.tintMode === 'solid') {
      return new RuyiOptions(
        size,
        hsvToArgb(this.hue, 0.75, 1),
        this.strokePt,
        this.absoluteStroke,
        24,
        this.density,
      );
    }
    const stops: GradientStop[] = [new GradientStop(0, this.stop0)];
    if (this.useMid) {
      stops.push(new GradientStop(this.midOffset, this.stop1));
    }
    stops.push(new GradientStop(1, this.stop2));
    const gradient = this.tintMode === 'linear'
      ? GradientTint.linearAngle(stops, this.angle)
      : GradientTint.radial(stops, this.centerX, this.centerY, this.radius);
    return new RuyiOptions(
      size,
      undefined,
      this.strokePt,
      this.absoluteStroke,
      24,
      this.density,
      gradient,
    );
  }

  private async renderCurrent(token: number): Promise<void> {
    const options = this.buildOptions();
    const svgs: string[] = this.icons.map((i: IconItem) => i.svg);
    const maps = await Ruyi.imageBatch(svgs, options);
    if (token !== this.workspaceToken) {
      return;
    }

    const old = this.pixelMaps;
    const keys = Object.keys(old);
    for (let i = 0; i < keys.length; i++) {
      try {
        old[keys[i]].release();
      } catch (_e) {
        // ignore
      }
    }

    const next: Record<string, image.PixelMap> = {};
    let ok = 0;
    for (let i = 0; i < this.icons.length; i++) {
      const pm = maps[i];
      if (pm) {
        next[this.icons[i].name] = pm;
        ok++;
      }
    }
    this.pixelMaps = next;
    this.status =
      `ok · ${this.tintMode} · ${ok}/${this.icons.length} · ${Math.round(this.sizeVp)}vp · ThorVG ${this.engineVersion}`;
  }

  private reset(): void {
    this.sizeVp = 40;
    this.strokePt = 2;
    this.hue = 0;
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
    this.scheduleRender();
  }

  @Builder
  modeChip(label: string, mode: TintMode) {
    Text(label)
      .fontSize(13)
      .fontColor(this.tintMode === mode ? Color.White : '#FFFFFFD9')
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      .backgroundColor(this.tintMode === mode ? '#F25973' : '#FFFFFF14')
      .borderRadius(16)
      .onClick(() => this.setMode(mode))
  }

  build() {
    Column() {
      Grid() {
        ForEach(this.icons, (item: IconItem) => {
          GridItem() {
            Column() {
              if (this.pixelMaps[item.name]) {
                Image(this.pixelMaps[item.name])
                  .width(Math.min(this.sizeVp, 76))
                  .height(Math.min(this.sizeVp, 76))
                  .objectFit(ImageFit.Contain)
              }
            }
            .width(88)
            .height(88)
            .justifyContent(FlexAlign.Center)
            .backgroundColor('#3A3A3A')
            .borderRadius(12)
            .padding(6)
          }
        }, (item: IconItem) => `${this.tintMode}-${item.name}`)
      }
      .columnsTemplate('1fr 1fr 1fr')
      .columnsGap(12)
      .rowsGap(12)
      .padding(12)
      .layoutWeight(1)
      .width('100%')
      .backgroundColor('#292929')

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
              .fontColor(Color.White)
            Blank()
            Text('Reset')
              .fontSize(14)
              .fontColor('#FFFFFFD9')
              .onClick(() => this.reset())
          }
          .width('100%')

          Text(this.blurb())
            .fontSize(13)
            .fontColor('#FFFFFF8C')
          Text(this.status)
            .fontSize(12)
            .fontColor('#8BD989')
            .fontFamily('monospace')
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')

          if (this.tintMode === 'solid') {
            this.sliderRow('Hue', `${Math.round(this.hue)}°`, this.hue, 0, 360, 1, (v: number) => {
              this.hue = v;
              this.scheduleRender();
            })
          }

          if (this.tintMode === 'linear' || this.tintMode === 'radial') {
            Text(this.showEditor ? 'Done editing' : 'Edit gradient…')
              .fontSize(14)
              .fontColor('#F28C99')
              .onClick(() => {
                if (this.showEditor) {
                  this.showEditor = false;
                  this.scheduleRender();
                } else {
                  this.showEditor = true;
                }
              })
            if (this.showEditor) {
              this.gradientEditor()
            }
          }

          if (this.tintMode !== 'original') {
            Row() {
              Text('Absolute Stroke width')
                .fontSize(13)
                .fontColor('#FFFFFFB3')
              Blank()
              Toggle({ type: ToggleType.Switch, isOn: this.absoluteStroke })
                .selectedColor('#FFFFFF59')
                .onChange((v: boolean) => {
                  this.absoluteStroke = v;
                  this.scheduleRender();
                })
            }
            .width('100%')
            this.sliderRow('Stroke', `${this.strokePt.toFixed(1)}pt`, this.strokePt, 0.5, 5, 0.1, (v: number) => {
              this.strokePt = v;
              this.scheduleRender();
            })
          }

          this.sliderRow('Size', `${Math.round(this.sizeVp)}vp`, this.sizeVp, 16, 72, 1, (v: number) => {
            this.sizeVp = Math.round(v);
            this.scheduleRender();
          })
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 16, bottom: 24 })
      }
      .scrollBar(BarState.Off)
      .constraintSize({ maxHeight: '48%' })
      .backgroundColor('#1C1C1C')
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#292929')
  }

  private blurb(): string {
    if (this.tintMode === 'original') {
      return 'Original SVG colors and strokes — only size is adjustable.';
    }
    if (this.tintMode === 'solid') {
      return 'Solid tint with live size, color and stroke controls.';
    }
    return 'Gradient tint. Edit stops in the panel; stroke/size stay live.';
  }

  @Builder
  gradientEditor() {
    Column({ space: 6 }) {
      Text('Stop 0').fontSize(12).fontColor('#FFFFFFB3')
      this.colorRow((c: number) => {
        this.stop0 = c;
      }, this.stop0)
      Row() {
        Text('Mid stop').fontSize(13).fontColor('#FFFFFFB3')
        Blank()
        Toggle({ type: ToggleType.Switch, isOn: this.useMid })
          .onChange((v: boolean) => {
            this.useMid = v;
          })
      }.width('100%')
      if (this.useMid) {
        Text('Stop mid').fontSize(12).fontColor('#FFFFFFB3')
        this.colorRow((c: number) => {
          this.stop1 = c;
        }, this.stop1)
        this.sliderRow('Mid offset', this.midOffset.toFixed(2), this.midOffset, 0.05, 0.95, 0.05, (v: number) => {
          this.midOffset = v;
        })
      }
      Text('Stop 1').fontSize(12).fontColor('#FFFFFFB3')
      this.colorRow((c: number) => {
        this.stop2 = c;
      }, this.stop2)
      if (this.tintMode === 'linear') {
        this.sliderRow('Angle', `${Math.round(this.angle)}°`, this.angle, 0, 360, 15, (v: number) => {
          this.angle = v;
        })
      } else {
        this.sliderRow('Center X', this.centerX.toFixed(2), this.centerX, 0, 1, 0.05, (v: number) => {
          this.centerX = v;
        })
        this.sliderRow('Center Y', this.centerY.toFixed(2), this.centerY, 0, 1, 0.05, (v: number) => {
          this.centerY = v;
        })
        this.sliderRow('Radius', this.radius.toFixed(2), this.radius, 0.1, 1.2, 0.05, (v: number) => {
          this.radius = v;
        })
      }
      Text('Apply gradient')
        .fontSize(14)
        .fontColor('#F28C99')
        .onClick(() => {
          this.showEditor = false;
          this.scheduleRender();
        })
    }
    .width('100%')
  }

  @Builder
  colorRow(onPick: (c: number) => void, selected: number) {
    Row({ space: 8 }) {
      ForEach([0xFFF25973, 0xFFFFBF33, 0xFF598CFF, 0xFF59CC8C, 0xFFFFFFFF, 0xFFB366F2], (c: number) => {
        Column()
          .width(28)
          .height(28)
          .borderRadius(14)
          .backgroundColor(argbToCss(c))
          .border({ width: selected === c ? 2 : 0, color: Color.White })
          .onClick(() => onPick(c))
      }, (c: number) => `${c}`)
    }
    .width('100%')
  }

  @Builder
  sliderRow(
    title: string,
    valueText: string,
    value: number,
    min: number,
    max: number,
    step: number,
    onChange: (v: number) => void,
  ) {
    Column() {
      Row() {
        Text(title)
          .fontSize(12)
          .fontColor('#FFFFFFB3')
        Blank()
        Text(valueText)
          .fontSize(12)
          .fontColor('#FFFFFFD9')
      }
      .width('100%')
      Slider({ value: value, min: min, max: max, step: step })
        .blockColor(Color.White)
        .selectedColor('#FFFFFFD9')
        .trackColor('#FFFFFF33')
        .onChange(onChange)
    }
    .width('100%')
  }
}

function argbToCss(argb: number): string {
  const r = (argb >> 16) & 0xff;
  const g = (argb >> 8) & 0xff;
  const b = argb & 0xff;
  return `rgb(${r},${g},${b})`;
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
