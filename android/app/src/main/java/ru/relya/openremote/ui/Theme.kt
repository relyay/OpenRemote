package ru.relya.openremote.ui

import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext

/** Xbox green seeds the scheme where the wallpaper cannot (Android 11 and older). */
private val LightScheme = lightColorScheme(
    primary = Color(0xFF1B6D24),
    onPrimary = Color.White,
    primaryContainer = Color(0xFFA3F69C),
    onPrimaryContainer = Color(0xFF002204),
    secondary = Color(0xFF52634F),
    secondaryContainer = Color(0xFFD5E8CF),
    onSecondaryContainer = Color(0xFF101F10),
)

private val DarkScheme = darkColorScheme(
    primary = Color(0xFF88D982),
    onPrimary = Color(0xFF00390A),
    primaryContainer = Color(0xFF005313),
    onPrimaryContainer = Color(0xFFA3F69C),
    secondary = Color(0xFFB9CCB4),
    secondaryContainer = Color(0xFF3B4B39),
    onSecondaryContainer = Color(0xFFD5E8CF),
)

/** Fixed Xbox face colors. They name the buttons, so they do not follow the theme. */
object FaceColors {
    val A = Color(0xFF3FAE49)
    val B = Color(0xFFE5352F)
    val X = Color(0xFF2F7BE5)
    val Y = Color(0xFFF2C21B)
}

@Composable
fun OpenRemoteTheme(content: @Composable () -> Unit) {
    val dark = isSystemInDarkTheme()
    val scheme = when {
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> {
            val context = LocalContext.current
            if (dark) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
        }
        dark -> DarkScheme
        else -> LightScheme
    }
    MaterialTheme(colorScheme = scheme, content = content)
}
