import { Ruyi, RuyiOptions } from '@reers/ruyi';
import { image } from '@kit.ImageKit';
import { display } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { buffer } from '@kit.ArkTS';

interface IconItem {
  name: string;
  svg: string;
}

interface RenderRequest {
  icons: IconItem[];
  sizeVp: number;
  strokePt: number;
  hue: number;
  absoluteStroke: boolean;
}

@Entry
@Component
struct Index {
  @State status: string = 'loading…';
  @State icons: IconItem[] = [];
  @State pixelMaps: Record<string, image.PixelMap> = {};
  @State sizeVp: number = 40;
  @State strokePt: number = 2;
  @State hue: number = 0;
  @State absoluteStroke: boolean = true;
  @State engineVersion: string = '';
  private density: number = 3;
  /** Latest desired params (conflate). */
  private pending: RenderRequest | undefined = undefined;
  private rendering: boolean = false;

  aboutToAppear(): void {
    try {
      const d = display.getDefaultDisplaySync();
      this.density = d.densityDPI / 160;
    } catch (_e) {
      this.density = 3;
    }
    // Engine lazy-inits inside Ruyi on first render (no engineInit).
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

  /** Push latest slider state; at most one native batch in flight. */
  private scheduleRender(): void {
    this.pending = {
      icons: this.icons,
      sizeVp: this.sizeVp,
      strokePt: this.strokePt,
      hue: this.hue,
      absoluteStroke: this.absoluteStroke,
    };
    if (!this.rendering) {
      this.drainRender();
    }
  }

  private async drainRender(): Promise<void> {
    if (this.rendering) {
      return;
    }
    this.rendering = true;
    try {
      while (this.pending !== undefined) {
        const req = this.pending;
        this.pending = undefined;
        if (req.icons.length === 0) {
          continue;
        }
        await this.renderRequest(req);
      }
    } finally {
      this.rendering = false;
      if (this.pending !== undefined) {
        this.drainRender();
      }
    }
  }

  private async renderRequest(req: RenderRequest): Promise<void> {
    const argb = hsvToArgb(req.hue, 0.75, 1);
    const svgs: string[] = req.icons.map((i: IconItem) => i.svg);
    const options = new RuyiOptions(
      req.sizeVp,
      argb,
      req.strokePt,
      req.absoluteStroke,
      24,
      this.density,
    );

    const maps = await Ruyi.imageBatch(svgs, options);

    // Release previous PixelMaps to avoid GPU/CPU memory buildup while sliding.
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
    for (let i = 0; i < req.icons.length; i++) {
      const pm = maps[i];
      if (pm) {
        next[req.icons[i].name] = pm;
        ok++;
      }
    }
    this.pixelMaps = next;
    const mode = req.absoluteStroke ? 'abs' : 'rel';
    this.status =
      `ok · ${ok}/${req.icons.length} · ${Math.round(req.sizeVp)}vp · stroke ${req.strokePt.toFixed(1)} (${mode}) · ThorVG ${this.engineVersion}`;
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
        }, (item: IconItem) => item.name)
      }
      .columnsTemplate('1fr 1fr 1fr')
      .columnsGap(12)
      .rowsGap(12)
      .padding(12)
      .layoutWeight(1)
      .width('100%')
      .backgroundColor('#292929')

      Column({ space: 8 }) {
        Text('Ruyi Demo')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
        Text('ArkTS · @reers/ruyi → PixelMap')
          .fontSize(13)
          .fontColor('#FFFFFF8C')
        Text(this.status)
          .fontSize(12)
          .fontColor('#8BD989')
          .fontFamily('monospace')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

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
        .margin({ top: 8 })

        this.sliderRow('Hue', `${Math.round(this.hue)}°`, this.hue, 0, 360, 1, (v: number) => {
          this.hue = v;
          this.scheduleRender();
        })
        this.sliderRow('Stroke', `${this.strokePt.toFixed(1)}pt`, this.strokePt, 0.5, 5, 0.1, (v: number) => {
          this.strokePt = v;
          this.scheduleRender();
        })
        this.sliderRow('Size', `${Math.round(this.sizeVp)}vp`, this.sizeVp, 16, 72, 1, (v: number) => {
          this.sizeVp = Math.round(v);
          this.scheduleRender();
        })
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 16, bottom: 24 })
      .backgroundColor('#1C1C1C')
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#292929')
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
