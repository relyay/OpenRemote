package ru.relya.openremote

import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.roundToInt

/**
 * One full pad snapshot. The server applies the difference, so every frame is complete.
 * Positive stick and hat Y is down, matching the Linux Xbox 360 driver.
 */
data class PadSnapshot(
    val lx: Double = 0.0,
    val ly: Double = 0.0,
    val rx: Double = 0.0,
    val ry: Double = 0.0,
    val lt: Double = 0.0,
    val rt: Double = 0.0,
    val hatX: Int = 0,
    val hatY: Int = 0,
    val buttons: Int = 0,
) {
    fun pressed(bit: Int) = buttons and bit != 0

    fun with(bit: Int, down: Boolean) =
        copy(buttons = if (down) buttons or bit else buttons and bit.inv())

    /** The 14-byte frame described in internal/protocol/protocol.go. */
    fun frame(): ByteArray {
        val out = ByteArray(FRAME_SIZE)
        putAxis(out, 0, lx)
        putAxis(out, 2, ly)
        putAxis(out, 4, rx)
        putAxis(out, 6, ry)
        out[8] = trigger(lt)
        out[9] = trigger(rt)
        out[10] = (buttons and 0xFF).toByte()
        out[11] = (buttons shr 8 and 0xFF).toByte()
        out[12] = hatX.coerceIn(-1, 1).toByte()
        out[13] = hatY.coerceIn(-1, 1).toByte()
        return out
    }

    companion object {
        const val FRAME_SIZE = 14

        const val A = 1 shl 0
        const val B = 1 shl 1
        const val X = 1 shl 2
        const val Y = 1 shl 3
        const val LB = 1 shl 4
        const val RB = 1 shl 5
        const val BACK = 1 shl 6
        const val START = 1 shl 7
        const val GUIDE = 1 shl 8
        const val L3 = 1 shl 9
        const val R3 = 1 shl 10
    }
}

private fun putAxis(out: ByteArray, offset: Int, value: Double) {
    val v = (value * 32767).roundToInt().coerceIn(-32767, 32767)
    out[offset] = (v and 0xFF).toByte()
    out[offset + 1] = (v shr 8 and 0xFF).toByte()
}

private fun trigger(value: Double): Byte =
    (value.coerceIn(0.0, 1.0) * 255).roundToInt().toByte()

/** Radial dead zone, then the response curve. Returns the stick inside the unit circle. */
fun deadzone(x: Double, y: Double, dead: Double, curve: Double): Pair<Double, Double> {
    val mag = hypot(x, y)
    if (mag == 0.0 || mag < dead) return 0.0 to 0.0
    val scaled = min(1.0, (mag - dead) / max(1e-6, 1 - dead))
    val curved = scaled.pow(curve)
    return x * curved / mag to y * curved / mag
}
