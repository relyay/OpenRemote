import Foundation
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// `UTType.xml` makes the iOS document picker select folders. This is a flat file.
    static let openRemoteLayout: UTType = UTType(filenameExtension: "xml", conformingTo: .data) ?? .data
}

enum LayoutXML {
    static func encode(
        name: String,
        slots: [String: Slot],
        faceCustom: Bool,
        centerCustom: Bool,
        hidden: [String],
        extras: [ControlNode] = [],
        faceOnLeft: Bool = false
    ) -> String {
        var lines = [
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
            "<openremote-layout name=\"\(escape(name))\" faceCustom=\"\(faceCustom)\" centerCustom=\"\(centerCustom)\" faceOnLeft=\"\(faceOnLeft)\">",
        ]
        for id in slots.keys.sorted() {
            guard let slot = slots[id] else { continue }
            lines.append(controlLine(id: id, kind: id, slot: slot))
        }
        for extra in extras {
            lines.append(controlLine(id: extra.id, kind: extra.kind, slot: extra.slot))
        }
        for id in hidden.sorted() {
            lines.append("  <hidden id=\"\(escape(id))\"/>")
        }
        lines.append("</openremote-layout>")
        return lines.joined(separator: "\n")
    }

    static func decode(_ text: String) -> (name: String, slots: [String: Slot], faceCustom: Bool, centerCustom: Bool, hidden: [String], extras: [ControlNode], faceOnLeft: Bool)? {
        let parser = XMLParser(data: Data(text.utf8))
        let reader = LayoutXMLReader()
        parser.delegate = reader
        guard parser.parse(), !reader.slots.isEmpty || !reader.extras.isEmpty else { return nil }
        let name = reader.name.isEmpty ? L10n.untitled : reader.name
        return (name, reader.slots, reader.faceCustom, reader.centerCustom, reader.hidden, reader.extras, reader.faceOnLeft)
    }

    private static func controlLine(id: String, kind: String, slot: Slot) -> String {
        "  <control id=\"\(escape(id))\" kind=\"\(escape(kind))\" x=\"\(slot.x)\" y=\"\(slot.y)\" scale=\"\(slot.scale)\"/>"
    }

    private static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

private final class LayoutXMLReader: NSObject, XMLParserDelegate {
    var name = ""
    var faceCustom = true
    var centerCustom = true
    var slots: [String: Slot] = [:]
    var hidden: [String] = []
    var extras: [ControlNode] = []
    var faceOnLeft = false

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes: [String: String] = [:]
    ) {
        switch elementName {
        case "openremote-layout", "layout":
            if let value = attributes["name"], !value.isEmpty { name = value }
            if let value = attributes["faceCustom"] { faceCustom = value == "true" }
            if let value = attributes["centerCustom"] { centerCustom = value == "true" }
            if let value = attributes["faceOnLeft"] { faceOnLeft = value == "true" }
        case "control":
            let rawID = attributes["id"] ?? ""
            let kind = attributes["kind"] ?? rawID
            guard LayoutStore.controlIDs.contains(kind) else { return }
            let x = Double(attributes["x"] ?? "") ?? 0.5
            let y = Double(attributes["y"] ?? "") ?? 0.5
            let scale = Double(attributes["scale"] ?? "") ?? 1
            let slot = Slot(x: min(0.96, max(0.04, x)), y: min(0.96, max(0.04, y)), scale: min(2, max(0.45, scale)))
            if rawID.isEmpty || rawID == kind {
                slots[kind] = slot
            } else {
                extras.append(ControlNode(id: rawID, kind: kind, slot: slot))
            }
        case "hidden":
            if let id = attributes["id"], LayoutStore.controlIDs.contains(id) {
                hidden.append(id)
            }
        default:
            break
        }
    }
}

struct LayoutXMLFile: FileDocument {
    static var readableContentTypes: [UTType] { [.openRemoteLayout] }

    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.text = text
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
