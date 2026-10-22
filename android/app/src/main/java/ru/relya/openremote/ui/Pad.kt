package ru.relya.openremote.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.drag
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.displayCutout
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChange
import androidx.compose.ui.layout.layout
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import ru.relya.openremote.AppModel
import ru.relya.openremote.Controls
import ru.relya.openremote.PadSnapshot
import ru.relya.openremote.R
import ru.relya.openremote.deadzone

@Composable
fun PadScreen(model: AppModel) {
    val layout = model.layout
    // The system back gesture is easy to trigger from a pad edge. Only the hold button leaves.
    BackHandler { }

    val scheme = MaterialTheme.colorScheme
    Box(
        Modifier
            .fillMaxSize()
            .background(Brush.verticalGradient(listOf(scheme.surfaceContainer, scheme.surface))),
    ) {
        BoxWithConstraints(
            Modifier
                .fillMaxSize()
                .windowInsetsPadding(WindowInsets.displayCutout),
        ) {
            val w = maxWidth
            val h = maxHeight
            SideEffect { layout.remember(w.value.toDouble(), h.value.toDouble()) }
            for (id in Controls.ids) {
                if (id !in layout.data.hidden) Placed(model, id, id, w, h)
            }
            for (node in layout.data.extras) {
                Placed(model, node.id, node.kind, w, h)
            }
        }

        Box(
            Modifier
                .windowInsetsPadding(WindowInsets.displayCutout)
                .padding(start = 12.dp, top = 8.dp),
        ) {
            HoldToExitButton(
                icon = if (model.editSession) Icons.Filled.Check else Icons.Filled.Close,
                label = stringResource(if (model.editSession) R.string.done else R.string.close),
                seconds = model.settings.holdTimeout,
                onExit = model::closePad,
            )
        }

        if (layout.editing) {
            EditToolbar(
                model,
                Modifier
                    .align(Alignment.BottomCenter)
                    .windowInsetsPadding(WindowInsets.displayCutout)
                    .padding(bottom = 12.dp),
            )
        }
    }
}

/** Places a control with its center at the slot. In edit mode the whole control drags. */
@Composable
private fun Placed(model: AppModel, id: String, kind: String, w: Dp, h: Dp) {
    val layout = model.layout
    val slot = layout.slot(id, w.value.toDouble(), h.value.toDouble())
    val editing = layout.editing
    val scale by rememberUpdatedState(slot.scale.toFloat())

    val edit = if (!editing) Modifier else Modifier.pointerInput(id) {
        awaitEachGesture {
            val down = awaitFirstDown(requireUnconsumed = false)
            layout.beginDrag(id)
            drag(down.id) { change ->
                // Positions are in the scaled control's space. Convert back to canvas dp.
                val d = change.positionChange() * scale
                layout.dragBy(id, (d.x / density).toDouble(), (d.y / density).toDouble())
                change.consume()
            }
        }
    }
    val outline = if (layout.selected == id) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outline

    Box(
        Modifier
            .centeredAt(w * slot.x.toFloat(), h * slot.y.toFloat())
            .graphicsLayer {
                scaleX = slot.scale.toFloat()
                scaleY = slot.scale.toFloat()
            }
            .then(edit),
    ) {
        Control(model, kind, enabled = !editing)
        if (editing) {
            Box(
                Modifier
                    .matchParentSize()
                    .border(2.dp, outline, RoundedCornerShape(14.dp)),
            )
        }
    }
}

/** Lays the content out at its own size with its center on (x, y) of the parent. */
private fun Modifier.centeredAt(x: Dp, y: Dp) = layout { measurable, constraints ->
    val placeable = measurable.measure(constraints.copy(minWidth = 0, minHeight = 0))
    layout(placeable.width, placeable.height) {
        placeable.place(x.roundToPx() - placeable.width / 2, y.roundToPx() - placeable.height / 2)
    }
}

@Composable
private fun Control(model: AppModel, kind: String, enabled: Boolean) {
    val session = model.session
    val pad = session.pad
    val haptics = model.haptics

    @Composable
    fun button(label: String, bit: Int, circle: Boolean = true, tint: androidx.compose.ui.graphics.Color? = null) =
        PadButton(
            label = label,
            down = pad.pressed(bit),
            enabled = enabled,
            circle = circle,
            tint = tint,
            onChange = { down ->
                if (down) haptics.tick()
                session.setButton(bit, down)
            },
        )

    @Composable
    fun trigger(left: Boolean) = PadButton(
        label = if (left) "LT" else "RT",
        down = (if (left) pad.lt else pad.rt) > 0.5,
        enabled = enabled,
        onChange = { down ->
            if (down) haptics.tick()
            session.setTrigger(left, if (down) 1.0 else 0.0)
        },
    )

    @Composable
    fun stick(left: Boolean) {
        val bit = if (left) PadSnapshot.L3 else PadSnapshot.R3
        val settings = model.settings
        PadStick(
            x = if (left) pad.lx else pad.rx,
            y = if (left) pad.ly else pad.ry,
            clicked = pad.pressed(bit),
            enabled = enabled,
            clickTimeout = settings.stickClickTimeout,
            shape = { x, y -> deadzone(x, y, settings.stickDeadzone, settings.stickCurve) },
            onMove = { x, y -> if (left) session.setLeft(x, y) else session.setRight(x, y) },
            onClick = { down ->
                if (down) haptics.tick()
                session.setButton(bit, down)
            },
            onTouch = haptics::tick,
            label = stringResource(if (left) R.string.left_stick else R.string.right_stick),
        )
    }

    when (kind) {
        "lt" -> trigger(left = true)
        "rt" -> trigger(left = false)
        "lb" -> button("LB", PadSnapshot.LB)
        "rb" -> button("RB", PadSnapshot.RB)
        "dpad" -> PadDpad(
            hatX = pad.hatX,
            hatY = pad.hatY,
            enabled = enabled,
            onChange = { x, y ->
                if ((x != 0 || y != 0) && (x != session.pad.hatX || y != session.pad.hatY)) haptics.tick()
                session.setHat(x, y)
            },
            label = stringResource(R.string.dpad),
        )
        "y" -> button("Y", PadSnapshot.Y, tint = FaceColors.Y)
        "x" -> button("X", PadSnapshot.X, tint = FaceColors.X)
        "b" -> button("B", PadSnapshot.B, tint = FaceColors.B)
        "a" -> button("A", PadSnapshot.A, tint = FaceColors.A)
        "ls" -> stick(left = true)
        "rs" -> stick(left = false)
        "l3" -> button("L3", PadSnapshot.L3)
        "r3" -> button("R3", PadSnapshot.R3)
        "back" -> button("Back", PadSnapshot.BACK, circle = false)
        "start" -> button("Start", PadSnapshot.START, circle = false)
        "guide" -> PadButton(
            label = "Guide",
            down = pad.pressed(PadSnapshot.GUIDE),
            enabled = enabled,
            icon = GuideIcon,
            onChange = { down ->
                if (down) haptics.tick()
                session.setButton(PadSnapshot.GUIDE, down)
            },
        )
    }
}

@Composable
fun controlName(kind: String): String = when (kind) {
    "ls" -> stringResource(R.string.left_stick)
    "rs" -> stringResource(R.string.right_stick)
    "dpad" -> stringResource(R.string.dpad)
    "back" -> "Back"
    "start" -> "Start"
    "guide" -> "Guide"
    else -> kind.uppercase()
}

/** Floating toolbar for the layout editor: size of the selection, add, remove, reset. */
@Composable
private fun EditToolbar(model: AppModel, modifier: Modifier) {
    val layout = model.layout
    var adding by remember { mutableStateOf(false) }
    Surface(
        shape = CircleShape,
        color = MaterialTheme.colorScheme.surfaceContainerHigh,
        shadowElevation = 6.dp,
        tonalElevation = 3.dp,
        modifier = modifier.widthIn(max = 640.dp),
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
        ) {
            val id = layout.selected
            if (id != null) {
                Text(
                    controlName(layout.kind(id)),
                    style = MaterialTheme.typography.labelLarge,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.widthIn(max = 120.dp),
                )
                Slider(
                    value = layout.slot(id).scale.toFloat(),
                    onValueChange = { layout.setScale(id, it.toDouble()) },
                    valueRange = 0.45f..2f,
                    modifier = Modifier
                        .padding(horizontal = 8.dp)
                        .width(180.dp),
                )
            } else {
                Text(
                    stringResource(R.string.edit_hint),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier
                        .widthIn(max = 320.dp)
                        .padding(end = 8.dp),
                )
            }
            Box {
                IconButton(onClick = { adding = true }) {
                    Icon(Icons.Filled.Add, contentDescription = stringResource(R.string.add_control))
                }
                DropdownMenu(expanded = adding, onDismissRequest = { adding = false }) {
                    Controls.ids.sortedBy { it }.forEach { kind ->
                        DropdownMenuItem(
                            text = { Text(controlName(kind)) },
                            onClick = {
                                adding = false
                                layout.add(kind)
                            },
                        )
                    }
                }
            }
            if (id != null) {
                IconButton(onClick = {
                    release(model, layout.kind(id))
                    layout.remove(id)
                }) {
                    Icon(Icons.Filled.Delete, contentDescription = stringResource(R.string.remove_control))
                }
            }
            IconButton(onClick = layout::reset) {
                Icon(Icons.Filled.Refresh, contentDescription = stringResource(R.string.reset_layout))
            }
        }
    }
}

/** A removed control must not leave its input held on the computer. */
private fun release(model: AppModel, kind: String) {
    val s = model.session
    when (kind) {
        "lt" -> s.setTrigger(true, 0.0)
        "rt" -> s.setTrigger(false, 0.0)
        "ls" -> {
            s.setLeft(0.0, 0.0)
            s.setButton(PadSnapshot.L3, false)
        }
        "rs" -> {
            s.setRight(0.0, 0.0)
            s.setButton(PadSnapshot.R3, false)
        }
        "dpad" -> s.setHat(0, 0)
        else -> buttonBits[kind]?.let { s.setButton(it, false) }
    }
}

private val buttonBits = mapOf(
    "a" to PadSnapshot.A, "b" to PadSnapshot.B, "x" to PadSnapshot.X, "y" to PadSnapshot.Y,
    "lb" to PadSnapshot.LB, "rb" to PadSnapshot.RB, "back" to PadSnapshot.BACK, "start" to PadSnapshot.START,
    "guide" to PadSnapshot.GUIDE, "l3" to PadSnapshot.L3, "r3" to PadSnapshot.R3,
)
