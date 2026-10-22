import SwiftUI
import UniformTypeIdentifiers

enum ShellTab: Hashable {
    case home
    case settings
}

struct MainShell: View {
    @Environment(Session.self) private var session
    @Environment(LayoutStore.self) private var layout
    @Environment(LayoutLibrary.self) private var library
    @State private var tab: ShellTab = .home
    @State private var showPad = false
    @State private var returnOnDone = false
    @State private var activeCustom: UUID?
    @State private var activePreset: LayoutPreset?
    @State private var creating = false
    @State private var draftName = ""
    @State private var pendingDelete: UserLayout?
    @State private var exporting = false
    @State private var exportDocument: LayoutXMLFile?
    @State private var exportName = "layout"
    @State private var importing = false
    @State private var importFailed = false
    @AppStorage(AppSettings.Key.haptics) private var haptics = AppSettings.Default.haptics
    @AppStorage(AppSettings.Key.hapticIntensity) private var hapticIntensity = AppSettings.Default.hapticIntensity
    @AppStorage(AppSettings.Key.holdTimeout) private var holdTimeout = AppSettings.Default.holdTimeout
    @AppStorage(AppSettings.Key.stickClickTimeout) private var stickClickTimeout = AppSettings.Default.stickClickTimeout
    @AppStorage(AppSettings.Key.stickDeadzone) private var stickDeadzone = AppSettings.Default.stickDeadzone
    @AppStorage(AppSettings.Key.stickCurve) private var stickCurve = AppSettings.Default.stickCurve
    @State private var confirmReset = false

    var body: some View {
        Group {
            if showPad {
                GamepadView(returnOnDone: returnOnDone, onLeave: leavePad, onFinish: finishEdit)
            } else {
                dock
            }
        }
        .onAppear { applyOrientation(showPad ? .landscape : .portrait) }
        .onChange(of: showPad) { _, on in
            applyOrientation(on ? .landscape : .portrait)
        }
    }

    private var dock: some View {
        TabView(selection: $tab) {
            home
                .tag(ShellTab.home)
                .tabItem { Label(L10n.home, systemImage: "house.fill") }
            settings
                .tag(ShellTab.settings)
                .tabItem { Label(L10n.settings, systemImage: "gearshape.fill") }
        }
        .tabViewStyle(.tabBarOnly)
        .background(screenBackground)
        .fileExporter(
            isPresented: $exporting,
            document: exportDocument,
            contentType: .openRemoteLayout,
            defaultFilename: exportName
        ) { _ in }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.openRemoteLayout], onCompletion: importFile)
        .alert(L10n.importFailed, isPresented: $importFailed) {
            Button(L10n.done, role: .cancel) {}
        }
        .alert(L10n.createLayout, isPresented: $creating) {
            TextField(L10n.layoutName, text: $draftName)
            Button(L10n.create, action: createLayout)
            Button(L10n.cancel, role: .cancel) {}
        }
        .alert(L10n.delete, isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )) {
            Button(L10n.delete, role: .destructive) {
                if let pendingDelete { library.remove(pendingDelete.id) }
                pendingDelete = nil
            }
            Button(L10n.cancel, role: .cancel) { pendingDelete = nil }
        } message: {
            Text(pendingDelete?.name ?? "")
        }
    }

    private var home: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("OpenRemote")
                        .font(.title2.bold())
                    Text(session.statusText)
                        .font(.subheadline)
                        .foregroundStyle(session.linked ? Color.green : Color.secondary)
                    Button(L10n.disconnect, action: session.disconnect)
                        .buttonStyle(.glass)
                        .controlSize(.small)
                }
                Text(L10n.presets)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(LayoutPreset.allCases) { preset in
                    card(title: preset.name, kind: L10n.presets) {
                        playPreset(preset)
                    } edit: {
                        editPreset(preset)
                    }
                }
                Text(L10n.myLayouts)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack {
                    Button(L10n.createLayout) { creating = true }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                    Button(L10n.importLayout) { importing = true }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                }
                ForEach(library.customs) { item in
                    card(title: item.name, kind: L10n.myLayouts, onDelete: { pendingDelete = item }) {
                        playCustom(item)
                    } edit: {
                        editCustom(item)
                    } export: {
                        exportCustom(item)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
    }

    private var settings: some View {
        VStack(spacing: 0) {
            List {
                Section {
                    Toggle(L10n.haptics, isOn: $haptics)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.intensity)
                        Slider(value: $hapticIntensity, in: 0.05...1, onEditingChanged: { editing in
                            if !editing { Haptics.play() }
                        })
                    }
                    .disabled(!haptics)
                } header: {
                    Text(L10n.haptics)
                }
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(L10n.confirmHold)
                            Spacer()
                            Text(L10n.seconds(holdTimeout))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $holdTimeout, in: 0.2...2)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(L10n.stickClick)
                            Spacer()
                            Text(L10n.seconds(stickClickTimeout))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $stickClickTimeout, in: 0.05...0.8)
                    }
                } header: {
                    Text(L10n.timeouts)
                }
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(L10n.deadzone)
                            Spacer()
                            Text("\(Int((stickDeadzone * 100).rounded()))%")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $stickDeadzone, in: 0...0.4)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(L10n.stickCurve)
                            Spacer()
                            Text(String(format: "%.1f", stickCurve))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $stickCurve, in: 1...3)
                    }
                } header: {
                    Text(L10n.sticks)
                }
                Section {
                    Button(L10n.resetDefaults, role: .destructive) {
                        confirmReset = true
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .listStyle(.insetGrouped)
            .confirmationDialog(L10n.resetDefaultsQuestion, isPresented: $confirmReset, titleVisibility: .visible) {
                Button(L10n.resetDefaults, role: .destructive, action: resetSettings)
                Button(L10n.cancel, role: .cancel) {}
            }
        }
    }

    private func resetSettings() {
        haptics = AppSettings.Default.haptics
        hapticIntensity = AppSettings.Default.hapticIntensity
        holdTimeout = AppSettings.Default.holdTimeout
        stickClickTimeout = AppSettings.Default.stickClickTimeout
        stickDeadzone = AppSettings.Default.stickDeadzone
        stickCurve = AppSettings.Default.stickCurve
    }

    private func card(
        title: String,
        kind: String,
        onDelete: (() -> Void)? = nil,
        play: @escaping () -> Void,
        edit: @escaping () -> Void,
        export: (() -> Void)? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .lineLimit(1)
            Text(kind)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button(L10n.play, action: play)
                    .buttonStyle(.glassProminent)
                    .controlSize(.small)
                Button(L10n.edit, action: edit)
                    .buttonStyle(.glass)
                    .controlSize(.small)
                if let export {
                    Button(action: export) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .accessibilityLabel(L10n.exportLayout)
                }
                if let onDelete {
                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18))
    }

    private func playPreset(_ preset: LayoutPreset) {
        preset.apply(to: layout)
        activePreset = preset
        activeCustom = nil
        returnOnDone = false
        showPad = true
    }

    private func playCustom(_ item: UserLayout) {
        layout.install(
            item.slots,
            dynamicFace: !item.faceCustom,
            dynamicCenter: !item.centerCustom,
            hidden: Set(item.hidden),
            extras: item.extras,
            faceOnLeft: item.faceOnLeft
        )
        activeCustom = item.id
        activePreset = nil
        returnOnDone = false
        showPad = true
    }

    private func editPreset(_ preset: LayoutPreset) {
        preset.apply(to: layout)
        activePreset = preset
        activeCustom = library.customs.first { $0.name == preset.name }?.id
        returnOnDone = true
        layout.editing = true
        layout.panel = true
        showPad = true
    }

    private func editCustom(_ item: UserLayout) {
        layout.install(
            item.slots,
            dynamicFace: !item.faceCustom,
            dynamicCenter: !item.centerCustom,
            hidden: Set(item.hidden),
            extras: item.extras,
            faceOnLeft: item.faceOnLeft
        )
        activeCustom = item.id
        activePreset = nil
        returnOnDone = true
        layout.editing = true
        layout.panel = true
        showPad = true
    }

    private func createLayout() {
        let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        draftName = ""
        LayoutPreset.standard.apply(to: layout)
        let item = library.add(
            name: name.isEmpty ? L10n.untitled : name,
            slots: layout.slots,
            faceCustom: false,
            centerCustom: false
        )
        activeCustom = item.id
        activePreset = nil
        returnOnDone = true
        layout.editing = true
        layout.panel = true
        showPad = true
    }

    private func finishEdit() {
        storeActive()
        layout.editing = false
        layout.panel = false
        showPad = false
        returnOnDone = false
    }

    private func leavePad() {
        if layout.changed || returnOnDone {
            storeActive()
        }
        session.releasePad()
        layout.editing = false
        layout.panel = false
        showPad = false
        returnOnDone = false
    }

    private func storeActive() {
        let baked = layout.bake()
        if let activeCustom {
            library.update(
                activeCustom,
                slots: baked.slots,
                faceCustom: baked.faceCustom,
                centerCustom: baked.centerCustom,
                hidden: baked.hidden,
                extras: baked.extras,
                faceOnLeft: baked.faceOnLeft
            )
            return
        }
        guard layout.changed || returnOnDone, let preset = activePreset else { return }
        if let existing = library.customs.first(where: { $0.name == preset.name }) {
            library.update(
                existing.id,
                slots: baked.slots,
                faceCustom: baked.faceCustom,
                centerCustom: baked.centerCustom,
                hidden: baked.hidden,
                extras: baked.extras,
                faceOnLeft: baked.faceOnLeft
            )
            activeCustom = existing.id
        } else {
            let item = library.add(
                name: preset.name,
                slots: baked.slots,
                faceCustom: baked.faceCustom,
                centerCustom: baked.centerCustom,
                hidden: baked.hidden,
                extras: baked.extras,
                faceOnLeft: baked.faceOnLeft
            )
            activeCustom = item.id
        }
    }

    private func exportCustom(_ item: UserLayout) {
        exportName = item.name
        exportDocument = LayoutXMLFile(text: LayoutXML.encode(
            name: item.name,
            slots: item.slots,
            faceCustom: item.faceCustom,
            centerCustom: item.centerCustom,
            hidden: item.hidden,
            extras: item.extras,
            faceOnLeft: item.faceOnLeft
        ))
        exporting = true
    }

    private func importFile(_ result: Result<URL, Error>) {
        guard case let .success(url) = result else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8),
              let parsed = LayoutXML.decode(text) else {
            importFailed = true
            return
        }
        _ = library.add(
            name: parsed.name,
            slots: parsed.slots,
            faceCustom: parsed.faceCustom,
            centerCustom: parsed.centerCustom,
            hidden: parsed.hidden,
            extras: parsed.extras,
            faceOnLeft: parsed.faceOnLeft
        )
    }
}
