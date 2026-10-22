package ru.relya.openremote

import android.content.SharedPreferences
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.edit

/** Tuning shared by the pad screen and the settings tab. Each value is clamped on read. */
class Settings(private val prefs: SharedPreferences) {
    var haptics by pref(KEY_HAPTICS, DEFAULT_HAPTICS)
    var hapticIntensity by pref(KEY_INTENSITY, DEFAULT_INTENSITY, 0.05..1.0)
    var holdTimeout by pref(KEY_HOLD, DEFAULT_HOLD, 0.2..2.0)
    var stickClickTimeout by pref(KEY_STICK_CLICK, DEFAULT_STICK_CLICK, 0.05..0.8)
    var stickDeadzone by pref(KEY_DEADZONE, DEFAULT_DEADZONE, 0.0..0.4)
    var stickCurve by pref(KEY_CURVE, DEFAULT_CURVE, 1.0..3.0)

    fun resetDefaults() {
        haptics = DEFAULT_HAPTICS
        hapticIntensity = DEFAULT_INTENSITY
        holdTimeout = DEFAULT_HOLD
        stickClickTimeout = DEFAULT_STICK_CLICK
        stickDeadzone = DEFAULT_DEADZONE
        stickCurve = DEFAULT_CURVE
    }

    private fun pref(key: String, default: Boolean) = object {
        private val state = mutableStateOf(prefs.getBoolean(key, default))
        operator fun getValue(thisRef: Any?, property: Any?) = state.value
        operator fun setValue(thisRef: Any?, property: Any?, value: Boolean) {
            state.value = value
            prefs.edit { putBoolean(key, value) }
        }
    }

    private fun pref(key: String, default: Double, range: ClosedFloatingPointRange<Double>) = object {
        private val state = mutableDoubleStateOf(
            prefs.getFloat(key, default.toFloat()).toDouble().coerceIn(range),
        )
        operator fun getValue(thisRef: Any?, property: Any?) = state.doubleValue
        operator fun setValue(thisRef: Any?, property: Any?, value: Double) {
            val clamped = value.coerceIn(range)
            state.doubleValue = clamped
            prefs.edit { putFloat(key, clamped.toFloat()) }
        }
    }

    companion object {
        const val DEFAULT_HAPTICS = true
        const val DEFAULT_INTENSITY = 1.0
        const val DEFAULT_HOLD = 0.7
        const val DEFAULT_STICK_CLICK = 0.16
        const val DEFAULT_DEADZONE = 0.14
        const val DEFAULT_CURVE = 1.0

        private const val KEY_HAPTICS = "haptics"
        private const val KEY_INTENSITY = "hapticIntensity"
        private const val KEY_HOLD = "holdTimeout"
        private const val KEY_STICK_CLICK = "stickClickTimeout"
        private const val KEY_DEADZONE = "stickDeadzone"
        private const val KEY_CURVE = "stickCurve"
    }
}
