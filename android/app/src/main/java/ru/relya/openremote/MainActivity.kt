package ru.relya.openremote

import android.annotation.SuppressLint
import android.content.Intent
import android.content.pm.ActivityInfo
import android.hardware.input.InputManager
import android.os.Bundle
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.compose.runtime.LaunchedEffect
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import ru.relya.openremote.ui.App
import ru.relya.openremote.ui.OpenRemoteTheme

class MainActivity : ComponentActivity(), InputManager.InputDeviceListener {
    private val model: AppModel by viewModels()
    private val inputManager by lazy { getSystemService(InputManager::class.java) }

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        if (savedInstanceState == null) openLink(intent)
        setContent {
            val screen = model.screen
            val playing = model.session.playing
            LaunchedEffect(screen) { applyScreen(screen) }
            LaunchedEffect(playing) { keepScreenOn(playing) }
            OpenRemoteTheme { App(model) }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        openLink(intent)
    }

    override fun onResume() {
        super.onResume()
        inputManager.registerInputDeviceListener(this, null)
        refreshControllers()
    }

    override fun onPause() {
        inputManager.unregisterInputDeviceListener(this)
        // Leaving the app must not leave a button held on the computer.
        model.controller.reset()
        model.session.releasePad()
        super.onPause()
    }

    // Gamepad keys are taken here, before Compose can use A, B and the d-pad for focus.
    // dispatchKeyEvent is public Activity API; lint flags only ComponentActivity's override.
    @SuppressLint("RestrictedApi")
    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (model.session.playing) {
            model.controller.onKey(event)?.let {
                model.session.applyController(it)
                return true
            }
        }
        return super.dispatchKeyEvent(event)
    }

    override fun dispatchGenericMotionEvent(event: MotionEvent): Boolean {
        if (model.session.playing) {
            model.controller.onMotion(event)?.let {
                model.session.applyController(it)
                return true
            }
        }
        return super.dispatchGenericMotionEvent(event)
    }

    override fun onInputDeviceAdded(deviceId: Int) = refreshControllers()
    override fun onInputDeviceRemoved(deviceId: Int) = refreshControllers()
    override fun onInputDeviceChanged(deviceId: Int) = refreshControllers()

    private fun refreshControllers() {
        val present = inputManager.inputDeviceIds.any { ControllerReader.isGamepad(inputManager.getInputDevice(it)) }
        if (!present) model.controller.reset()
        model.session.setController(present)
    }

    private fun openLink(intent: Intent?) {
        val data = intent?.data?.toString() ?: return
        val (host, port) = ConnectionCode.parse(data) ?: return
        if (model.session.playing) model.disconnect()
        model.connect(host, port)
    }

    /** The pad is a landscape, full-screen surface. Everything else is a portrait app. */
    private fun applyScreen(screen: Screen) {
        val pad = screen == Screen.Pad
        requestedOrientation = if (pad) {
            ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
        } else {
            ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
        }
        val insets = WindowCompat.getInsetsController(window, window.decorView)
        if (pad) {
            insets.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            insets.hide(WindowInsetsCompat.Type.systemBars())
        } else {
            insets.show(WindowInsetsCompat.Type.systemBars())
        }
    }

    private fun keepScreenOn(on: Boolean) {
        if (on) {
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
    }
}
