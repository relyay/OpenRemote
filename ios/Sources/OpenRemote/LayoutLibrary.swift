import Foundation
import Observation

struct UserLayout: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var slots: [String: Slot]
    var faceCustom: Bool
    var centerCustom: Bool
    var hidden: [String]
    var extras: [ControlNode]
    var faceOnLeft: Bool

    init(
        id: UUID = UUID(),
        name: String,
        slots: [String: Slot],
        faceCustom: Bool,
        centerCustom: Bool,
        hidden: [String] = [],
        extras: [ControlNode] = [],
        faceOnLeft: Bool = false
    ) {
        self.id = id
        self.name = name
        self.slots = slots
        self.faceCustom = faceCustom
        self.centerCustom = centerCustom
        self.hidden = hidden
        self.extras = extras
        self.faceOnLeft = faceOnLeft
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        id = try box.decode(UUID.self, forKey: .id)
        name = try box.decode(String.self, forKey: .name)
        slots = try box.decode([String: Slot].self, forKey: .slots)
        faceCustom = try box.decode(Bool.self, forKey: .faceCustom)
        centerCustom = try box.decode(Bool.self, forKey: .centerCustom)
        hidden = try box.decodeIfPresent([String].self, forKey: .hidden) ?? []
        extras = try box.decodeIfPresent([ControlNode].self, forKey: .extras) ?? []
        faceOnLeft = try box.decodeIfPresent(Bool.self, forKey: .faceOnLeft) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(id, forKey: .id)
        try box.encode(name, forKey: .name)
        try box.encode(slots, forKey: .slots)
        try box.encode(faceCustom, forKey: .faceCustom)
        try box.encode(centerCustom, forKey: .centerCustom)
        try box.encode(hidden, forKey: .hidden)
        try box.encode(extras, forKey: .extras)
        try box.encode(faceOnLeft, forKey: .faceOnLeft)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, slots, faceCustom, centerCustom, hidden, extras, faceOnLeft
    }
}

enum LayoutPreset: String, CaseIterable, Identifiable {
    case standard
    case lefty

    var id: String { rawValue }

    var name: String {
        switch self {
        case .standard: L10n.presetStandard
        case .lefty: L10n.presetLefty
        }
    }

    @MainActor
    func apply(to layout: LayoutStore) {
        switch self {
        case .standard:
            layout.install(LayoutStore.defaults, dynamicFace: true, dynamicCenter: true, hidden: ["l3", "r3"])
        case .lefty:
            layout.install(
                LayoutStore.lefty,
                dynamicFace: true,
                dynamicCenter: true,
                hidden: ["l3", "r3"],
                faceOnLeft: true
            )
        }
    }
}

@MainActor
@Observable
final class LayoutLibrary {
    private(set) var customs: [UserLayout] = []

    init() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([UserLayout].self, from: data) {
            customs = decoded
            return
        }
        if let data = defaults.data(forKey: "layoutSlots2") ?? defaults.data(forKey: "layoutSlots"),
           let slots = try? JSONDecoder().decode([String: Slot].self, from: data) {
            customs = [UserLayout(
                id: UUID(),
                name: L10n.savedLayout,
                slots: slots,
                faceCustom: defaults.bool(forKey: "layoutFaceCustom"),
                centerCustom: defaults.bool(forKey: "layoutCenterCustom"),
                hidden: []
            )]
            persist()
        }
    }

    func add(
        name: String,
        slots: [String: Slot],
        faceCustom: Bool,
        centerCustom: Bool,
        hidden: [String] = [],
        extras: [ControlNode] = [],
        faceOnLeft: Bool = false
    ) -> UserLayout {
        let item = UserLayout(
            id: UUID(),
            name: uniqueName(name),
            slots: slots,
            faceCustom: faceCustom,
            centerCustom: centerCustom,
            hidden: hidden,
            extras: extras,
            faceOnLeft: faceOnLeft
        )
        customs.append(item)
        persist()
        return item
    }

    func update(
        _ id: UUID,
        slots: [String: Slot],
        faceCustom: Bool,
        centerCustom: Bool,
        hidden: [String],
        extras: [ControlNode] = [],
        faceOnLeft: Bool = false
    ) {
        guard let index = customs.firstIndex(where: { $0.id == id }) else { return }
        customs[index].slots = slots
        customs[index].faceCustom = faceCustom
        customs[index].centerCustom = centerCustom
        customs[index].hidden = hidden
        customs[index].extras = extras
        customs[index].faceOnLeft = faceOnLeft
        persist()
    }

    func uniqueName(_ name: String) -> String {
        var candidate = name
        var number = 2
        while customs.contains(where: { $0.name == candidate }) {
            candidate = "\(name) \(number)"
            number += 1
        }
        return candidate
    }

    func remove(_ id: UUID) {
        customs.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(customs) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    private static let storageKey = "layoutLibrary"
}
