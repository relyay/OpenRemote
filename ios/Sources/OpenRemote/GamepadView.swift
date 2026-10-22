import CoreHaptics
import SwiftUI
import UIKit

struct GamepadView: View {
    @Environment(Session.self) private var session
    @Environment(LayoutStore.self) private var layout
    var returnOnDone: Bool
    var onLeave: () -> Void
    var onFinish: () -> Void

    var body: some View {
        canvas
            .overlay(alignment: .bottom) {
                if layout.panel {
                    layoutPanel
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                header
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 6)
            }
            .background(padBackground)
            .defersSystemGestures(on: .all)
            .statusBarHidden(true)
            .persistentSystemOverlays(.hidden)
            .onAppear {
                applyOrientation(.landscape)
                UIApplication.shared.isIdleTimerDisabled = true
            }
            .onDisappear {
                UIApplication.shared.isIdleTimerDisabled = false
                applyOrientation(.portrait)
            }
    }

    private var header: some View {
        HoldCloseButton(
            symbol: returnOnDone ? "checkmark" : "xmark",
            label: returnOnDone ? L10n.done : L10n.close
        ) {
            if returnOnDone {
                layout.panel = false
                layout.editing = false
                layout.selected = nil
                onFinish()
            } else {
                onLeave()
            }
        }
    }

    private var layoutPanel: some View {
        HStack(spacing: 8) {
            if let id = layout.selected {
                Text(L10n.controlName(layout.kind(of: id)))
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                    .allowsHitTesting(false)
                Slider(value: Binding(
                    get: { layout.slot(id).scale },
                    set: { layout.setItemScale(id, $0) }
                ), in: 0.45...2)
            }
            Menu {
                ForEach(LayoutStore.controlIDs.sorted(), id: \.self) { kind in
                    Button(L10n.controlName(kind)) { layout.add(kind) }
                }
            } label: {
                Image(systemName: "plus")
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.glass)
            .controlSize(.small)
            .accessibilityLabel(L10n.addControl)
            if let id = layout.selected {
                Button {
                    silence(id)
                    layout.remove(id)
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .accessibilityLabel(L10n.removeControl)
            }
            Button(action: layout.reset) {
                Image(systemName: "arrow.counterclockwise")
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.glass)
            .controlSize(.small)
            .accessibilityLabel(L10n.resetLayout)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            Capsule()
                .glassEffect(.regular, in: Capsule())
                .allowsHitTesting(false)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    private var canvas: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                placed("lt", in: size) { triggerCircle(left: true) }
                placed("lb", in: size) { hold("LB", tint: .white, bit: PadSnapshot.lb, circle: true) }
                placed("rt", in: size) { triggerCircle(left: false) }
                placed("rb", in: size) { hold("RB", tint: .white, bit: PadSnapshot.rb, circle: true) }
                placed("dpad", in: size) { dpad }
                placed("y", in: size) { hold("Y", tint: .yellow, bit: PadSnapshot.y, circle: true) }
                placed("x", in: size) { hold("X", tint: .blue, bit: PadSnapshot.x, circle: true) }
                placed("b", in: size) { hold("B", tint: .red, bit: PadSnapshot.b, circle: true) }
                placed("a", in: size) { hold("A", tint: .green, bit: PadSnapshot.a, circle: true) }
                placed("ls", in: size) { analog(left: true) }
                placed("rs", in: size) { analog(left: false) }
                placed("l3", in: size) { hold("L3", tint: .white, bit: PadSnapshot.l3, circle: true) }
                placed("r3", in: size) { hold("R3", tint: .white, bit: PadSnapshot.r3, circle: true) }
                placed("back", in: size) { hold("Back", tint: .white, bit: PadSnapshot.back, circle: false) }
                placed("guide", in: size) { hold("", tint: .white, bit: PadSnapshot.guide, circle: true, symbol: "gamecontroller.fill") }
                placed("start", in: size) { hold("Start", tint: .white, bit: PadSnapshot.start, circle: false) }
                ForEach(layout.extras) { node in
                    placed(node.id, in: size) { control(node.kind) }
                }
            }
            .frame(width: size.width, height: size.height)
            .onAppear { layout.remember(size) }
            .onChange(of: size) { _, newSize in layout.remember(newSize) }
        }
    }

    @ViewBuilder
    private func placed<Content: View>(_ id: String, in size: CGSize, @ViewBuilder content: () -> Content) -> some View {
        if !layout.hidden.contains(id) {
            let slot = layout.slot(id, in: size)
            content()
            .scaleEffect(slot.scale)
            .overlay {
                if layout.editing {
                    DragCatcher(
                        onBegan: { layout.beginDrag(id, size: size) },
                        onMoved: { dx, dy in layout.drag(id, dx: dx, dy: dy, size: size) },
                        onEnded: { layout.endDrag(id) }
                    )
                }
            }
            .overlay {
                if layout.editing {
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(layout.selected == id ? Color.accentColor : Color.primary.opacity(0.45), lineWidth: 2)
                        .allowsHitTesting(false)
                }
            }
            .position(x: slot.x * size.width, y: slot.y * size.height)
        }
    }

    @ViewBuilder
    private func control(_ kind: String) -> some View {
        switch kind {
        case "lt": triggerCircle(left: true)
        case "rt": triggerCircle(left: false)
        case "lb": hold("LB", tint: .white, bit: PadSnapshot.lb, circle: true)
        case "rb": hold("RB", tint: .white, bit: PadSnapshot.rb, circle: true)
        case "dpad": dpad
        case "y": hold("Y", tint: .yellow, bit: PadSnapshot.y, circle: true)
        case "x": hold("X", tint: .blue, bit: PadSnapshot.x, circle: true)
        case "b": hold("B", tint: .red, bit: PadSnapshot.b, circle: true)
        case "a": hold("A", tint: .green, bit: PadSnapshot.a, circle: true)
        case "ls": analog(left: true)
        case "rs": analog(left: false)
        case "l3": hold("L3", tint: .white, bit: PadSnapshot.l3, circle: true)
        case "r3": hold("R3", tint: .white, bit: PadSnapshot.r3, circle: true)
        case "back": hold("Back", tint: .white, bit: PadSnapshot.back, circle: false)
        case "guide": hold("", tint: .white, bit: PadSnapshot.guide, circle: true, symbol: "gamecontroller.fill")
        case "start": hold("Start", tint: .white, bit: PadSnapshot.start, circle: false)
        default: EmptyView()
        }
    }

    private func silence(_ id: String) {
        release(layout.kind(of: id))
    }

    private func release(_ kind: String) {
        switch kind {
        case "lt": session.setTrigger(left: true, value: 0)
        case "rt": session.setTrigger(left: false, value: 0)
        case "ls":
            session.setLeft(x: 0, y: 0)
            session.setButton(PadSnapshot.l3, down: false)
        case "rs":
            session.setRight(x: 0, y: 0)
            session.setButton(PadSnapshot.r3, down: false)
        case "dpad": session.setHat(x: 0, y: 0)
        case "y": session.setButton(PadSnapshot.y, down: false)
        case "x": session.setButton(PadSnapshot.x, down: false)
        case "b": session.setButton(PadSnapshot.b, down: false)
        case "a": session.setButton(PadSnapshot.a, down: false)
        case "lb": session.setButton(PadSnapshot.lb, down: false)
        case "rb": session.setButton(PadSnapshot.rb, down: false)
        case "l3": session.setButton(PadSnapshot.l3, down: false)
        case "r3": session.setButton(PadSnapshot.r3, down: false)
        case "back": session.setButton(PadSnapshot.back, down: false)
        case "guide": session.setButton(PadSnapshot.guide, down: false)
        case "start": session.setButton(PadSnapshot.start, down: false)
        default: break
        }
    }

    private var dpad: some View {
        DPad(hatX: session.pad.hatX, hatY: session.pad.hatY, enabled: !layout.editing) { x, y in
            session.setHat(x: x, y: y)
        }
        .modifier(DirectionHaptic(x: session.pad.hatX, y: session.pad.hatY))
        .frame(width: 156, height: 156)
    }

    private func analog(left: Bool) -> some View {
        let bit = left ? PadSnapshot.l3 : PadSnapshot.r3
        return Stick(
            x: left ? session.pad.lx : session.pad.rx,
            y: left ? session.pad.ly : session.pad.ry,
            clicked: session.pad.buttons & bit != 0,
            enabled: !layout.editing,
            onMove: { x, y in
                if left {
                    session.setLeft(x: x, y: y)
                } else {
                    session.setRight(x: x, y: y)
                }
            },
            onClick: { down in
                session.setButton(bit, down: down)
            }
        )
        .frame(width: 148, height: 148)
    }

    private func triggerCircle(left: Bool) -> some View {
        let down = (left ? session.pad.lt : session.pad.rt) > 0.5
        return HoldControl(title: left ? "LT" : "RT", tint: .white, circle: true, down: down, enabled: !layout.editing) { pressed in
            session.setTrigger(left: left, value: pressed ? 1 : 0)
        }
    }

    private func hold(_ title: String, tint: Color, bit: UInt16, circle: Bool, symbol: String? = nil) -> some View {
        let down = session.pad.buttons & bit != 0
        return HoldControl(title: title, symbol: symbol, tint: tint, circle: circle, down: down, enabled: !layout.editing) { pressed in
            session.setButton(bit, down: pressed)
        }
    }
}

private struct HoldControl: View {
    var title: String
    var symbol: String?
    var tint: Color
    var circle: Bool
    var down: Bool
    var enabled: Bool
    var onChange: (Bool) -> Void

    var body: some View {
        let glass = (down ? Glass.regular.tint(tint) : Glass.regular.tint(tint.opacity(0.55))).interactive()
        ZStack {
            if let symbol {
                Image(systemName: symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.primary)
                    .allowsHitTesting(false)
            } else {
                Text(title.isEmpty ? " " : title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(tint == .yellow ? Color.black : Color.primary)
                    .allowsHitTesting(false)
            }
        }
        .frame(minWidth: circle ? 64 : 82, minHeight: circle ? 64 : 50)
        .padding(.horizontal, circle ? 0 : 12)
        .glassEffect(glass, in: circle ? AnyShape(Circle()) : AnyShape(Capsule()))
        .overlay {
            PressCatcher { pressed in
                onChange(pressed)
            }
            .allowsHitTesting(enabled)
        }
        .modifier(PressHaptic(trigger: down))
    }
}

enum Haptics {
    @MainActor private static var engine: CHHapticEngine?

    @MainActor
    static func play() {
        let defaults = UserDefaults.standard
        let enabled = defaults.object(forKey: AppSettings.Key.haptics) as? Bool ?? AppSettings.Default.haptics
        guard enabled else { return }
        let raw = defaults.object(forKey: AppSettings.Key.hapticIntensity) as? Double ?? AppSettings.Default.hapticIntensity
        let amount = Float(min(1, max(0, raw)))
        guard amount > 0.02 else { return }
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            let engine = try runningEngine()
            let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: amount)
            let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.6)
            let event = CHHapticEvent(eventType: .hapticTransient, parameters: [intensity, sharpness], relativeTime: 0)
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            engine = nil
        }
    }

    @MainActor
    private static func runningEngine() throws -> CHHapticEngine {
        if let engine { return engine }
        let created = try CHHapticEngine()
        created.isAutoShutdownEnabled = false
        created.resetHandler = {
            Task { @MainActor in
                engine = nil
            }
        }
        try created.start()
        engine = created
        return created
    }
}

/// Tuning shared by the pad and the settings tab. The settings tab reads the
/// same keys through @AppStorage, so its defaults come from `Default` as well.
enum AppSettings {
    enum Key {
        static let haptics = "haptics"
        static let hapticIntensity = "hapticIntensity"
        static let holdTimeout = "holdTimeout"
        static let stickClickTimeout = "stickClickTimeout"
        static let stickDeadzone = "stickDeadzone"
        static let stickCurve = "stickCurve"
    }

    enum Default {
        static let haptics = true
        static let hapticIntensity = 1.0
        static let holdTimeout = 0.7
        static let stickClickTimeout = 0.16
        static let stickDeadzone = 0.14
        static let stickCurve = 1.0
    }

    static var holdTimeout: TimeInterval {
        let raw = UserDefaults.standard.object(forKey: Key.holdTimeout) as? Double ?? Default.holdTimeout
        return min(2, max(0.2, raw))
    }

    static var stickClickTimeout: TimeInterval {
        let raw = UserDefaults.standard.object(forKey: Key.stickClickTimeout) as? Double ?? Default.stickClickTimeout
        return min(0.8, max(0.05, raw))
    }

    static var stickDeadzone: Double {
        let raw = UserDefaults.standard.object(forKey: Key.stickDeadzone) as? Double ?? Default.stickDeadzone
        return min(0.5, max(0, raw))
    }

    static var stickCurve: Double {
        let raw = UserDefaults.standard.object(forKey: Key.stickCurve) as? Double ?? Default.stickCurve
        return min(3, max(1, raw))
    }
}

private struct PressHaptic: ViewModifier {
    var trigger: Bool

    func body(content: Content) -> some View {
        content.onChange(of: trigger) { _, _ in
            Haptics.play()
        }
    }
}

private struct PulseHaptic: ViewModifier {
    var pulse: Int

    func body(content: Content) -> some View {
        content.onChange(of: pulse) { _, value in
            if value > 0 { Haptics.play() }
        }
    }
}

private struct DirectionHaptic: ViewModifier {
    var x: Int8
    var y: Int8

    func body(content: Content) -> some View {
        content.onChange(of: Int(x) * 3 + Int(y)) { _, _ in
            Haptics.play()
        }
    }
}

private struct Stick: View {
    var x: Double
    var y: Double
    var clicked: Bool
    var enabled: Bool
    var onMove: (Double, Double) -> Void
    var onClick: (Bool) -> Void
    @State private var touchPulse = 0
    @State private var clickPulse = 0

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let travel = side * 0.32
            ZStack {
                Circle()
                    .glassEffect(.regular.interactive(), in: .circle)
                    .allowsHitTesting(false)
                Circle()
                    .fill(clicked ? Color.green.opacity(0.9) : Color.white.opacity(0.9))
                    .frame(width: side * 0.42, height: side * 0.42)
                    .offset(x: x * travel, y: y * travel)
                    .allowsHitTesting(false)
                StickCatcher(
                    onChange: onMove,
                    onTouch: { down in
                        if down { touchPulse += 1 }
                    },
                    onClick: { down in
                        onClick(down)
                        if down { clickPulse += 1 }
                    }
                )
                .allowsHitTesting(enabled)
            }
        }
        .modifier(PulseHaptic(pulse: touchPulse))
        .modifier(PulseHaptic(pulse: clickPulse))
    }
}

private struct DPad: View {
    var hatX: Int8
    var hatY: Int8
    var enabled: Bool
    var onChange: (Int8, Int8) -> Void

    var body: some View {
        GeometryReader { geo in
            ZStack {
                arm(vertical: true, active: hatY < 0, edge: .top)
                arm(vertical: true, active: hatY > 0, edge: .bottom)
                arm(vertical: false, active: hatX < 0, edge: .leading)
                arm(vertical: false, active: hatX > 0, edge: .trailing)
            }
            .overlay {
                ZoneCatcher { point in
                    guard let point else {
                        onChange(0, 0)
                        return
                    }
                    let nx = (point.x - geo.size.width / 2) / max(geo.size.width / 2, 1)
                    let ny = (point.y - geo.size.height / 2) / max(geo.size.height / 2, 1)
                    var hx: Int8 = 0
                    var hy: Int8 = 0
                    if hypot(nx, ny) > 0.28 {
                        if abs(nx) > 0.32 { hx = nx > 0 ? 1 : -1 }
                        if abs(ny) > 0.32 { hy = ny > 0 ? 1 : -1 }
                    }
                    onChange(hx, hy)
                }
                .allowsHitTesting(enabled)
            }
        }
    }

    private func arm(vertical: Bool, active: Bool, edge: Edge) -> some View {
        let glass = (active ? Glass.regular.tint(.green) : Glass.regular).interactive()
        return RoundedRectangle(cornerRadius: 10)
            .glassEffect(glass, in: RoundedRectangle(cornerRadius: 10))
            .frame(width: vertical ? 40 : nil, height: vertical ? nil : 40)
            .frame(maxWidth: vertical ? nil : .infinity, maxHeight: vertical ? .infinity : nil)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment(edge))
            .padding(vertical ? .horizontal : .vertical, 30)
            .allowsHitTesting(false)
    }

    private func alignment(_ edge: Edge) -> Alignment {
        switch edge {
        case .top: .top
        case .bottom: .bottom
        case .leading: .leading
        case .trailing: .trailing
        }
    }
}

private struct HoldCloseButton: View {
    var symbol: String
    var label: String
    var onExit: () -> Void
    @State private var holding = false
    @State private var started: Date?

    private var duration: TimeInterval { AppSettings.holdTimeout }

    var body: some View {
        Image(systemName: symbol)
            .font(.body.weight(.bold))
            .frame(width: 44, height: 44)
            .glassEffect(.regular.interactive(), in: .circle)
            .overlay {
                Circle()
                    .trim(from: 0, to: holding ? 1 : 0)
                    .stroke(Color.primary, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(3)
                    .allowsHitTesting(false)
                    .animation(.linear(duration: duration), value: holding)
            }
            .overlay {
                PressCatcher { down in
                    if down { begin() } else { end() }
                }
            }
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
    }

    private func begin() {
        started = Date()
        holding = true
    }

    private func end() {
        let elapsed = started.map { Date().timeIntervalSince($0) } ?? 0
        started = nil
        holding = false
        if elapsed >= duration {
            onExit()
        }
    }
}

private var padBackground: some View {
    LinearGradient(
        colors: [Color(.secondarySystemBackground), Color(.systemBackground)],
        startPoint: .top,
        endPoint: .bottom
    )
    .ignoresSafeArea()
}
