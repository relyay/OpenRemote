package ru.relya.openremote

import org.xml.sax.Attributes
import org.xml.sax.helpers.DefaultHandler
import java.io.StringReader
import javax.xml.parsers.SAXParserFactory
import org.xml.sax.InputSource

/** The `<openremote-layout>` file. The iOS app reads and writes the same format. */
object LayoutXml {
    fun encode(name: String, d: LayoutData): String = buildString {
        appendLine("""<?xml version="1.0" encoding="UTF-8"?>""")
        appendLine(
            """<openremote-layout name="${esc(name)}" faceCustom="${d.faceCustom}" """ +
                """centerCustom="${d.centerCustom}" faceOnLeft="${d.faceOnLeft}">""",
        )
        for (id in d.slots.keys.sorted()) appendLine(control(id, id, d.slots.getValue(id)))
        for (e in d.extras) appendLine(control(e.id, e.kind, e.slot))
        for (id in d.hidden.sorted()) appendLine("""  <hidden id="${esc(id)}"/>""")
        append("</openremote-layout>")
    }

    /** Returns the name and layout, or null when the text is not a layout. */
    fun decode(text: String): Pair<String, LayoutData>? {
        val reader = Reader()
        val ok = runCatching {
            val factory = SAXParserFactory.newInstance()
            // A layout never needs a DTD. Refusing one keeps external entities out.
            runCatching { factory.setFeature("http://apache.org/xml/features/disallow-doctype-decl", true) }
            factory.newSAXParser().parse(InputSource(StringReader(text)), reader)
        }.isSuccess
        if (!ok || (reader.slots.isEmpty() && reader.extras.isEmpty())) return null
        return reader.name to LayoutData(
            slots = reader.slots,
            faceCustom = reader.faceCustom,
            centerCustom = reader.centerCustom,
            hidden = reader.hidden,
            extras = reader.extras,
            faceOnLeft = reader.faceOnLeft,
        )
    }

    private fun control(id: String, kind: String, s: Slot) =
        """  <control id="${esc(id)}" kind="${esc(kind)}" x="${s.x}" y="${s.y}" scale="${s.scale}"/>"""

    private fun esc(text: String) = text
        .replace("&", "&amp;")
        .replace("\"", "&quot;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")

    private class Reader : DefaultHandler() {
        var name = ""
        var faceCustom = true
        var centerCustom = true
        var faceOnLeft = false
        val slots = mutableMapOf<String, Slot>()
        val hidden = mutableSetOf<String>()
        val extras = mutableListOf<ControlNode>()

        override fun startElement(uri: String?, localName: String?, qName: String, attrs: Attributes) {
            fun attr(key: String): String? = attrs.getValue(key)
            when (qName) {
                "openremote-layout", "layout" -> {
                    attr("name")?.takeIf { it.isNotEmpty() }?.let { name = it }
                    attr("faceCustom")?.let { faceCustom = it == "true" }
                    attr("centerCustom")?.let { centerCustom = it == "true" }
                    attr("faceOnLeft")?.let { faceOnLeft = it == "true" }
                }
                "control" -> {
                    val rawId = attr("id").orEmpty()
                    val kind = attr("kind") ?: rawId
                    if (kind !in Controls.ids) return
                    val slot = Slot(
                        x = clampX(attr("x")?.toDoubleOrNull() ?: 0.5),
                        y = clampX(attr("y")?.toDoubleOrNull() ?: 0.5),
                        scale = clampScale(attr("scale")?.toDoubleOrNull() ?: 1.0),
                    )
                    if (rawId.isEmpty() || rawId == kind) {
                        slots[kind] = slot
                    } else {
                        extras += ControlNode(rawId, kind, slot)
                    }
                }
                "hidden" -> attr("id")?.takeIf { it in Controls.ids }?.let { hidden += it }
            }
        }
    }
}

/** Reads what the host prints: `openremote://ip:port`, a ws or http URL, or `ip:port`. */
object ConnectionCode {
    fun parse(raw: String): Pair<String, String>? {
        val text = raw.trim()
        val scheme = text.substringBefore("://", "").lowercase()
        if (scheme.isNotEmpty()) {
            if (scheme !in setOf("openremote", "ws", "http", "https")) return null
            val authority = text.substringAfter("://").substringBefore('/').substringBefore('?')
            return split(authority) ?: authority.takeIf { it.isNotEmpty() && ':' !in it }?.let { it to "1337" }
        }
        return split(text)
    }

    private fun split(text: String): Pair<String, String>? {
        val colon = text.lastIndexOf(':')
        if (colon <= 0) return null
        val host = text.substring(0, colon)
        val port = text.substring(colon + 1)
        val n = port.toIntOrNull() ?: return null
        if (n !in 1..65535) return null
        return host to port
    }
}
