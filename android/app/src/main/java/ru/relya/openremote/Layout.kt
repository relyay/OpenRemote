package ru.relya.openremote

import android.content.SharedPreferences
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.edit
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

/** Position as a fraction of the pad canvas, plus a size multiplier. */
data class Slot(val x: Double, val y: Double, val scale: Double = 1.0)

/** An extra copy of a control. [kind] is one of [Controls.ids]. */
data class ControlNode(val id: String, val kind: String, val slot: Slot)

object Controls {
    val ids = listOf(
        "lt", "lb", "rt", "rb", "dpad", "y", "x", "b", "a", "ls", "rs", "l3", "r3", "back", "guide", "start",
    )
    val faceIds = setOf("a", "b", "x", "y")
    val centerIds = setOf("back", "guide", "start")
    val defaultHidden = setOf("l3", "r3")

    val defaults: Map<String, Slot> = mapOf(
        "lt" to Slot(0.05, 0.06, 1.75),
        "lb" to Slot(0.16, 0.30, 1.3),
        "rt" to Slot(0.95, 0.06, 1.75),
        "rb" to Slot(0.84, 0.30, 1.3),
        "dpad" to Slot(0.09, 0.64),
        "y" to Slot(0.78, 0.58),
        "x" to Slot(0.72, 0.72),
        "b" to Slot(0.84, 0.72),
        "a" to Slot(0.78, 0.86),
        "ls" to Slot(0.30, 0.82),
        "rs" to Slot(0.70, 0.82),
        "l3" to Slot(0.08, 0.88),
        "r3" to Slot(0.92, 0.88),
        "back" to Slot(0.36, 0.14),
        "guide" to Slot(0.50, 0.14),
        "start" to Slot(0.64, 0.14),
    )

    /** Standard, with the d-pad and sticks moved to the opposite side. */
    val lefty: Map<String, Slot> = defaults.mapValues { (id, slot) ->
        if (id in setOf("dpad", "ls", "rs", "l3", "r3")) slot.copy(x = 1 - slot.x) else slot
    }

    /** Gaps in dp. Fractions of a landscape canvas would stretch the diamond. */
    const val FACE_GAP = 54.0
    const val CENTER_GAP = 96.0
}

fun clampX(v: Double) = v.coerceIn(0.04, 0.96)
fun clampScale(v: Double) = v.coerceIn(0.45, 2.0)

/** A layout as it is stored, exported and installed. */
data class LayoutData(
    val slots: Map<String, Slot>,
    val faceCustom: Boolean,
    val centerCustom: Boolean,
    val hidden: Set<String> = emptySet(),
    val extras: List<ControlNode> = emptyList(),
    val faceOnLeft: Boolean = false,
)

data class UserLayout(val id: String, val name: String, val data: LayoutData)

enum class Preset(val nameRes: Int) {
    Standard(R.string.preset_standard),
    Lefty(R.string.preset_lefty);

    val data: LayoutData
        get() = when (this) {
            Standard -> LayoutData(Controls.defaults, false, false, Controls.defaultHidden)
            Lefty -> LayoutData(Controls.lefty, false, false, Controls.defaultHidden, faceOnLeft = true)
        }
}

/**
 * The live pad arrangement. While the face diamond or the center row is not
 * custom, it is computed from the canvas size in dp, so it keeps its shape on
 * any screen. Dragging one of those controls freezes the group in place.
 */
class LayoutStore(private val prefs: SharedPreferences) {
    var editing by mutableStateOf(false)
    var selected by mutableStateOf<String?>(null)
    var changed by mutableStateOf(false)
        private set
    var data by mutableStateOf(load())
        private set

    private var canvasW = 0.0
    private var canvasH = 0.0

    fun kind(id: String) = data.extras.firstOrNull { it.id == id }?.kind ?: id

    /** The slot to draw. [w] and [h] are the canvas size in dp, or 0 for the stored slot. */
    fun slot(id: String, w: Double = 0.0, h: Double = 0.0): Slot {
        data.extras.firstOrNull { it.id == id }?.let { return it.slot }
        val slot = data.slots[id] ?: Controls.defaults[id] ?: Slot(0.5, 0.5)
        if (w <= 1 || h <= 1) return slot
        val point = when {
            !data.faceCustom && id in Controls.faceIds -> facePoint(id, w, h, data.faceOnLeft)
            !data.centerCustom && id in Controls.centerIds -> centerPoint(id, w, h)
            else -> return slot
        }
        return slot.copy(x = clampX(point.first / w), y = clampX(point.second / h))
    }

    fun remember(w: Double, h: Double) {
        if (w > 1 && h > 1) {
            canvasW = w
            canvasH = h
        }
    }

    fun beginDrag(id: String) {
        if (id in Controls.faceIds && !data.faceCustom) freezeFace()
        if (id in Controls.centerIds && !data.centerCustom) freezeCenter()
        selected = id
    }

    /** Moves by a delta in dp. */
    fun dragBy(id: String, dx: Double, dy: Double) {
        if (canvasW <= 1 || canvasH <= 1) return
        val s = slot(id)
        update(id, s.copy(x = clampX(s.x + dx / canvasW), y = clampX(s.y + dy / canvasH)))
    }

    fun setScale(id: String, value: Double) {
        update(id, slot(id).copy(scale = clampScale(value)))
        selected = id
    }

    fun install(layout: LayoutData) {
        data = layout.copy(slots = Controls.defaults + layout.slots.filterKeys { it in Controls.defaults })
        selected = null
        editing = false
        changed = false
        save()
    }

    fun add(kind: String) {
        if (kind !in Controls.ids) return
        val hidden = kind in data.hidden
        val base = if (hidden) Controls.defaults.getValue(kind) else slot(kind, canvasW, canvasH)
        val index = data.extras.count { it.kind == kind } + if (hidden) 0 else 1
        val nudge = 0.07 * index
        val node = ControlNode(
            id = UUID.randomUUID().toString(),
            kind = kind,
            slot = Slot(
                x = (base.x + nudge).coerceIn(0.08, 0.92),
                y = (base.y + nudge * 0.35).coerceIn(0.1, 0.9),
                scale = base.scale,
            ),
        )
        data = data.copy(extras = data.extras + node)
        selected = node.id
        touched()
    }

    fun remove(id: String) {
        data = if (data.extras.any { it.id == id }) {
            data.copy(extras = data.extras.filterNot { it.id == id })
        } else {
            data.copy(hidden = data.hidden + id)
        }
        if (selected == id) selected = null
        touched()
    }

    fun reset() {
        data = Preset.Standard.data
        selected = null
        touched()
    }

    /** The layout with the computed diamond and center row written out. */
    fun bake(): LayoutData {
        if (!data.faceCustom) freezeFace()
        if (!data.centerCustom) freezeCenter()
        return data
    }

    private fun update(id: String, slot: Slot) {
        data = if (data.extras.any { it.id == id }) {
            data.copy(extras = data.extras.map { if (it.id == id) it.copy(slot = slot) else it })
        } else {
            data.copy(slots = data.slots + (id to slot))
        }
        touched()
    }

    private fun freezeFace() {
        if (canvasW <= 1) return
        val frozen = Controls.faceIds.associateWith { slot(it, canvasW, canvasH) }
        data = data.copy(slots = data.slots + frozen, faceCustom = true)
        save()
    }

    private fun freezeCenter() {
        if (canvasW <= 1) return
        val frozen = Controls.centerIds.associateWith { slot(it, canvasW, canvasH) }
        data = data.copy(slots = data.slots + frozen, centerCustom = true)
        save()
    }

    private fun touched() {
        changed = true
        save()
    }

    private fun load(): LayoutData =
        prefs.getString(KEY, null)?.let { runCatching { LayoutJson.decodeData(JSONObject(it)) }.getOrNull() }
            ?: Preset.Standard.data

    private fun save() {
        prefs.edit { putString(KEY, LayoutJson.encodeData(data).toString()) }
    }

    private companion object {
        const val KEY = "liveLayout"

        /** `onLeft` mirrors the cluster the way Lefty mirrors Standard. */
        fun facePoint(id: String, w: Double, h: Double, onLeft: Boolean): Pair<Double, Double> {
            val cx = w * if (onLeft) 0.10 else 0.90
            val cy = h * 0.66
            val side = if (onLeft) -1 else 1
            val gap = Controls.FACE_GAP
            return when (id) {
                "y" -> cx to cy - gap
                "x" -> cx - side * gap to cy
                "b" -> cx + side * gap to cy
                "a" -> cx to cy + gap
                else -> cx to cy
            }
        }

        /** Kept in dp so the row stays above the middle on a short landscape canvas. */
        fun centerPoint(id: String, w: Double, h: Double): Pair<Double, Double> {
            val ox = w * 0.5
            val oy = minOf(h * 0.14, 52.0)
            return when (id) {
                "back" -> ox - Controls.CENTER_GAP to oy
                "start" -> ox + Controls.CENTER_GAP to oy
                else -> ox to oy
            }
        }
    }
}

/** Saved layouts. Stored as JSON with the same field names as the iOS app. */
class LayoutLibrary(private val prefs: SharedPreferences) {
    var items by mutableStateOf(load())
        private set

    fun add(name: String, data: LayoutData): UserLayout {
        val item = UserLayout(UUID.randomUUID().toString(), uniqueName(name), data)
        items = items + item
        persist()
        return item
    }

    fun update(id: String, data: LayoutData) {
        items = items.map { if (it.id == id) it.copy(data = data) else it }
        persist()
    }

    fun remove(id: String) {
        items = items.filterNot { it.id == id }
        persist()
    }

    fun find(name: String) = items.firstOrNull { it.name == name }

    private fun uniqueName(name: String): String {
        var candidate = name
        var n = 2
        while (items.any { it.name == candidate }) candidate = "$name ${n++}"
        return candidate
    }

    private fun load(): List<UserLayout> {
        val raw = prefs.getString(KEY, null) ?: return emptyList()
        return runCatching {
            val array = JSONArray(raw)
            List(array.length()) { i ->
                val o = array.getJSONObject(i)
                UserLayout(o.getString("id"), o.getString("name"), LayoutJson.decodeData(o))
            }
        }.getOrDefault(emptyList())
    }

    private fun persist() {
        val array = JSONArray()
        for (item in items) {
            array.put(LayoutJson.encodeData(item.data).put("id", item.id).put("name", item.name))
        }
        prefs.edit { putString(KEY, array.toString()) }
    }

    private companion object {
        const val KEY = "layoutLibrary"
    }
}

private object LayoutJson {
    fun encodeData(d: LayoutData): JSONObject {
        val slots = JSONObject()
        for ((id, s) in d.slots) slots.put(id, encodeSlot(s))
        val extras = JSONArray()
        for (e in d.extras) extras.put(JSONObject().put("id", e.id).put("kind", e.kind).put("slot", encodeSlot(e.slot)))
        return JSONObject()
            .put("slots", slots)
            .put("faceCustom", d.faceCustom)
            .put("centerCustom", d.centerCustom)
            .put("hidden", JSONArray(d.hidden.sorted()))
            .put("extras", extras)
            .put("faceOnLeft", d.faceOnLeft)
    }

    fun decodeData(o: JSONObject): LayoutData {
        val slotsJson = o.getJSONObject("slots")
        val slots = slotsJson.keys().asSequence().associateWith { decodeSlot(slotsJson.getJSONObject(it)) }
        val hidden = o.optJSONArray("hidden")?.let { a -> List(a.length()) { a.getString(it) }.toSet() } ?: emptySet()
        val extras = o.optJSONArray("extras")?.let { a ->
            List(a.length()) {
                val e = a.getJSONObject(it)
                ControlNode(e.getString("id"), e.getString("kind"), decodeSlot(e.getJSONObject("slot")))
            }
        } ?: emptyList()
        return LayoutData(
            slots = slots,
            faceCustom = o.optBoolean("faceCustom"),
            centerCustom = o.optBoolean("centerCustom"),
            hidden = hidden,
            extras = extras,
            faceOnLeft = o.optBoolean("faceOnLeft"),
        )
    }

    private fun encodeSlot(s: Slot) = JSONObject().put("x", s.x).put("y", s.y).put("scale", s.scale)

    private fun decodeSlot(o: JSONObject) = Slot(o.getDouble("x"), o.getDouble("y"), o.optDouble("scale", 1.0))
}
