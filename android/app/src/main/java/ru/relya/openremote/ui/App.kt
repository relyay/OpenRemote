package ru.relya.openremote.ui

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.runtime.Composable
import ru.relya.openremote.AppModel
import ru.relya.openremote.Screen

@Composable
fun App(model: AppModel) {
    AnimatedContent(
        targetState = model.screen,
        transitionSpec = { fadeIn() togetherWith fadeOut() },
        label = "screen",
    ) { screen ->
        when (screen) {
            Screen.Connect -> ConnectScreen(model)
            Screen.Scanner -> ScannerScreen(model)
            Screen.Shell -> ShellScreen(model)
            Screen.Pad -> PadScreen(model)
        }
    }
}
