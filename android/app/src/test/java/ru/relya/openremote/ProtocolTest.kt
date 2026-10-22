package ru.relya.openremote

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ProtocolTest {
    @Test
    fun frameMatchesHostLayout() {
        val pad = PadSnapshot(
            lx = 1.0, ly = -1.0, rx = 0.5, ry = 0.0, lt = 1.0, rt = 0.0,
            hatX = -1, hatY = 1,
            buttons = PadSnapshot.A or PadSnapshot.R3,
        )
        val expected = byteArrayOf(
            0xFF.toByte(), 0x7F, // 32767
            0x01, 0x80.toByte(), // -32767
            0x00, 0x40, // 16384
            0x00, 0x00,
            0xFF.toByte(), 0x00,
            0x01, 0x04, // A | R3 = 0x0401
            0xFF.toByte(), 0x01,
        )
        assertArrayEquals(expected, pad.frame())
    }

    @Test
    fun frameClampsOutOfRange() {
        val f = PadSnapshot(lx = 3.0, lt = -1.0, hatX = 5).frame()
        assertEquals(0x7FFF, (f[0].toInt() and 0xFF) or (f[1].toInt() shl 8 and 0xFF00))
        assertEquals(0, f[8].toInt())
        assertEquals(1, f[12].toInt())
    }

    @Test
    fun deadzoneScalesFromEdge() {
        assertEquals(0.0 to 0.0, deadzone(0.1, 0.0, 0.14, 1.0))
        val (x, y) = deadzone(1.0, 0.0, 0.14, 1.0)
        assertEquals(1.0, x, 1e-9)
        assertEquals(0.0, y, 1e-9)
        assertEquals(0.5, deadzone(0.57, 0.0, 0.14, 1.0).first, 1e-9)
    }

    @Test
    fun connectionCodes() {
        assertEquals("192.168.1.5" to "1337", ConnectionCode.parse("openremote://192.168.1.5:1337"))
        assertEquals("10.0.0.2" to "1337", ConnectionCode.parse("openremote://10.0.0.2"))
        assertEquals("pc.local" to "9000", ConnectionCode.parse("ws://pc.local:9000/ws"))
        assertEquals("10.0.0.2" to "80", ConnectionCode.parse(" 10.0.0.2:80 "))
        assertNull(ConnectionCode.parse("ftp://x:1"))
        assertNull(ConnectionCode.parse("10.0.0.2:99999"))
        assertNull(ConnectionCode.parse("hello"))
    }
}
