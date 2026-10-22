package ru.relya.openremote.ui

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Home
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.compositeOver
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.PointerInputChange
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.abs
import kotlin.math.hypot

/**
 * Calls [onChange] with true as soon as a finger lands and false when the
 * last finger lifts. There is no touch slop and no long-press wait, so a
 * quick tap still reaches the game.
 */
@Composable
private fun Modifier.press(enabled: Boolean, onChange: (Boolean) -> Unit): Modifier {
    if (!enabled) return this
    val latest by rememberUpdatedState(onChange)
    return pointerInput(Unit) {
        awaitEachGesture {
            awaitFirstDown(requireUnconsumed = false).consume()
            latest(true)
            try {
                do {
                    val event = awaitPointerEvent()
                    event.changes.forEach(PointerInputChange::consume)
                } while (event.changes.any { it.pressed })
            } finally {
                latest(false)
            }
        }
    }
}

/** A round or pill pad button. [tint] colors face buttons; null uses the theme. */
@Composable
fun PadButton(
    label: String,
    down: Boolean,
    enabled: Boolean,
    onChange: (Boolean) -> Unit,
    circle: Boolean = true,
    tint: Color? = null,
    icon: ImageVector? = null,
) {
    val scheme = MaterialTheme.colorScheme
    val container by animateColorAsState(
        when {
            tint != null && down -> tint
            tint != null -> tint.copy(alpha = 0.32f).compositeOver(scheme.surfaceContainerHigh)
            down -> scheme.primary
            else -> scheme.surfaceContainerHighest
        },
        animationSpec = tween(60),
        label = "button",
    )
    val content = when {
        tint == FaceColors.Y && down -> Color.Black
        tint != null && down -> Color.White
        tint != null -> tint
        down -> scheme.onPrimary
        else -> scheme.onSurface
    }
    Surface(
        shape = if (circle) CircleShape else RoundedCornerShape(50),
        color = container,
        contentColor = content,
        shadowElevation = if (down) 0.dp else 2.dp,
        modifier = Modifier
            .semantics {
                role = Role.Button
                contentDescription = label
            }
            .press(enabled, onChange),
    ) {
        Box(
            contentAlignment = Alignment.Center,
            modifier = if (circle) {
                Modifier.size(64.dp)
            } else {
                Modifier.defaultMinSize(minWidth = 82.dp, minHeight = 50.dp).padding(horizontal = 12.dp)
            },
        ) {
            if (icon != null) {
                Icon(icon, contentDescription = null)
            } else {
                Text(label, style = MaterialTheme.typography.titleMedium)
            }
        }
    }
}

/**
 * An analog stick. Resting a finger without moving presses the stick click
 * (L3 or R3) after [clickTimeout] seconds; a quick tap clicks once.
 */
@Composable
fun PadStick(
    x: Double,
    y: Double,
    clicked: Boolean,
    enabled: Boolean,
    clickTimeout: Double,
    shape: (Double, Double) -> Pair<Double, Double>,
    onMove: (Double, Double) -> Unit,
    onClick: (Boolean) -> Unit,
    onTouch: () -> Unit,
    label: String,
) {
    val scope = rememberCoroutineScope()
    val move by rememberUpdatedState(onMove)
    val click by rememberUpdatedState(onClick)
    val touch by rememberUpdatedState(onTouch)
    val shaper by rememberUpdatedState(shape)
    val timeout by rememberUpdatedState(clickTimeout)
    val scheme = MaterialTheme.colorScheme
    val knob = if (clicked) scheme.primary else scheme.inverseSurface
    val ring = scheme.outlineVariant
    val base = scheme.surfaceContainerHigh

    val input = if (!enabled) Modifier else Modifier.pointerInput(Unit) {
        awaitEachGesture {
            val down = awaitFirstDown(requireUnconsumed = false)
            down.consume()
            val origin = down.position
            val slop = 16.dp.toPx()
            var armed = true
            var held = false

            fun emit(p: Offset) {
                val travel = maxOf(1f, size.width * 0.32f)
                var dx = p.x - size.width / 2f
                var dy = p.y - size.height / 2f
                val mag = hypot(dx, dy)
                if (mag > travel) {
                    dx = dx / mag * travel
                    dy = dy / mag * travel
                }
                val (sx, sy) = shaper(dx / travel.toDouble(), dy / travel.toDouble())
                move(sx, sy)
            }

            touch()
            emit(down.position)
            val timer = scope.launch {
                delay((timeout * 1000).toLong())
                if (armed) {
                    armed = false
                    held = true
                    click(true)
                }
            }
            try {
                while (true) {
                    val event = awaitPointerEvent()
                    val change = event.changes.firstOrNull { it.id == down.id } ?: continue
                    if (!change.pressed) break
                    if (armed && (change.position - origin).getDistance() > slop) {
                        armed = false
                        timer.cancel()
                    }
                    emit(change.position)
                    change.consume()
                }
            } finally {
                timer.cancel()
                val tap = armed
                if (tap && !held) click(true)
                if (held || tap) click(false)
                move(0.0, 0.0)
            }
        }
    }

    Canvas(
        modifier = Modifier
            .size(148.dp)
            .semantics { contentDescription = label }
            .then(input),
    ) {
        val r = size.minDimension / 2
        val travel = size.minDimension * 0.32f
        drawCircle(base, r)
        drawCircle(ring, r - 1.dp.toPx(), style = Stroke(2.dp.toPx()))
        drawCircle(
            knob,
            size.minDimension * 0.21f,
            center = center + Offset((x * travel).toFloat(), (y * travel).toFloat()),
        )
    }
}

/** A d-pad. The finger may slide between directions and diagonals without lifting. */
@Composable
fun PadDpad(hatX: Int, hatY: Int, enabled: Boolean, onChange: (Int, Int) -> Unit, label: String) {
    val latest by rememberUpdatedState(onChange)
    val input = if (!enabled) Modifier else Modifier.pointerInput(Unit) {
        fun zone(p: Offset): Pair<Int, Int> {
            val nx = (p.x - size.width / 2f) / maxOf(size.width / 2f, 1f)
            val ny = (p.y - size.height / 2f) / maxOf(size.height / 2f, 1f)
            if (hypot(nx, ny) <= 0.28f) return 0 to 0
            val hx = if (abs(nx) > 0.32f) (if (nx > 0) 1 else -1) else 0
            val hy = if (abs(ny) > 0.32f) (if (ny > 0) 1 else -1) else 0
            return hx to hy
        }
        awaitEachGesture {
            val down = awaitFirstDown(requireUnconsumed = false)
            down.consume()
            zone(down.position).let { (hx, hy) -> latest(hx, hy) }
            try {
                while (true) {
                    val event = awaitPointerEvent()
                    val change = event.changes.firstOrNull { it.id == down.id } ?: continue
                    if (!change.pressed) break
                    zone(change.position).let { (hx, hy) -> latest(hx, hy) }
                    change.consume()
                }
            } finally {
                latest(0, 0)
            }
        }
    }
    Box(
        Modifier
            .size(156.dp)
            .semantics { contentDescription = label }
            .then(input),
    ) {
        DpadArm(hatY < 0, Modifier.align(Alignment.TopCenter).size(40.dp, 58.dp))
        DpadArm(hatY > 0, Modifier.align(Alignment.BottomCenter).size(40.dp, 58.dp))
        DpadArm(hatX < 0, Modifier.align(Alignment.CenterStart).size(58.dp, 40.dp))
        DpadArm(hatX > 0, Modifier.align(Alignment.CenterEnd).size(58.dp, 40.dp))
    }
}

@Composable
private fun DpadArm(active: Boolean, modifier: Modifier) {
    val scheme = MaterialTheme.colorScheme
    val color by animateColorAsState(
        if (active) scheme.primary else scheme.surfaceContainerHighest,
        animationSpec = tween(60),
        label = "arm",
    )
    Surface(shape = RoundedCornerShape(10.dp), color = color, shadowElevation = 2.dp, modifier = modifier) {}
}

/** Guide uses the home glyph: on a real pad it is the home button. */
val GuideIcon = Icons.Filled.Home

/**
 * Leaves the pad only after a hold, so a stray touch in a game cannot.
 * The ring fills over [seconds].
 */
@Composable
fun HoldToExitButton(icon: ImageVector, label: String, seconds: Double, onExit: () -> Unit) {
    val progress = remember { Animatable(0f) }
    val scope = rememberCoroutineScope()
    val exit by rememberUpdatedState(onExit)
    val duration by rememberUpdatedState(seconds)
    Box(
        contentAlignment = Alignment.Center,
        modifier = Modifier
            .size(52.dp)
            .semantics {
                role = Role.Button
                contentDescription = label
            }
            .pointerInput(Unit) {
                awaitEachGesture {
                    awaitFirstDown(requireUnconsumed = false).consume()
                    val started = System.nanoTime()
                    val fill = scope.launch {
                        progress.snapTo(0f)
                        progress.animateTo(1f, tween((duration * 1000).toInt(), easing = LinearEasing))
                    }
                    try {
                        do {
                            val event = awaitPointerEvent()
                        } while (event.changes.any { it.pressed })
                    } finally {
                        fill.cancel()
                        scope.launch { progress.snapTo(0f) }
                        if ((System.nanoTime() - started) / 1e9 >= duration) exit()
                    }
                }
            },
    ) {
        Surface(
            shape = CircleShape,
            color = MaterialTheme.colorScheme.surfaceContainerHighest,
            shadowElevation = 2.dp,
            modifier = Modifier.size(44.dp),
        ) {
            Box(contentAlignment = Alignment.Center, modifier = Modifier.fillMaxSize()) {
                Icon(icon, contentDescription = null)
            }
        }
        CircularProgressIndicator(
            progress = { progress.value },
            strokeWidth = 3.dp,
            trackColor = Color.Transparent,
            modifier = Modifier.size(52.dp),
        )
    }
}
