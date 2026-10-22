package ru.relya.openremote

import android.content.SharedPreferences
import android.os.Handler
import android.os.Looper
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.edit
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okio.ByteString.Companion.toByteString
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetSocketAddress
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

enum class LinkState { Offline, Connecting, Live, Taken, BadAddress, NeedAddress }

/**
 * The link to the host. The WebSocket owns the pad: the host serves one phone
 * and closes the previous one with code 4000. Snapshots also go over UDP with
 * a sequence number, so a lost Wi-Fi packet never delays the next one.
 *
 * Every public member is used from the main thread.
 */
class Session(private val prefs: SharedPreferences) {
    var host by mutableStateOf(prefs.getString(KEY_HOST, "").orEmpty())
    var port by mutableStateOf(prefs.getString(KEY_PORT, "1337").orEmpty())
    var playing by mutableStateOf(false)
        private set
    var linkState by mutableStateOf(LinkState.Offline)
        private set
    var controllerConnected by mutableStateOf(false)
        private set
    var pad by mutableStateOf(PadSnapshot())
        private set

    val linked get() = linkState == LinkState.Live

    private val main = Handler(Looper.getMainLooper())
    private val net = Executors.newSingleThreadExecutor { Thread(it, "openremote-udp") }
    private val client = OkHttpClient.Builder()
        .connectTimeout(3, TimeUnit.SECONDS)
        .build()

    private var socket: WebSocket? = null
    private var generation = 0
    private var wantLink = false
    private var lastQueued: PadSnapshot? = null
    private var seq = 0

    // Only touched on the net thread.
    private var udp: DatagramSocket? = null
    private var udpTarget: InetSocketAddress? = null

    private val heartbeat = object : Runnable {
        override fun run() {
            if (!linked) return
            sendUdp()
            main.postDelayed(this, if (pad == PadSnapshot()) IDLE_BEAT_MS else ACTIVE_BEAT_MS)
        }
    }
    private val reconnect = Runnable { openSocket() }

    fun connect() {
        val trimmed = host.trim()
        if (trimmed.isEmpty() || port.toIntOrNull() !in 1..65535) {
            linkState = LinkState.NeedAddress
            return
        }
        host = trimmed
        prefs.edit {
            putString(KEY_HOST, host)
            putString(KEY_PORT, port)
        }
        playing = true
        wantLink = true
        openSocket()
    }

    fun disconnect() {
        wantLink = false
        main.removeCallbacks(reconnect)
        releasePad()
        generation++
        socket?.close(1000, null)
        socket = null
        closeUdp()
        main.removeCallbacks(heartbeat)
        lastQueued = null
        playing = false
        linkState = LinkState.Offline
    }

    fun setButton(bit: Int, down: Boolean) = touch { pad.with(bit, down) }
    fun setLeft(x: Double, y: Double) = touch { pad.copy(lx = x, ly = y) }
    fun setRight(x: Double, y: Double) = touch { pad.copy(rx = x, ry = y) }
    fun setHat(x: Int, y: Int) = touch { pad.copy(hatX = x, hatY = y) }
    fun setTrigger(left: Boolean, value: Double) = touch { if (left) pad.copy(lt = value) else pad.copy(rt = value) }

    fun releasePad() {
        pad = PadSnapshot()
        send()
    }

    /** A hardware controller attached to the phone replaces the touch controls. */
    fun setController(connected: Boolean) {
        if (controllerConnected == connected) return
        controllerConnected = connected
        releasePad()
    }

    fun applyController(snapshot: PadSnapshot) {
        controllerConnected = true
        if (snapshot == pad) return
        pad = snapshot
        send()
    }

    fun close() {
        disconnect()
        net.shutdown()
        client.dispatcher.executorService.shutdown()
    }

    private inline fun touch(next: () -> PadSnapshot) {
        if (controllerConnected) return
        pad = next()
        send()
    }

    private fun openSocket() {
        main.removeCallbacks(reconnect)
        main.removeCallbacks(heartbeat)
        val gen = ++generation
        linkState = LinkState.Connecting
        lastQueued = null
        socket?.cancel()
        socket = null

        val request = runCatching { Request.Builder().url("ws://${hostForUrl()}:$port/ws").build() }.getOrNull()
        val portNumber = port.toIntOrNull()
        if (request == null || portNumber == null) {
            linkState = LinkState.BadAddress
            return
        }
        val target = host
        net.execute {
            udp?.close()
            udp = runCatching { DatagramSocket() }.getOrNull()
            udpTarget = runCatching { InetSocketAddress(target, portNumber) }.getOrNull()
        }
        socket = client.newWebSocket(request, object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) = onMain(gen) { didOpen() }

            override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
                webSocket.close(1000, null)
                onMain(gen) { didClose(code) }
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) = onMain(gen) { didClose(code) }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) =
                onMain(gen) { didClose(0) }
        })
    }

    private fun onMain(gen: Int, block: () -> Unit) {
        main.post { if (gen == generation) block() }
    }

    private fun didOpen() {
        if (!wantLink) return
        linkState = LinkState.Live
        lastQueued = null
        send()
        main.removeCallbacks(heartbeat)
        main.post(heartbeat)
    }

    private fun didClose(code: Int) {
        main.removeCallbacks(heartbeat)
        // A close is reported by both onClosing and onClosed. Retire this socket after the first.
        generation++
        socket = null
        if (!wantLink) return
        if (code == CLOSE_REPLACED) {
            // Another phone took the pad. Reconnecting would steal it back.
            wantLink = false
            closeUdp()
            linkState = LinkState.Taken
            return
        }
        linkState = LinkState.Offline
        main.postDelayed(reconnect, RECONNECT_MS)
    }

    private fun send() {
        sendUdp()
        val ws = socket ?: return
        if (!linked || pad == lastQueued) return
        lastQueued = pad
        ws.send(pad.frame().toByteString())
    }

    private fun sendUdp() {
        if (!linked) return
        seq = (seq + 1) and 0xFFFF
        val packet = ByteArray(2 + PadSnapshot.FRAME_SIZE)
        packet[0] = (seq and 0xFF).toByte()
        packet[1] = (seq shr 8).toByte()
        pad.frame().copyInto(packet, 2)
        net.execute {
            val socket = udp ?: return@execute
            val target = udpTarget ?: return@execute
            runCatching { socket.send(DatagramPacket(packet, packet.size, target)) }
        }
    }

    private fun closeUdp() {
        net.execute {
            udp?.close()
            udp = null
            udpTarget = null
        }
    }

    private fun hostForUrl() = if (':' in host && !host.startsWith("[")) "[$host]" else host

    private companion object {
        const val KEY_HOST = "host"
        const val KEY_PORT = "port"
        const val CLOSE_REPLACED = 4000
        const val RECONNECT_MS = 400L

        // The host prefers UDP while a datagram arrived in the last 300 ms.
        // A held control repeats fast so a lost packet is replaced at once;
        // a pad at rest only keeps that window open.
        const val ACTIVE_BEAT_MS = 8L
        const val IDLE_BEAT_MS = 100L
    }
}
