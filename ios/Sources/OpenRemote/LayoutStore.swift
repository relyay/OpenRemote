import CoreGraphics
import Foundation
import Observation

struct Slot: Codable, Equatable {
    var x: Double
    var y: Double
    var scale: Double = 1
}

struct ControlNode: Codable, Identifiable, Equatable {
    var id: String
    var kind: String
    var slot: Slot
}

@MainActor
@Observable
final class LayoutStore {
    var editing = false
    var panel = false
    var selected: String?
    private(set) var faceCustom = false
    private(set) var centerCustom = false
    private(set) var faceOnLeft = false
    private(set) var hidden: Set<String> = ["l3", "r3"]
    private(set) var extras: [ControlNode] = []
    private(set) var slots: [String: Slot]
    private var dragOrigin: [String: Slot] = [:]
    private var canvasSize: CGSize = .zero
    private(set) var changed = false

    init() {
        let defaults = UserDefaults.standard
        let custom = defaults.bool(forKey: Self.faceKey)
        let center = defaults.bool(forKey: Self.centerKey)
        let onLeft = defaults.bool(forKey: Self.faceSideKey)
        let data = defaults.data(forKey: Self.slotsKey) ?? defaults.data(forKey: Self.legacySlotsKey)
        if let data, let decoded = try? JSONDecoder().decode([String: Slot].self, from: data) {
            var merged = Self.defaults
            for (key, value) in decoded where merged[key] != nil {
                var slot = value
                if slot.scale < 0.4 { slot.scale = 1 }
                if !custom, Self.faceIDs.contains(key) {
                    slot.x = Self.defaults[key]?.x ?? slot.x
                    slot.y = Self.defaults[key]?.y ?? slot.y
                }
                if !center, Self.centerIDs.contains(key) {
                    slot.x = Self.defaults[key]?.x ?? slot.x
                    slot.y = Self.defaults[key]?.y ?? slot.y
                }
                merged[key] = slot
            }
            slots = merged
        } else {
            slots = Self.defaults
        }
        faceCustom = custom
        centerCustom = center
        faceOnLeft = onLeft
    }

    func kind(of id: String) -> String {
        extras.first { $0.id == id }?.kind ?? id
    }

    func slot(_ id: String, in size: CGSize = .zero) -> Slot {
        if let extra = extras.first(where: { $0.id == id }) {
            var slot = extra.slot
            if slot.scale < 0.4 { slot.scale = 1 }
            return slot
        }
        var slot = slots[id] ?? Self.defaults[id] ?? Slot(x: 0.5, y: 0.5, scale: 1)
        if slot.scale < 0.4 { slot.scale = 1 }
        guard size.width > 1, size.height > 1 else { return slot }
        let point: CGPoint
        if !faceCustom, Self.faceIDs.contains(id) {
            point = Self.facePoint(id, in: size, onLeft: faceOnLeft)
        } else if !centerCustom, Self.centerIDs.contains(id) {
            point = Self.centerPoint(id, in: size)
        } else {
            return slot
        }
        slot.x = min(0.96, max(0.04, Double(point.x / size.width)))
        slot.y = min(0.96, max(0.04, Double(point.y / size.height)))
        return slot
    }

    func beginDrag(_ id: String, size: CGSize) {
        if !faceCustom, Self.faceIDs.contains(id) {
            freezeFace(in: size)
        }
        if !centerCustom, Self.centerIDs.contains(id) {
            freezeCenter(in: size)
        }
        selected = id
        if dragOrigin[id] == nil {
            dragOrigin[id] = slot(id, in: size)
        }
    }

    func drag(_ id: String, dx: CGFloat, dy: CGFloat, size: CGSize) {
        guard let origin = dragOrigin[id] else { return }
        let width = max(size.width, 1)
        let height = max(size.height, 1)
        move(id, x: origin.x + Double(dx) / width, y: origin.y + Double(dy) / height)
    }

    func endDrag(_ id: String) {
        dragOrigin[id] = nil
    }

    func move(_ id: String, x: Double, y: Double) {
        let x = min(0.96, max(0.04, x))
        let y = min(0.96, max(0.04, y))
        if let index = extras.firstIndex(where: { $0.id == id }) {
            extras[index].slot.x = x
            extras[index].slot.y = y
            changed = true
            save()
            return
        }
        var slot = slot(id)
        slot.x = x
        slot.y = y
        slots[id] = slot
        changed = true
        save()
    }

    func setItemScale(_ id: String, _ value: Double) {
        let scale = min(2, max(0.45, value))
        if let index = extras.firstIndex(where: { $0.id == id }) {
            extras[index].slot.scale = scale
            selected = id
            changed = true
            save()
            return
        }
        var slot = slot(id)
        slot.scale = scale
        slots[id] = slot
        selected = id
        changed = true
        save()
    }

    func remember(_ size: CGSize) {
        guard size.width > 1, size.height > 1 else { return }
        canvasSize = size
    }

    /// Copies a preset or a saved layout into the live pad.
    func install(
        _ incoming: [String: Slot],
        dynamicFace: Bool,
        dynamicCenter: Bool,
        hidden: Set<String> = [],
        extras: [ControlNode] = [],
        faceOnLeft: Bool = false
    ) {
        var merged = Self.defaults
        for (key, value) in incoming where merged[key] != nil {
            var slot = value
            if slot.scale < 0.4 { slot.scale = 1 }
            merged[key] = slot
        }
        slots = merged
        faceCustom = !dynamicFace
        centerCustom = !dynamicCenter
        self.hidden = hidden
        self.extras = extras
        self.faceOnLeft = faceOnLeft
        selected = nil
        dragOrigin = [:]
        editing = false
        panel = false
        changed = false
        save()
    }

    func hide(_ id: String) {
        var next = hidden
        next.insert(id)
        hidden = next
        if selected == id { selected = nil }
        changed = true
        save()
    }

    func show(_ id: String) {
        var next = hidden
        next.remove(id)
        hidden = next
        changed = true
        save()
    }

    func add(_ kind: String) {
        guard Self.controlIDs.contains(kind) else { return }
        let base = hidden.contains(kind)
            ? (Self.defaults[kind] ?? Slot(x: 0.5, y: 0.5))
            : slot(kind)
        let index = extras.filter { $0.kind == kind }.count + (hidden.contains(kind) ? 0 : 1)
        let nudge = 0.07 * Double(index)
        let node = ControlNode(
            id: UUID().uuidString,
            kind: kind,
            slot: Slot(
                x: min(0.92, max(0.08, base.x + (index == 0 ? 0 : nudge))),
                y: min(0.9, max(0.1, base.y + (index == 0 ? 0 : nudge * 0.35))),
                scale: base.scale
            )
        )
        extras.append(node)
        selected = node.id
        changed = true
        save()
    }

    func remove(_ id: String) {
        if let index = extras.firstIndex(where: { $0.id == id }) {
            extras.remove(at: index)
            if selected == id { selected = nil }
            changed = true
            save()
            return
        }
        hide(id)
    }

    /// Writes the on-screen positions, including the computed diamond and center row.
    func bake() -> BakedLayout {
        if canvasSize.width > 1 {
            if !faceCustom { freezeFace(in: canvasSize) }
            if !centerCustom { freezeCenter(in: canvasSize) }
        }
        return BakedLayout(
            slots: slots,
            faceCustom: faceCustom,
            centerCustom: centerCustom,
            hidden: hidden.sorted(),
            extras: extras,
            faceOnLeft: faceOnLeft
        )
    }

    func reset() {
        slots = Self.defaults
        faceCustom = false
        centerCustom = false
        faceOnLeft = false
        hidden = ["l3", "r3"]
        extras = []
        selected = nil
        dragOrigin = [:]
        changed = true
        save()
    }

    private func freezeFace(in size: CGSize) {
        guard size.width > 1, size.height > 1 else { return }
        for id in Self.faceIDs {
            slots[id] = slot(id, in: size)
        }
        faceCustom = true
        save()
    }

    private func freezeCenter(in size: CGSize) {
        guard size.width > 1, size.height > 1 else { return }
        for id in Self.centerIDs {
            slots[id] = slot(id, in: size)
        }
        centerCustom = true
        save()
    }

    private func save() {
        let defaults = UserDefaults.standard
        if let data = try? JSONEncoder().encode(slots) {
            defaults.set(data, forKey: Self.slotsKey)
        }
        defaults.set(faceCustom, forKey: Self.faceKey)
        defaults.set(centerCustom, forKey: Self.centerKey)
        defaults.set(faceOnLeft, forKey: Self.faceSideKey)
    }

    /// Equal point offsets. Fractions of a landscape canvas stretch the diamond.
    /// `onLeft` mirrors the cluster the way Lefty mirrors Standard.
    private static func facePoint(_ id: String, in size: CGSize, onLeft: Bool) -> CGPoint {
        let anchor: CGFloat = onLeft ? 0.10 : 0.90
        let center = CGPoint(x: size.width * anchor, y: size.height * 0.66)
        let side: CGFloat = onLeft ? -1 : 1
        switch id {
        case "y": return CGPoint(x: center.x, y: center.y - faceGap)
        case "x": return CGPoint(x: center.x - side * faceGap, y: center.y)
        case "b": return CGPoint(x: center.x + side * faceGap, y: center.y)
        case "a": return CGPoint(x: center.x, y: center.y + faceGap)
        default: return center
        }
    }

    /// Kept in points so the row stays above the middle on a short landscape canvas.
    private static func centerPoint(_ id: String, in size: CGSize) -> CGPoint {
        let origin = CGPoint(x: size.width * 0.50, y: min(size.height * 0.14, 52))
        switch id {
        case "back": return CGPoint(x: origin.x - centerGap, y: origin.y)
        case "start": return CGPoint(x: origin.x + centerGap, y: origin.y)
        default: return origin
        }
    }

    private static let faceGap: CGFloat = 54
    private static let centerGap: CGFloat = 96
    nonisolated static let controlIDs: Set<String> = [
        "lt", "lb", "rt", "rb", "dpad", "y", "x", "b", "a", "ls", "rs", "l3", "r3", "back", "guide", "start",
    ]
    private static let faceIDs: Set<String> = ["a", "b", "x", "y"]
    private static let centerIDs: Set<String> = ["back", "guide", "start"]
    private static let slotsKey = "layoutSlots2"
    private static let legacySlotsKey = "layoutSlots"
    private static let faceKey = "layoutFaceCustom"
    private static let centerKey = "layoutCenterCustom"
    private static let faceSideKey = "layoutFaceOnLeft"

    /// Standard, with the d-pad and sticks moved to the opposite side.
    static var lefty: [String: Slot] {
        var slots = defaults
        for id in ["dpad", "ls", "rs", "l3", "r3"] {
            if var slot = slots[id] {
                slot.x = 1 - slot.x
                slots[id] = slot
            }
        }
        return slots
    }

    static let defaults: [String: Slot] = [
        "lt": Slot(x: 0.05, y: 0.06, scale: 1.75),
        "lb": Slot(x: 0.16, y: 0.30, scale: 1.3),
        "rt": Slot(x: 0.95, y: 0.06, scale: 1.75),
        "rb": Slot(x: 0.84, y: 0.30, scale: 1.3),
        "dpad": Slot(x: 0.09, y: 0.64),
        "y": Slot(x: 0.78, y: 0.58),
        "x": Slot(x: 0.72, y: 0.72),
        "b": Slot(x: 0.84, y: 0.72),
        "a": Slot(x: 0.78, y: 0.86),
        "ls": Slot(x: 0.30, y: 0.82),
        "rs": Slot(x: 0.70, y: 0.82),
        "l3": Slot(x: 0.08, y: 0.88),
        "r3": Slot(x: 0.92, y: 0.88),
        "back": Slot(x: 0.36, y: 0.14),
        "guide": Slot(x: 0.50, y: 0.14),
        "start": Slot(x: 0.64, y: 0.14),
    ]
}

struct BakedLayout {
    var slots: [String: Slot]
    var faceCustom: Bool
    var centerCustom: Bool
    var hidden: [String]
    var extras: [ControlNode]
    var faceOnLeft: Bool
}
