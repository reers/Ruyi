package io.github.reers.ruyidemo

import android.graphics.Bitmap
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
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
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.conflate
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.withContext
import kotlin.coroutines.coroutineContext
import kotlin.math.roundToInt

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            MaterialTheme(colorScheme = darkColorScheme()) {
                DemoScreen(engineVersion = Ruyi.version())
            }
        }
    }
}

private data class IconItem(val name: String, val svg: String)

private data class RenderRequest(
    val icons: List<IconItem>,
    val sizeDp: Float,
    val strokePt: Float,
    val hue: Float,
    val absoluteStroke: Boolean,
)

@Composable
private fun DemoScreen(engineVersion: String) {
    val context = LocalContext.current
    val density = LocalDensity.current.density

    var icons by remember { mutableStateOf<List<IconItem>>(emptyList()) }
    var bitmaps by remember { mutableStateOf<Map<String, Bitmap>>(emptyMap()) }
    var status by remember { mutableStateOf("loading…") }

    var sizeDp by remember { mutableFloatStateOf(40f) }
    var strokePt by remember { mutableFloatStateOf(2f) }
    var hue by remember { mutableFloatStateOf(0f) }
    var absoluteStroke by remember { mutableStateOf(true) }

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
        status = if (icons.isEmpty()) {
            "no icons in assets"
        } else {
            "ready · Ruyi / ThorVG $engineVersion"
        }
    }

    // Real-time: render as slider moves. conflate keeps only the latest request
    // while a frame is in flight (no "wait until finger up", no backlog).
    LaunchedEffect(Unit) {
        snapshotFlow {
            RenderRequest(icons, sizeDp, strokePt, hue, absoluteStroke)
        }
            .distinctUntilChanged()
            .conflate()
            .collectLatest { req ->
                if (req.icons.isEmpty()) return@collectLatest

                val argb = hsvToArgb(req.hue, 0.75f, 1f)
                val options = Ruyi.Options(
                    sizeDp = req.sizeDp,
                    color = argb,
                    strokeWidth = req.strokePt,
                    absoluteStrokeWidth = req.absoluteStroke,
                    referenceSize = 24f,
                    density = density,
                )
                val rendered = withContext(Dispatchers.Default) {
                    buildMap {
                        for (item in req.icons) {
                            coroutineContext.ensureActive()
                            val bmp = Ruyi.image(item.svg, options)
                            if (bmp != null) put(item.name, bmp)
                        }
                    }
                }
                bitmaps = rendered
                val mode = if (req.absoluteStroke) "abs" else "rel"
                status =
                    "ok · ${rendered.size}/${req.icons.size} · ${req.sizeDp.roundToInt()}dp · stroke ${"%.1f".format(req.strokePt)} ($mode) · ThorVG $engineVersion"
            }
    }

    val iconDisplayDp = minOf(sizeDp, 76f)

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

        Box(
            Modifier
                .fillMaxWidth()
                .background(Color(0xFF1C1C1C)),
        ) {
            Column(
                Modifier
                    .fillMaxWidth()
                    .navigationBarsPadding()
                    .padding(horizontal = 20.dp, vertical = 16.dp),
            ) {
                Text(
                    text = "Ruyi Android Demo",
                    color = Color.White,
                    fontSize = 22.sp,
                    fontWeight = FontWeight.Bold,
                )
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    text = "Compose UI · Ruyi.image → Bitmap",
                    color = Color.White.copy(alpha = 0.55f),
                    fontSize = 13.sp,
                )
                Spacer(modifier = Modifier.height(6.dp))
                Text(
                    text = status,
                    color = Color(0xFF8BD989),
                    fontSize = 12.sp,
                    fontFamily = FontFamily.Monospace,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(16.dp),
                )

                Spacer(modifier = Modifier.height(14.dp))
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    Text(
                        text = "Absolute Stroke width",
                        color = Color.White.copy(alpha = 0.7f),
                        fontSize = 13.sp,
                    )
                    Switch(
                        checked = absoluteStroke,
                        onCheckedChange = { absoluteStroke = it },
                        colors = SwitchDefaults.colors(
                            checkedThumbColor = Color.White,
                            checkedTrackColor = Color.White.copy(alpha = 0.35f),
                            uncheckedThumbColor = Color.White.copy(alpha = 0.7f),
                            uncheckedTrackColor = Color.White.copy(alpha = 0.15f),
                        ),
                    )
                }

                Spacer(modifier = Modifier.height(8.dp))
                SliderRow(
                    title = "Hue",
                    valueText = "${hue.roundToInt()}°",
                    value = hue,
                    range = 0f..360f,
                    onChange = { hue = it },
                )
                SliderRow(
                    title = "Stroke",
                    valueText = "${"%.1f".format(strokePt)}pt",
                    value = strokePt,
                    range = 0.5f..5f,
                    onChange = { strokePt = it },
                )
                SliderRow(
                    title = "Size",
                    valueText = "${sizeDp.roundToInt()}dp",
                    value = sizeDp,
                    range = 16f..72f,
                    onChange = { sizeDp = it },
                )
            }
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
