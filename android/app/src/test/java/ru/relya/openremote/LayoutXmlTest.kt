package ru.relya.openremote

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class LayoutXmlTest {
    @Test
    fun roundTrip() {
        val data = LayoutData(
            slots = mapOf("a" to Slot(0.7, 0.8, 1.2), "ls" to Slot(0.3, 0.8)),
            faceCustom = true,
            centerCustom = false,
            hidden = setOf("l3"),
            extras = listOf(ControlNode("extra-1", "a", Slot(0.5, 0.5, 0.9))),
            faceOnLeft = true,
        )
        val (name, back) = LayoutXml.decode(LayoutXml.encode("Mine & \"yours\"", data))!!
        assertEquals("Mine & \"yours\"", name)
        assertEquals(data, back)
    }

    /** A file written by the iOS app. */
    @Test
    fun readsIosFile() {
        val text = """
            <?xml version="1.0" encoding="UTF-8"?>
            <openremote-layout name="Racing" faceCustom="false" centerCustom="true" faceOnLeft="false">
              <control id="lt" kind="lt" x="0.05" y="0.06" scale="1.75"/>
              <control id="rt" kind="rt" x="1.5" y="0.06" scale="9"/>
              <control id="bogus" kind="nope" x="0.5" y="0.5" scale="1"/>
              <hidden id="r3"/>
            </openremote-layout>
        """.trimIndent()
        val (name, data) = LayoutXml.decode(text)!!
        assertEquals("Racing", name)
        assertEquals(false, data.faceCustom)
        assertEquals(true, data.centerCustom)
        assertEquals(setOf("lt", "rt"), data.slots.keys)
        assertEquals(Slot(0.96, 0.06, 2.0), data.slots["rt"])
        assertEquals(setOf("r3"), data.hidden)
    }

    @Test
    fun rejectsOtherFiles() {
        assertNull(LayoutXml.decode("not xml"))
        assertNull(LayoutXml.decode("<openremote-layout name=\"x\"/>"))
        assertNotNull(LayoutXml.decode("<layout><control id=\"a\"/></layout>"))
    }

    @Test
    fun refusesDoctype() {
        val text = """<?xml version="1.0"?><!DOCTYPE x [<!ENTITY e SYSTEM "file:///etc/passwd">]>""" +
            """<openremote-layout name="&e;"><control id="a"/></openremote-layout>"""
        val parsed = LayoutXml.decode(text)
        assertTrue(parsed == null || !parsed.first.contains("root"))
    }
}
