package ru.relya.openremote

import android.app.Application
import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel

enum class Screen { Connect, Scanner, Shell, Pad }

/** Everything that must outlive a configuration change: the link, the layouts and where the user is. */
class AppModel(app: Application) : AndroidViewModel(app) {
    private val prefs = app.getSharedPreferences("openremote", Context.MODE_PRIVATE)

    val settings = Settings(prefs)
    val session = Session(prefs)
    val layout = LayoutStore(prefs)
    val library = LayoutLibrary(prefs)
    val haptics = Haptics(app, settings)
    val controller = ControllerReader(settings)

    var scanning by mutableStateOf(false)
    var showPad by mutableStateOf(false)
        private set

    /** True when the pad was opened to edit a layout, so closing it saves and returns home. */
    var editSession by mutableStateOf(false)
        private set
    private var activeCustom: String? = null
    private var activePreset: Preset? = null

    val screen: Screen
        get() = when {
            session.playing && showPad -> Screen.Pad
            session.playing -> Screen.Shell
            scanning -> Screen.Scanner
            else -> Screen.Connect
        }

    fun connect(host: String? = null, port: String? = null) {
        host?.let { session.host = it }
        port?.let { session.port = it }
        scanning = false
        session.connect()
    }

    fun disconnect() {
        showPad = false
        session.disconnect()
    }

    fun play(preset: Preset) {
        layout.install(preset.data)
        activePreset = preset
        activeCustom = null
        open(edit = false)
    }

    fun play(item: UserLayout) {
        layout.install(item.data)
        activeCustom = item.id
        activePreset = null
        open(edit = false)
    }

    fun edit(preset: Preset) {
        layout.install(preset.data)
        activePreset = preset
        activeCustom = library.find(app().getString(preset.nameRes))?.id
        open(edit = true)
    }

    fun edit(item: UserLayout) {
        layout.install(item.data)
        activeCustom = item.id
        activePreset = null
        open(edit = true)
    }

    fun create(name: String) {
        layout.install(Preset.Standard.data)
        val item = library.add(name.trim().ifEmpty { app().getString(R.string.untitled) }, layout.data)
        activeCustom = item.id
        activePreset = null
        open(edit = true)
    }

    /** Called by the hold-to-close button. Edits are saved; play changes are saved when there are any. */
    fun closePad() {
        if (layout.changed || editSession) storeActive()
        session.releasePad()
        layout.editing = false
        layout.selected = null
        editSession = false
        showPad = false
    }

    fun import(text: String): Boolean {
        val (name, data) = LayoutXml.decode(text) ?: return false
        library.add(name.ifEmpty { app().getString(R.string.untitled) }, data)
        return true
    }

    fun export(item: UserLayout) = LayoutXml.encode(item.name, item.data)

    private fun open(edit: Boolean) {
        editSession = edit
        layout.editing = edit
        showPad = true
    }

    /** Saves the pad into the layout it came from. An edited preset becomes a saved layout of the same name. */
    private fun storeActive() {
        val baked = layout.bake()
        activeCustom?.let {
            library.update(it, baked)
            return
        }
        val preset = activePreset ?: return
        val name = app().getString(preset.nameRes)
        val existing = library.find(name)
        if (existing != null) {
            library.update(existing.id, baked)
            activeCustom = existing.id
        } else {
            activeCustom = library.add(name, baked).id
        }
    }

    private fun app() = getApplication<Application>()

    override fun onCleared() {
        session.close()
    }
}
