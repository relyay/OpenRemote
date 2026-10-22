package ru.relya.openremote

import android.view.InputDevice
import android.view.KeyEvent
import android.view.MotionEvent

/**
 * Turns key and motion events from a gamepad attached to the phone into pad
 * snapshots. Android reports buttons as key codes and sticks, triggers and
 * the d-pad hat as axes of one MotionEvent.
 */
class ControllerReader(private val settings: Settings) {
    private var buttons = 0
    private var keyHatX = 0
    private var keyHatY = 0
    private var axes = PadSnapshot()

    /** Returns the new snapshot, or null when the event did not come from a gamepad. */
    fun onKey(event: KeyEvent): PadSnapshot? {
        if (!isGamepad(event.device)) return null
        val down = when (event.action) {
            KeyEvent.ACTION_DOWN -> true
            KeyEvent.ACTION_UP -> false
            else -> return null
        }
        when (event.keyCode) {
            KeyEvent.KEYCODE_DPAD_LEFT -> keyHatX = if (down) -1 else if (keyHatX < 0) 0 else keyHatX
            KeyEvent.KEYCODE_DPAD_RIGHT -> keyHatX = if (down) 1 else if (keyHatX > 0) 0 else keyHatX
            KeyEvent.KEYCODE_DPAD_UP -> keyHatY = if (down) -1 else if (keyHatY < 0) 0 else keyHatY
            KeyEvent.KEYCODE_DPAD_DOWN -> keyHatY = if (down) 1 else if (keyHatY > 0) 0 else keyHatY
            else -> {
                val bit = buttonBit(event.keyCode) ?: return null
                buttons = if (down) buttons or bit else buttons and bit.inv()
            }
        }
        return snapshot()
    }

    fun onMotion(event: MotionEvent): PadSnapshot? {
        if (!isGamepad(event.device) || event.action != MotionEvent.ACTION_MOVE) return null
        val dead = settings.stickDeadzone
        val curve = settings.stickCurve
        val (lx, ly) = deadzone(axis(event, MotionEvent.AXIS_X), axis(event, MotionEvent.AXIS_Y), dead, curve)
        val (rx, ry) = deadzone(axis(event, MotionEvent.AXIS_Z), axis(event, MotionEvent.AXIS_RZ), dead, curve)
        val lt = maxOf(axis(event, MotionEvent.AXIS_LTRIGGER), axis(event, MotionEvent.AXIS_BRAKE))
        val rt = maxOf(axis(event, MotionEvent.AXIS_RTRIGGER), axis(event, MotionEvent.AXIS_GAS))
        val hx = axis(event, MotionEvent.AXIS_HAT_X)
        val hy = axis(event, MotionEvent.AXIS_HAT_Y)
        axes = PadSnapshot(
            lx = lx, ly = ly, rx = rx, ry = ry, lt = lt, rt = rt,
            hatX = if (hx < -0.5) -1 else if (hx > 0.5) 1 else 0,
            hatY = if (hy < -0.5) -1 else if (hy > 0.5) 1 else 0,
        )
        return snapshot()
    }

    fun reset() {
        buttons = 0
        keyHatX = 0
        keyHatY = 0
        axes = PadSnapshot()
    }

    private fun snapshot() = axes.copy(
        buttons = buttons,
        hatX = if (axes.hatX != 0) axes.hatX else keyHatX,
        hatY = if (axes.hatY != 0) axes.hatY else keyHatY,
    )

    private fun axis(event: MotionEvent, axis: Int): Double {
        val range = event.device?.getMotionRange(axis, event.source) ?: return 0.0
        val value = event.getAxisValue(axis)
        return if (kotlin.math.abs(value) > range.flat) value.toDouble() else 0.0
    }

    private fun buttonBit(code: Int): Int? = when (code) {
        KeyEvent.KEYCODE_BUTTON_A -> PadSnapshot.A
        KeyEvent.KEYCODE_BUTTON_B -> PadSnapshot.B
        KeyEvent.KEYCODE_BUTTON_X -> PadSnapshot.X
        KeyEvent.KEYCODE_BUTTON_Y -> PadSnapshot.Y
        KeyEvent.KEYCODE_BUTTON_L1 -> PadSnapshot.LB
        KeyEvent.KEYCODE_BUTTON_R1 -> PadSnapshot.RB
        KeyEvent.KEYCODE_BUTTON_SELECT, KeyEvent.KEYCODE_BACK -> PadSnapshot.BACK
        KeyEvent.KEYCODE_BUTTON_START, KeyEvent.KEYCODE_MENU -> PadSnapshot.START
        KeyEvent.KEYCODE_BUTTON_MODE -> PadSnapshot.GUIDE
        KeyEvent.KEYCODE_BUTTON_THUMBL -> PadSnapshot.L3
        KeyEvent.KEYCODE_BUTTON_THUMBR -> PadSnapshot.R3
        else -> null
    }

    companion object {
        fun isGamepad(device: InputDevice?): Boolean {
            if (device == null || device.isVirtual) return false
            val sources = device.sources
            return sources and InputDevice.SOURCE_GAMEPAD == InputDevice.SOURCE_GAMEPAD ||
                sources and InputDevice.SOURCE_JOYSTICK == InputDevice.SOURCE_JOYSTICK
        }
    }
}
