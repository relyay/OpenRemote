package ru.relya.openremote.ui

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.outlined.Home
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExtendedFloatingActionButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Slider
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLocale
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import kotlin.math.roundToInt
import ru.relya.openremote.AppModel
import ru.relya.openremote.Preset
import ru.relya.openremote.R
import ru.relya.openremote.Settings
import ru.relya.openremote.UserLayout

private enum class Tab(val label: Int, val selected: androidx.compose.ui.graphics.vector.ImageVector, val idle: androidx.compose.ui.graphics.vector.ImageVector) {
    Home(R.string.home, Icons.Filled.Home, Icons.Outlined.Home),
    Settings(R.string.settings, Icons.Filled.Settings, Icons.Outlined.Settings),
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ShellScreen(model: AppModel) {
    var tab by rememberSaveable { mutableStateOf(Tab.Home) }
    var creating by rememberSaveable { mutableStateOf(false) }
    var pendingDelete by remember { mutableStateOf<UserLayout?>(null) }
    var pendingExport by remember { mutableStateOf<UserLayout?>(null) }
    val snackbar = remember { SnackbarHostState() }
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    val importFailed = stringResource(R.string.import_failed)
    val scroll = TopAppBarDefaults.enterAlwaysScrollBehavior()

    val exporter = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("text/xml")) { uri ->
        val item = pendingExport
        pendingExport = null
        if (uri == null || item == null) return@rememberLauncherForActivityResult
        runCatching {
            context.contentResolver.openOutputStream(uri)?.use { it.write(model.export(item).toByteArray()) }
        }
    }
    val importer = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        val text = runCatching {
            context.contentResolver.openInputStream(uri)?.use { it.readBytes().decodeToString() }
        }.getOrNull()
        if (text == null || !model.import(text)) {
            scope.launch { snackbar.showSnackbar(importFailed) }
        }
    }

    Scaffold(
        modifier = Modifier.nestedScroll(scroll.nestedScrollConnection),
        topBar = {
            TopAppBar(
                title = { Text(stringResource(if (tab == Tab.Home) R.string.app_name else R.string.settings)) },
                scrollBehavior = scroll,
            )
        },
        bottomBar = {
            NavigationBar {
                Tab.entries.forEach { item ->
                    NavigationBarItem(
                        selected = tab == item,
                        onClick = { tab = item },
                        icon = { Icon(if (tab == item) item.selected else item.idle, contentDescription = null) },
                        label = { Text(stringResource(item.label)) },
                    )
                }
            }
        },
        floatingActionButton = {
            if (tab == Tab.Home) {
                ExtendedFloatingActionButton(
                    onClick = { creating = true },
                    icon = { Icon(Icons.Filled.Add, contentDescription = null) },
                    text = { Text(stringResource(R.string.new_layout)) },
                )
            }
        },
        snackbarHost = { SnackbarHost(snackbar) },
    ) { padding ->
        when (tab) {
            Tab.Home -> HomeTab(
                model = model,
                padding = padding,
                onImport = { importer.launch(arrayOf("text/xml", "application/xml", "text/plain", "application/octet-stream")) },
                onExport = { item ->
                    pendingExport = item
                    exporter.launch("${item.name}.xml")
                },
                onDelete = { pendingDelete = it },
            )
            Tab.Settings -> SettingsTab(model.settings, padding, onTry = model.haptics::tick)
        }
    }

    if (creating) {
        CreateDialog(
            onCreate = { name ->
                creating = false
                model.create(name)
            },
            onDismiss = { creating = false },
        )
    }
    pendingDelete?.let { item ->
        AlertDialog(
            onDismissRequest = { pendingDelete = null },
            icon = { Icon(Icons.Filled.Delete, contentDescription = null) },
            title = { Text(stringResource(R.string.delete_layout)) },
            text = { Text(item.name) },
            confirmButton = {
                TextButton(onClick = {
                    model.library.remove(item.id)
                    pendingDelete = null
                }) { Text(stringResource(R.string.delete)) }
            },
            dismissButton = {
                TextButton(onClick = { pendingDelete = null }) { Text(stringResource(R.string.cancel)) }
            },
        )
    }
}

@Composable
private fun HomeTab(
    model: AppModel,
    padding: PaddingValues,
    onImport: () -> Unit,
    onExport: (UserLayout) -> Unit,
    onDelete: (UserLayout) -> Unit,
) {
    val session = model.session
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(
            start = 16.dp,
            end = 16.dp,
            top = padding.calculateTopPadding() + 8.dp,
            // Room for the extended FAB over the last card.
            bottom = padding.calculateBottomPadding() + 88.dp,
        ),
        verticalArrangement = Arrangement.spacedBy(12.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        item {
            Card(
                colors = CardDefaults.cardColors(
                    containerColor = if (session.linked) {
                        MaterialTheme.colorScheme.primaryContainer
                    } else {
                        MaterialTheme.colorScheme.surfaceContainerHighest
                    },
                ),
                modifier = Modifier.widthIn(max = 560.dp).fillMaxWidth(),
            ) {
                Row(
                    Modifier.padding(start = 16.dp, end = 8.dp, top = 12.dp, bottom = 12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        statusText(session),
                        style = MaterialTheme.typography.titleMedium,
                        modifier = Modifier.weight(1f),
                    )
                    TextButton(onClick = model::disconnect) { Text(stringResource(R.string.disconnect)) }
                }
            }
        }
        item { SectionHeader(stringResource(R.string.presets)) }
        items(Preset.entries) { preset ->
            LayoutCard(
                title = stringResource(preset.nameRes),
                onPlay = { model.play(preset) },
                onEdit = { model.edit(preset) },
            )
        }
        item {
            SectionHeader(stringResource(R.string.my_layouts)) {
                TextButton(onClick = onImport) { Text(stringResource(R.string.import_layout)) }
            }
        }
        if (model.library.items.isEmpty()) {
            item {
                Text(
                    stringResource(R.string.no_layouts),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.widthIn(max = 560.dp).fillMaxWidth().padding(horizontal = 4.dp),
                )
            }
        }
        items(model.library.items, key = { it.id }) { item ->
            LayoutCard(
                title = item.name,
                onPlay = { model.play(item) },
                onEdit = { model.edit(item) },
                onExport = { onExport(item) },
                onDelete = { onDelete(item) },
            )
        }
    }
}

@Composable
private fun SectionHeader(text: String, action: (@Composable () -> Unit)? = null) {
    Row(
        Modifier.widthIn(max = 560.dp).fillMaxWidth().padding(start = 4.dp, top = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text,
            style = MaterialTheme.typography.titleSmall,
            color = MaterialTheme.colorScheme.primary,
            modifier = Modifier.weight(1f),
        )
        action?.invoke()
    }
}

@Composable
private fun LayoutCard(
    title: String,
    onPlay: () -> Unit,
    onEdit: () -> Unit,
    onExport: (() -> Unit)? = null,
    onDelete: (() -> Unit)? = null,
) {
    ElevatedCard(Modifier.widthIn(max = 560.dp).fillMaxWidth()) {
        Column(Modifier.padding(start = 16.dp, end = 8.dp, top = 16.dp, bottom = 8.dp)) {
            Text(
                title,
                style = MaterialTheme.typography.titleLarge,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.padding(end = 8.dp),
            )
            Row(
                Modifier.fillMaxWidth().padding(top = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Button(onClick = onPlay) { Text(stringResource(R.string.play)) }
                OutlinedButton(onClick = onEdit) { Text(stringResource(R.string.edit)) }
                Spacer(Modifier.weight(1f))
                if (onExport != null) {
                    IconButton(onClick = onExport) {
                        Icon(Icons.Filled.Share, contentDescription = stringResource(R.string.export_layout))
                    }
                }
                if (onDelete != null) {
                    IconButton(onClick = onDelete) {
                        Icon(Icons.Filled.Delete, contentDescription = stringResource(R.string.delete))
                    }
                }
            }
        }
    }
}

@Composable
private fun CreateDialog(onCreate: (String) -> Unit, onDismiss: () -> Unit) {
    var name by rememberSaveable { mutableStateOf("") }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.new_layout)) },
        text = {
            OutlinedTextField(
                value = name,
                onValueChange = { name = it },
                label = { Text(stringResource(R.string.layout_name)) },
                singleLine = true,
            )
        },
        confirmButton = { TextButton(onClick = { onCreate(name) }) { Text(stringResource(R.string.create)) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) } },
    )
}

@Composable
private fun SettingsTab(settings: Settings, padding: PaddingValues, onTry: () -> Unit) {
    var confirmReset by rememberSaveable { mutableStateOf(false) }
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = padding,
    ) {
        item { SettingsHeader(stringResource(R.string.haptics)) }
        item {
            ListItem(
                headlineContent = { Text(stringResource(R.string.haptics)) },
                supportingContent = { Text(stringResource(R.string.haptics_summary)) },
                trailingContent = { Switch(checked = settings.haptics, onCheckedChange = { settings.haptics = it }) },
                modifier = Modifier.padding(end = 8.dp),
            )
        }
        item {
            SliderItem(
                title = stringResource(R.string.intensity),
                value = settings.hapticIntensity,
                range = 0.05..1.0,
                label = percent(settings.hapticIntensity),
                enabled = settings.haptics,
                onChange = { settings.hapticIntensity = it },
                onFinished = onTry,
            )
        }
        item { HorizontalDivider(Modifier.padding(vertical = 8.dp)) }
        item { SettingsHeader(stringResource(R.string.timeouts)) }
        item {
            SliderItem(
                title = stringResource(R.string.confirm_hold),
                value = settings.holdTimeout,
                range = 0.2..2.0,
                label = stringResource(R.string.seconds, settings.holdTimeout),
                onChange = { settings.holdTimeout = it },
            )
        }
        item {
            SliderItem(
                title = stringResource(R.string.stick_click),
                value = settings.stickClickTimeout,
                range = 0.05..0.8,
                label = stringResource(R.string.seconds, settings.stickClickTimeout),
                onChange = { settings.stickClickTimeout = it },
            )
        }
        item { HorizontalDivider(Modifier.padding(vertical = 8.dp)) }
        item { SettingsHeader(stringResource(R.string.sticks)) }
        item {
            SliderItem(
                title = stringResource(R.string.deadzone),
                value = settings.stickDeadzone,
                range = 0.0..0.4,
                label = percent(settings.stickDeadzone),
                onChange = { settings.stickDeadzone = it },
            )
        }
        item {
            SliderItem(
                title = stringResource(R.string.stick_curve),
                value = settings.stickCurve,
                range = 1.0..3.0,
                label = String.format(LocalLocale.current.platformLocale, "%.1f", settings.stickCurve),
                onChange = { settings.stickCurve = it },
            )
        }
        item { HorizontalDivider(Modifier.padding(vertical = 8.dp)) }
        item {
            Row(Modifier.fillMaxWidth().padding(16.dp)) {
                OutlinedButton(
                    onClick = { confirmReset = true },
                    colors = ButtonDefaults.outlinedButtonColors(contentColor = MaterialTheme.colorScheme.error),
                ) { Text(stringResource(R.string.reset_defaults)) }
            }
        }
    }

    if (confirmReset) {
        AlertDialog(
            onDismissRequest = { confirmReset = false },
            title = { Text(stringResource(R.string.reset_defaults_question)) },
            confirmButton = {
                TextButton(onClick = {
                    settings.resetDefaults()
                    confirmReset = false
                }) { Text(stringResource(R.string.reset)) }
            },
            dismissButton = {
                TextButton(onClick = { confirmReset = false }) { Text(stringResource(R.string.cancel)) }
            },
        )
    }
}

@Composable
private fun SettingsHeader(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.titleSmall,
        color = MaterialTheme.colorScheme.primary,
        modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 16.dp, bottom = 4.dp),
    )
}

@Composable
private fun SliderItem(
    title: String,
    value: Double,
    range: ClosedFloatingPointRange<Double>,
    label: String,
    enabled: Boolean = true,
    onChange: (Double) -> Unit,
    onFinished: (() -> Unit)? = null,
) {
    ListItem(
        headlineContent = { Text(title) },
        trailingContent = { Text(label, style = MaterialTheme.typography.labelLarge) },
        supportingContent = {
            Slider(
                value = value.toFloat(),
                onValueChange = { onChange(it.toDouble()) },
                valueRange = range.start.toFloat()..range.endInclusive.toFloat(),
                enabled = enabled,
                onValueChangeFinished = onFinished,
            )
        },
    )
}

private fun percent(value: Double) = "${(value * 100).roundToInt()}%"
