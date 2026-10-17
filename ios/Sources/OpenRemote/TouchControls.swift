import SwiftUI
import UIKit

/// SwiftUI delays the first stationary touch until a second finger lands.
/// These recognizers accept the touch immediately and ignore that delay.
struct PressCatcher: UIViewRepresentable {
    var onChange: (Bool) -> Void

    func makeUIView(context: Context) -> PressHost {
        let host = PressHost()
        host.onChange = onChange
        return host
    }

    func updateUIView(_ uiView: PressHost, context: Context) {
        uiView.onChange = onChange
    }
}

/// Buttons use the view's own touches. A gesture recognizer can be reset
/// in the same turn the finger lands, and the press never reaches the game.
final class PressHost: UIView {
    var onChange: ((Bool) -> Void)?
    private var active = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        isExclusiveTouch = false
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) { return nil }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        loosenAncestorGestures()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        loosenAncestorGestures()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let wasEmpty = active == 0
        active += touches.count
        if wasEmpty { onChange?(true) }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        finish(touches.count)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        finish(touches.count)
    }

    private func finish(_ count: Int) {
        active = max(0, active - count)
        if active == 0 { onChange?(false) }
    }
}

struct StickCatcher: UIViewRepresentable {
    var onChange: (Double, Double) -> Void
    var onTouch: (Bool) -> Void
    var onClick: (Bool) -> Void

    func makeUIView(context: Context) -> TouchHost {
        let host = TouchHost()
        host.install(StickRecognizer(onChange: onChange, onTouch: onTouch, onClick: onClick))
        return host
    }

    func updateUIView(_ uiView: TouchHost, context: Context) {
        guard let stick = uiView.recognizer as? StickRecognizer else { return }
        stick.onChange = onChange
        stick.onTouch = onTouch
        stick.onClick = onClick
    }
}

struct ZoneCatcher: UIViewRepresentable {
    var onChange: (CGPoint?) -> Void

    func makeUIView(context: Context) -> TouchHost {
        let host = TouchHost()
        host.install(ZoneRecognizer(onChange: onChange))
        return host
    }

    func updateUIView(_ uiView: TouchHost, context: Context) {
        (uiView.recognizer as? ZoneRecognizer)?.onChange = onChange
    }
}

struct DragCatcher: UIViewRepresentable {
    var onBegan: () -> Void
    var onMoved: (CGFloat, CGFloat) -> Void
    var onEnded: () -> Void

    func makeUIView(context: Context) -> TouchHost {
        let host = TouchHost()
        host.install(DragRecognizer(onBegan: onBegan, onMoved: onMoved, onEnded: onEnded))
        return host
    }

    func updateUIView(_ uiView: TouchHost, context: Context) {
        guard let drag = uiView.recognizer as? DragRecognizer else { return }
        drag.onBegan = onBegan
        drag.onMoved = onMoved
        drag.onEnded = onEnded
    }
}

final class TouchHost: UIView {
    var recognizer: UIGestureRecognizer?
    private let gate = SimultaneousGate.shared

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        isExclusiveTouch = false
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) { return nil }

    func install(_ recognizer: UIGestureRecognizer) {
        recognizer.delegate = gate
        recognizer.cancelsTouchesInView = false
        recognizer.delaysTouchesBegan = false
        recognizer.delaysTouchesEnded = false
        addGestureRecognizer(recognizer)
        self.recognizer = recognizer
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        loosenAncestorGestures()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        loosenAncestorGestures()
    }

    private func loosenAncestorGestures() {
        loosenAncestorGestures(except: recognizer)
    }
}

extension UIView {
    fileprivate func loosenAncestorGestures(except: UIGestureRecognizer? = nil) {
        var node: UIView? = superview
        while let current = node {
            for other in current.gestureRecognizers ?? [] where other !== except {
                other.delaysTouchesBegan = false
                other.delaysTouchesEnded = false
                other.cancelsTouchesInView = false
            }
            node = current.superview
        }
    }
}

private final class SimultaneousGate: NSObject, UIGestureRecognizerDelegate {
    static let shared = SimultaneousGate()

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        true
    }
}

private final class StickRecognizer: UIGestureRecognizer {
    var onChange: (Double, Double) -> Void
    var onTouch: (Bool) -> Void
    var onClick: (Bool) -> Void
    private var touch: UITouch?
    private var origin: CGPoint = .zero
    private var clickArmed = false
    private var clickDown = false
    private var clickWork: DispatchWorkItem?

    init(
        onChange: @escaping (Double, Double) -> Void,
        onTouch: @escaping (Bool) -> Void,
        onClick: @escaping (Bool) -> Void
    ) {
        self.onChange = onChange
        self.onTouch = onTouch
        self.onClick = onClick
        super.init(target: nil, action: nil)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        guard touch == nil, let next = touches.first, let view else { return }
        touch = next
        origin = next.location(in: view)
        clickArmed = true
        clickDown = false
        state = .began
        onTouch(true)
        emit(next)
        scheduleClick()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        guard let touch, touches.contains(touch), let view else { return }
        if clickArmed, hypot(touch.location(in: view).x - origin.x, touch.location(in: view).y - origin.y) > 16 {
            clickArmed = false
            clickWork?.cancel()
        }
        state = .changed
        emit(touch)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        end(touches, cancelled: false)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        end(touches, cancelled: true)
    }

    private func scheduleClick() {
        clickWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.clickArmed else { return }
            self.clickArmed = false
            self.clickDown = true
            self.onClick(true)
        }
        clickWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + AppSettings.stickClickTimeout, execute: work)
    }

    private func end(_ touches: Set<UITouch>, cancelled: Bool) {
        guard let touch, touches.contains(touch) else { return }
        self.touch = nil
        clickWork?.cancel()
        let tap = clickArmed
        clickArmed = false
        let held = clickDown
        clickDown = false
        if tap && !held { onClick(true) }
        if held || tap { onClick(false) }
        onTouch(false)
        onChange(0, 0)
        state = cancelled ? .cancelled : .ended
    }

    private func emit(_ touch: UITouch) {
        guard let view else { return }
        let point = touch.location(in: view)
        let travel = max(1, view.bounds.width * 0.32)
        var dx = point.x - view.bounds.midX
        var dy = point.y - view.bounds.midY
        let mag = hypot(dx, dy)
        if mag > travel {
            dx = dx / mag * travel
            dy = dy / mag * travel
        }
        let out = deadzone(dx / travel, dy / travel)
        onChange(out.0, out.1)
    }

    override func reset() {
        super.reset()
        clickWork?.cancel()
        clickArmed = false
        if clickDown {
            clickDown = false
            onClick(false)
        }
        if touch != nil {
            touch = nil
            onTouch(false)
            onChange(0, 0)
        }
    }
}

private final class ZoneRecognizer: UIGestureRecognizer {
    var onChange: (CGPoint?) -> Void
    private var touch: UITouch?

    init(onChange: @escaping (CGPoint?) -> Void) {
        self.onChange = onChange
        super.init(target: nil, action: nil)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        guard touch == nil, let next = touches.first, let view else { return }
        touch = next
        state = .began
        onChange(next.location(in: view))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        guard let touch, touches.contains(touch), let view else { return }
        state = .changed
        onChange(touch.location(in: view))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        end(touches, cancelled: false)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        end(touches, cancelled: true)
    }

    private func end(_ touches: Set<UITouch>, cancelled: Bool) {
        guard let touch, touches.contains(touch) else { return }
        self.touch = nil
        onChange(nil)
        state = cancelled ? .cancelled : .ended
    }

    override func reset() {
        super.reset()
        if touch != nil {
            touch = nil
            onChange(nil)
        }
    }
}

private final class DragRecognizer: UIGestureRecognizer {
    var onBegan: () -> Void
    var onMoved: (CGFloat, CGFloat) -> Void
    var onEnded: () -> Void
    private var touch: UITouch?
    private var start: CGPoint = .zero
    private var began = false

    init(onBegan: @escaping () -> Void, onMoved: @escaping (CGFloat, CGFloat) -> Void, onEnded: @escaping () -> Void) {
        self.onBegan = onBegan
        self.onMoved = onMoved
        self.onEnded = onEnded
        super.init(target: nil, action: nil)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        guard touch == nil, let next = touches.first else { return }
        touch = next
        start = next.location(in: nil)
        state = .began
        began = true
        onBegan()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        guard let touch, touches.contains(touch) else { return }
        let point = touch.location(in: nil)
        state = .changed
        onMoved(point.x - start.x, point.y - start.y)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        end(touches, cancelled: false)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        end(touches, cancelled: true)
    }

    private func end(_ touches: Set<UITouch>, cancelled: Bool) {
        guard let touch, touches.contains(touch) else { return }
        self.touch = nil
        if began { onEnded() }
        began = false
        state = cancelled ? .cancelled : .ended
    }

    override func reset() {
        super.reset()
        if began {
            began = false
            touch = nil
            onEnded()
        }
    }
}
