package io.github.reers.ruyidemo

import android.graphics.Bitmap
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.reers.ruyi.Ruyi
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.conflate
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.withContext
import kotlin.math.roundToInt

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            MaterialTheme(colorScheme = darkColorScheme()) {
                DemoRoot(engineVersion = Ruyi.version())
            }
        }
    }
}

private enum class TintMode { Original, Solid, Linear, Radial }

private data class IconItem(val name: String, val svg: String)

@Composable
private fun DemoRoot(engineVersion: String) {
    val context = LocalContext.current
    var icons by remember { mutableStateOf<List<IconItem>>(emptyList()) }
    var tintMode by remember { mutableStateOf(TintMode.Original) }

    LaunchedEffect(Unit) {
        icons = withContext(Dispatchers.IO) {
            context.assets.list("icons")
                ?.filter { it.endsWith(".svg") }
                ?.sorted()
                ?.map { name ->
                    IconItem(
                        name = name.removeSuffix(".svg"),
                        svg = context.assets.open("icons/$name").bufferedReader().use { it.readText() },
                    )
                }
                .orEmpty()
        }
    }

    // Hard remount per mode so Solid never inherits Gradient render backlog.
    key(tintMode) {
        when (tintMode) {
            TintMode.Original -> OriginalWorkspace(icons, engineVersion, tintMode) { tintMode = it }
            TintMode.Solid -> SolidWorkspace(icons, engineVersion, tintMode) { tintMode = it }
            TintMode.Linear, TintMode.Radial ->
                GradientWorkspace(icons, engineVersion, tintMode) { tintMode = it }
        }
    }
}

@Composable
private fun ModePicker(selected: TintMode, onSelect: (TintMode) -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .horizontalScroll(rememberScrollState()),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        TintMode.entries.forEach { mode ->
            FilterChip(
                selected = selected == mode,
                onClick = { onSelect(mode) },
                label = { Text(mode.name) },
                colors = FilterChipDefaults.filterChipColors(
                    selectedContainerColor = Color(0xFFF25973),
                    selectedLabelColor = Color.White,
                    containerColor = Color.White.copy(alpha = 0.08f),
                    labelColor = Color.White.copy(alpha = 0.85f),
                ),
            )
        }
    }
}

@Composable
private fun OriginalWorkspace(
    icons: List<IconItem>,
    engineVersion: String,
    tintMode: TintMode,
    onMode: (TintMode) -> Unit,
) {
    val density = LocalDensity.current.density
    var sizeDp by remember { mutableFloatStateOf(40f) }
    var bitmaps by remember { mutableStateOf<Map<String, Bitmap>>(emptyMap()) }
    var status by remember { mutableStateOf("ready") }

    LaunchedEffect(icons) {
        snapshotFlow { sizeDp.roundToInt().toFloat() }
            .distinctUntilChanged()
            .conflate()
            .collectLatest { rasterSize ->
                if (icons.isEmpty()) return@collectLatest
                val options = Ruyi.Options(sizeDp = rasterSize, density = density)
                bitmaps = renderIcons(icons, options)
                status = "ok · original · ${rasterSize.roundToInt()}dp · ThorVG $engineVersion"
            }
    }

    DemoScaffold(
        tintMode = tintMode,
        onMode = onMode,
        status = status,
        icons = icons,
        bitmaps = bitmaps,
        displaySizeDp = sizeDp,
        onReset = { sizeDp = 40f },
        blurb = "Original SVG colors and strokes — only size is adjustable.",
    ) {
        SliderRow("Size", "${sizeDp.roundToInt()}dp", sizeDp, 16f..72f) { sizeDp = it }
    }
}

@Composable
private fun SolidWorkspace(
    icons: List<IconItem>,
    engineVersion: String,
    tintMode: TintMode,
    onMode: (TintMode) -> Unit,
) {
    val density = LocalDensity.current.density
    var sizeDp by remember { mutableFloatStateOf(40f) }
    var strokePt by remember { mutableFloatStateOf(2f) }
    var hue by remember { mutableFloatStateOf(0f) }
    var absoluteStroke by remember { mutableStateOf(false) }
    var bitmaps by remember { mutableStateOf<Map<String, Bitmap>>(emptyMap()) }
    var status by remember { mutableStateOf("ready") }

    data class Req(
        val size: Float,
        val stroke: Float,
        val hue: Float,
        val abs: Boolean,
    )

    LaunchedEffect(icons) {
        snapshotFlow {
            Req(
                size = sizeDp.roundToInt().toFloat(),
                stroke = (strokePt * 10f).roundToInt() / 10f,
                hue = hue.roundToInt().toFloat(),
                abs = absoluteStroke,
            )
        }
            .distinctUntilChanged()
            .conflate()
            .collectLatest { req ->
                if (icons.isEmpty()) return@collectLatest
                val options = Ruyi.Options(
                    sizeDp = req.size,
                    color = hsvToArgb(req.hue, 0.75f, 1f),
                    strokeWidth = req.stroke,
                    absoluteStrokeWidth = req.abs,
                    density = density,
                )
                bitmaps = renderIcons(icons, options)
                val mode = if (req.abs) "abs" else "rel"
                status =
                    "ok · solid · ${req.size.roundToInt()}dp · stroke ${"%.1f".format(req.stroke)} ($mode) · ThorVG $engineVersion"
            }
    }

    DemoScaffold(
        tintMode = tintMode,
        onMode = onMode,
        status = status,
        icons = icons,
        bitmaps = bitmaps,
        displaySizeDp = sizeDp,
        onReset = {
            sizeDp = 40f
            strokePt = 2f
            hue = 0f
            absoluteStroke = false
        },
        blurb = "Solid tint with live size, color and stroke controls.",
    ) {
        AbsoluteStrokeRow(absoluteStroke) { absoluteStroke = it }
        SliderRow("Hue", "${hue.roundToInt()}°", hue, 0f..360f) { hue = it }
        SliderRow("Stroke", "${"%.1f".format(strokePt)}pt", strokePt, 0.5f..5f) { strokePt = it }
        SliderRow("Size", "${sizeDp.roundToInt()}dp", sizeDp, 16f..72f) { sizeDp = it }
    }
}

@Composable
private fun GradientWorkspace(
    icons: List<IconItem>,
    engineVersion: String,
    tintMode: TintMode,
    onMode: (TintMode) -> Unit,
) {
    val density = LocalDensity.current.density
    var sizeDp by remember { mutableFloatStateOf(40f) }
    var strokePt by remember { mutableFloatStateOf(2f) }
    var absoluteStroke by remember { mutableStateOf(false) }
    var stop0 by remember { mutableIntStateOf(0xFFF25973.toInt()) }
    var stop1 by remember { mutableIntStateOf(0xFFFFBF33.toInt()) }
    var stop2 by remember { mutableIntStateOf(0xFF598CFF.toInt()) }
    var useMid by remember { mutableStateOf(true) }
    var midOffset by remember { mutableFloatStateOf(0.5f) }
    var angle by remember { mutableFloatStateOf(90f) }
    var centerX by remember { mutableFloatStateOf(0.5f) }
    var centerY by remember { mutableFloatStateOf(0.5f) }
    var radius by remember { mutableFloatStateOf(0.71f) }
    var showEditor by remember { mutableStateOf(false) }
    var bitmaps by remember { mutableStateOf<Map<String, Bitmap>>(emptyMap()) }
    var status by remember { mutableStateOf("ready") }

    // Live stroke/size; gradient params commit when editor closes (or initial).
    data class LiveReq(val size: Float, val stroke: Float, val abs: Boolean, val editorOpen: Boolean)
    var committedGradient by remember {
        mutableStateOf(buildGradient(tintMode, stop0, stop1, stop2, useMid, midOffset, angle, centerX, centerY, radius))
    }

    LaunchedEffect(icons, tintMode, committedGradient) {
        snapshotFlow {
            LiveReq(
                size = sizeDp.roundToInt().toFloat(),
                stroke = (strokePt * 10f).roundToInt() / 10f,
                abs = absoluteStroke,
                editorOpen = showEditor,
            )
        }
            .distinctUntilChanged()
            .conflate()
            .collectLatest { req ->
                if (icons.isEmpty() || req.editorOpen) return@collectLatest
                val options = Ruyi.Options(
                    sizeDp = req.size,
                    gradient = committedGradient,
                    strokeWidth = req.stroke,
                    absoluteStrokeWidth = req.abs,
                    density = density,
                )
                bitmaps = renderIcons(icons, options)
                status =
                    "ok · ${tintMode.name.lowercase()} · ${req.size.roundToInt()}dp · ThorVG $engineVersion"
            }
    }

    DemoScaffold(
        tintMode = tintMode,
        onMode = onMode,
        status = status,
        icons = icons,
        bitmaps = bitmaps,
        displaySizeDp = sizeDp,
        onReset = {
            sizeDp = 40f
            strokePt = 2f
            absoluteStroke = false
            stop0 = 0xFFF25973.toInt()
            stop1 = 0xFFFFBF33.toInt()
            stop2 = 0xFF598CFF.toInt()
            useMid = true
            midOffset = 0.5f
            angle = 90f
            centerX = 0.5f
            centerY = 0.5f
            radius = 0.71f
            committedGradient =
                buildGradient(tintMode, stop0, stop1, stop2, useMid, midOffset, angle, centerX, centerY, radius)
        },
        blurb = "Gradient tint. Edit stops in the panel; stroke/size stay live.",
    ) {
        GradientPreview(tintMode, stop0, stop1, stop2, useMid, midOffset, angle, centerX, centerY, radius)
        TextButton(onClick = { showEditor = !showEditor }) {
            Text(if (showEditor) "Done editing" else "Edit gradient…", color = Color(0xFFF28C99))
        }
        if (showEditor) {
            GradientEditor(
                tintMode = tintMode,
                stop0 = stop0,
                stop1 = stop1,
                stop2 = stop2,
                useMid = useMid,
                midOffset = midOffset,
                angle = angle,
                centerX = centerX,
                centerY = centerY,
                radius = radius,
                onStop0 = { stop0 = it },
                onStop1 = { stop1 = it },
                onStop2 = { stop2 = it },
                onUseMid = { useMid = it },
                onMidOffset = { midOffset = it },
                onAngle = { angle = it },
                onCenterX = { centerX = it },
                onCenterY = { centerY = it },
                onRadius = { radius = it },
                onCommit = {
                    committedGradient = buildGradient(
                        tintMode, stop0, stop1, stop2, useMid, midOffset, angle, centerX, centerY, radius,
                    )
                    showEditor = false
                },
            )
        }
        AbsoluteStrokeRow(absoluteStroke) { absoluteStroke = it }
        SliderRow("Stroke", "${"%.1f".format(strokePt)}pt", strokePt, 0.5f..5f) { strokePt = it }
        SliderRow("Size", "${sizeDp.roundToInt()}dp", sizeDp, 16f..72f) { sizeDp = it }
    }
}

@Composable
private fun DemoScaffold(
    tintMode: TintMode,
    onMode: (TintMode) -> Unit,
    status: String,
    icons: List<IconItem>,
    bitmaps: Map<String, Bitmap>,
    displaySizeDp: Float,
    onReset: () -> Unit,
    blurb: String,
    controls: @Composable () -> Unit,
) {
    val iconDisplayDp = minOf(displaySizeDp, 76f)
    Column(
        Modifier
            .fillMaxSize()
            .background(Color(0xFF292929))
            .statusBarsPadding(),
    ) {
        LazyVerticalGrid(
            columns = GridCells.Adaptive(minSize = 100.dp),
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth()
                .padding(12.dp),
            contentPadding = PaddingValues(8.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            items(icons, key = { it.name }) { item ->
                val bmp = bitmaps[item.name]
                Box(
                    modifier = Modifier
                        .size(88.dp)
                        .background(Color(0xFF3A3A3A), RoundedCornerShape(12.dp))
                        .padding(6.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    if (bmp != null) {
                        Image(
                            bitmap = bmp.asImageBitmap(),
                            contentDescription = item.name,
                            modifier = Modifier.size(iconDisplayDp.dp),
                        )
                    }
                }
            }
        }

        Column(
            Modifier
                .fillMaxWidth()
                .background(Color(0xFF1C1C1C))
                .navigationBarsPadding()
                .padding(horizontal = 20.dp, vertical = 16.dp)
                .verticalScroll(rememberScrollState()),
        ) {
            ModePicker(tintMode, onMode)
            Spacer(Modifier.height(12.dp))
            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    "Style as you please",
                    color = Color.White,
                    fontSize = 22.sp,
                    fontWeight = FontWeight.Bold,
                )
                TextButton(onClick = onReset) {
                    Text("Reset", color = Color.White.copy(alpha = 0.85f))
                }
            }
            Text(blurb, color = Color.White.copy(alpha = 0.55f), fontSize = 13.sp)
            Spacer(Modifier.height(6.dp))
            Text(
                status,
                color = Color(0xFF8BD989),
                fontSize = 12.sp,
                fontFamily = FontFamily.Monospace,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            Spacer(Modifier.height(12.dp))
            controls()
        }
    }
}

@Composable
private fun AbsoluteStrokeRow(value: Boolean, onChange: (Boolean) -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text("Absolute Stroke width", color = Color.White.copy(alpha = 0.7f), fontSize = 13.sp)
        Switch(
            checked = value,
            onCheckedChange = onChange,
            colors = SwitchDefaults.colors(
                checkedThumbColor = Color.White,
                checkedTrackColor = Color.White.copy(alpha = 0.35f),
                uncheckedThumbColor = Color.White.copy(alpha = 0.7f),
                uncheckedTrackColor = Color.White.copy(alpha = 0.15f),
            ),
        )
    }
}

@Composable
private fun GradientPreview(
    tintMode: TintMode,
    stop0: Int,
    stop1: Int,
    stop2: Int,
    useMid: Boolean,
    midOffset: Float,
    angle: Float,
    centerX: Float,
    centerY: Float,
    radius: Float,
) {
    val colors = buildList {
        add(Color(stop0))
        if (useMid) add(Color(stop1))
        add(Color(stop2))
    }
    val stops = buildList {
        add(0f)
        if (useMid) add(midOffset)
        add(1f)
    }
    val brush = if (tintMode == TintMode.Linear) {
        val ends = Ruyi.GradientTint.linearAngle(angle)
        Brush.linearGradient(
            colorStops = stops.zip(colors).toTypedArray(),
            start = androidx.compose.ui.geometry.Offset(ends[0] * 200f, ends[1] * 56f),
            end = androidx.compose.ui.geometry.Offset(ends[2] * 200f, ends[3] * 56f),
        )
    } else {
        Brush.radialGradient(
            colorStops = stops.zip(colors).toTypedArray(),
            center = androidx.compose.ui.geometry.Offset(centerX * 200f, centerY * 56f),
            radius = 40f * radius,
        )
    }
    Box(
        Modifier
            .fillMaxWidth()
            .height(if (tintMode == TintMode.Linear) 28.dp else 56.dp)
            .background(brush, RoundedCornerShape(8.dp)),
    )
}

@Composable
private fun GradientEditor(
    tintMode: TintMode,
    stop0: Int,
    stop1: Int,
    stop2: Int,
    useMid: Boolean,
    midOffset: Float,
    angle: Float,
    centerX: Float,
    centerY: Float,
    radius: Float,
    onStop0: (Int) -> Unit,
    onStop1: (Int) -> Unit,
    onStop2: (Int) -> Unit,
    onUseMid: (Boolean) -> Unit,
    onMidOffset: (Float) -> Unit,
    onAngle: (Float) -> Unit,
    onCenterX: (Float) -> Unit,
    onCenterY: (Float) -> Unit,
    onRadius: (Float) -> Unit,
    onCommit: () -> Unit,
) {
    val palette = listOf(
        0xFFF25973.toInt(),
        0xFFFFBF33.toInt(),
        0xFF598CFF.toInt(),
        0xFF59CC8C.toInt(),
        0xFFFFFFFF.toInt(),
        0xFFB366F2.toInt(),
    )
    Column(modifier = Modifier.fillMaxWidth()) {
        Text("Stop 0", color = Color.White.copy(alpha = 0.7f), fontSize = 12.sp)
        ColorSwatches(palette, stop0, onStop0)
        Row(
            Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text("Mid stop", color = Color.White.copy(alpha = 0.7f), fontSize = 13.sp)
            Switch(checked = useMid, onCheckedChange = onUseMid)
        }
        if (useMid) {
            Text("Stop mid", color = Color.White.copy(alpha = 0.7f), fontSize = 12.sp)
            ColorSwatches(palette, stop1, onStop1)
            SliderRow("Mid offset", "%.2f".format(midOffset), midOffset, 0.05f..0.95f, onMidOffset)
        }
        Text("Stop 1", color = Color.White.copy(alpha = 0.7f), fontSize = 12.sp)
        ColorSwatches(palette, stop2, onStop2)
        if (tintMode == TintMode.Linear) {
            SliderRow("Angle", "${angle.roundToInt()}°", angle, 0f..360f, onAngle)
        } else {
            SliderRow("Center X", "%.2f".format(centerX), centerX, 0f..1f, onCenterX)
            SliderRow("Center Y", "%.2f".format(centerY), centerY, 0f..1f, onCenterY)
            SliderRow("Radius", "%.2f".format(radius), radius, 0.1f..1.2f, onRadius)
        }
        TextButton(onClick = onCommit) { Text("Apply gradient", color = Color(0xFFF28C99)) }
    }
}

@Composable
private fun ColorSwatches(palette: List<Int>, selected: Int, onSelect: (Int) -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 6.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        palette.forEach { color ->
            Box(
                Modifier
                    .size(28.dp)
                    .background(Color(color), CircleShape)
                    .then(
                        if (color == selected) Modifier.border(2.dp, Color.White, CircleShape)
                        else Modifier,
                    )
                    .clickable { onSelect(color) },
            )
        }
    }
}

@Composable
private fun SliderRow(
    title: String,
    valueText: String,
    value: Float,
    range: ClosedFloatingPointRange<Float>,
    onChange: (Float) -> Unit,
) {
    Column(modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            Text(title, color = Color.White.copy(alpha = 0.7f), fontSize = 12.sp)
            Text(valueText, color = Color.White.copy(alpha = 0.85f), fontSize = 12.sp)
        }
        Slider(
            value = value,
            onValueChange = onChange,
            valueRange = range,
            colors = SliderDefaults.colors(
                thumbColor = Color.White,
                activeTrackColor = Color.White.copy(alpha = 0.85f),
                inactiveTrackColor = Color.White.copy(alpha = 0.2f),
            ),
        )
    }
}

private suspend fun renderIcons(icons: List<IconItem>, options: Ruyi.Options): Map<String, Bitmap> =
    withContext(Dispatchers.Default) {
        coroutineScope {
            icons
                .map { item -> async { item.name to Ruyi.image(item.svg, options) } }
                .awaitAll()
                .mapNotNull { (name, bmp) -> bmp?.let { name to it } }
                .toMap()
        }
    }

private fun buildGradient(
    tintMode: TintMode,
    stop0: Int,
    stop1: Int,
    stop2: Int,
    useMid: Boolean,
    midOffset: Float,
    angle: Float,
    centerX: Float,
    centerY: Float,
    radius: Float,
): Ruyi.GradientTint {
    val stops = buildList {
        add(Ruyi.GradientStop(0f, stop0))
        if (useMid) add(Ruyi.GradientStop(midOffset, stop1))
        add(Ruyi.GradientStop(1f, stop2))
    }
    return if (tintMode == TintMode.Linear) {
        Ruyi.GradientTint.linear(stops, angle)
    } else {
        Ruyi.GradientTint.Radial(
            stops = stops,
            centerX = centerX,
            centerY = centerY,
            radius = radius,
        )
    }
}

private fun hsvToArgb(hue: Float, sat: Float, value: Float): Int {
    val h = ((hue % 360f) + 360f) % 360f / 60f
    val c = value * sat
    val x = c * (1f - kotlin.math.abs(h % 2f - 1f))
    val mVal = value - c
    val (r1, g1, b1) = when (h.toInt()) {
        0 -> Triple(c, x, 0f)
        1 -> Triple(x, c, 0f)
        2 -> Triple(0f, c, x)
        3 -> Triple(0f, x, c)
        4 -> Triple(x, 0f, c)
        else -> Triple(c, 0f, x)
    }
    val r = ((r1 + mVal) * 255f).roundToInt().coerceIn(0, 255)
    val g = ((g1 + mVal) * 255f).roundToInt().coerceIn(0, 255)
    val b = ((b1 + mVal) * 255f).roundToInt().coerceIn(0, 255)
    return (0xFF shl 24) or (r shl 16) or (g shl 8) or b
}
