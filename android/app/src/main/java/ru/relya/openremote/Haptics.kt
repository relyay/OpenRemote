package ru.relya.openremote

import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import kotlin.math.roundToInt

/** A short tick for presses. Strength follows the settings slider where the motor allows it. */
class Haptics(context: Context, private val settings: Settings) {
    private val vibrator: Vibrator? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            context.getSystemService(VibratorManager::class.java)?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            context.getSystemService(Vibrator::class.java)
        }

    fun tick() {
        val v = vibrator ?: return
        if (!settings.haptics || !v.hasVibrator()) return
        val amount = settings.hapticIntensity
        if (amount <= 0.02) return
        val amplitude = if (v.hasAmplitudeControl()) {
            (amount * 255).roundToInt().coerceIn(1, 255)
        } else {
            VibrationEffect.DEFAULT_AMPLITUDE
        }
        v.vibrate(VibrationEffect.createOneShot(TICK_MS, amplitude))
    }

    private companion object {
        const val TICK_MS = 12L
    }
}
