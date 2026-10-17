import Foundation
import GameController
import Network
import Observation
import UIKit

enum LinkState: Equatable {
    case offline
    case connecting
    case live
    case taken
    case badAddress
    case needAddress
}

@MainActor
@Observable
final class Session {
    var host: String
    var portText: String
    var playing = false
    var linked = false
    var controllerConnected = false
    var linkState: LinkState = .offline
    var pad = PadSnapshot()

    private var connection: NWConnection?
    private var udp: NWConnection?
    private var seq: UInt16 = 0
    private var socketGeneration = 0
    private var wantLink = false
    private var lastQueued: Data?
    private var outbound: [Data] = []
    private var sending = false
    private var reconnectTask: Task<Void, Never>?
    private var controller: GCController?
    private var tokens: [NSObjectProtocol] = []
    private var holdRefresh: Task<Void, Never>?

    init() {
        let defaults = UserDefaults.standard
        host = defaults.string(forKey: "host") ?? ""
        portText = defaults.string(forKey: "port") ?? "1337"
    }

    var statusText: String {
        if controllerConnected && linkState == .live { return L10n.connectedPad(host) }
        switch linkState {
        case .offline: return L10n.offline
        case .connecting: return L10n.connecting
        case .live: return L10n.connectedTo(host)
        case .taken: return L10n.taken
        case .badAddress: return L10n.badAddress
        case .needAddress: return L10n.needAddress
        }
    }

    func connect() {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, UInt16(portText) != nil else {
            linkState = .needAddress
            return
        }
        host = trimmed
        let defaults = UserDefaults.standard
        defaults.set(host, forKey: "host")
        defaults.set(portText, forKey: "port")
        playing = true
        wantLink = true
        UIApplication.shared.isIdleTimerDisabled = true
        watchControllers()
        openSocket()
    }

    func disconnect() {
        wantLink = false
        reconnectTask?.cancel()
        releasePad()
        connection?.cancel()
        connection = nil
        udp?.cancel()
        udp = nil
        linked = false
        outbound.removeAll()
        lastQueued = nil
        sending = false
        holdRefresh?.cancel()
        holdRefresh = nil
        playing = false
        controller = nil
        controllerConnected = false
        linkState = .offline
        UIApplication.shared.isIdleTimerDisabled = false
    }

    func setButton(_ bit: UInt16, down: Bool) {
        guard !controllerConnected else { return }
        if down {
            pad.buttons |= bit
        } else {
            pad.buttons &= ~bit
        }
        send()
    }

    func setLeft(x: Double, y: Double) {
        guard !controllerConnected else { return }
        pad.lx = x
        pad.ly = y
        send()
    }

    func setRight(x: Double, y: Double) {
        guard !controllerConnected else { return }
        pad.rx = x
        pad.ry = y
        send()
    }

    func setHat(x: Int8, y: Int8) {
        guard !controllerConnected else { return }
        pad.hatX = x
        pad.hatY = y
        send()
    }

    func setTrigger(left: Bool, value: Double) {
        guard !controllerConnected else { return }
        if left {
            pad.lt = value
        } else {
            pad.rt = value
        }
        send()
    }

    func releasePad() {
        pad = PadSnapshot()
        send()
    }

    private func openSocket() {
        reconnectTask?.cancel()
        socketGeneration += 1
        let generation = socketGeneration
        linkState = .connecting
        linked = false
        outbound.removeAll()
        lastQueued = nil
        sending = false
        let previous = connection
        connection = nil
        previous?.stateUpdateHandler = nil
        previous?.cancel()

        guard let url = URL(string: "ws://\(host):\(portText)/ws") else {
            linkState = .badAddress
            return
        }
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        let web = NWProtocolWebSocket.Options()
        web.autoReplyPing = true
        let parameters = NWParameters(tls: nil, tcp: tcp)
        parameters.defaultProtocolStack.applicationProtocols.insert(web, at: 0)
        let conn = NWConnection(to: .url(url), using: parameters)
        connection = conn
        conn.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self, self.socketGeneration == generation else { return }
                self.connectionState(state, conn, generation)
            }
        }
        conn.start(queue: .main)

        let udpConn = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(portText)!, using: .udp)
        udp = udpConn
        udpConn.start(queue: .main)
    }

    private func connectionState(_ state: NWConnection.State, _ conn: NWConnection, _ generation: Int) {
        guard connection === conn else { return }
        switch state {
        case .ready:
            didOpen()
            receive(conn, generation)
        case .failed, .cancelled:
            didClose(0)
        default:
            break
        }
    }

    private func receive(_ conn: NWConnection, _ generation: Int) {
        conn.receiveMessage { [weak self] data, context, _, error in
            let code = closeCode(data: data, context: context)
            Task { @MainActor in
                guard let self, self.socketGeneration == generation, self.connection === conn else { return }
                if code == 4000 {
                    self.didClose(4000)
                    return
                }
                if error != nil {
                    self.didClose(0)
                    return
                }
                self.receive(conn, generation)
            }
        }
    }

    private func didOpen() {
        guard wantLink else { return }
        linked = true
        linkState = .live
        lastQueued = nil
        outbound.removeAll()
        sending = false
        send()
        startHeartbeat()
    }

    private func didClose(_ code: Int) {
        holdRefresh?.cancel()
        holdRefresh = nil
        linked = false
        guard wantLink else { return }
        if code == 4000 {
            wantLink = false
            linkState = .taken
            return
        }
        linkState = .offline
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        guard wantLink else { return }
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.openSocket() }
        }
    }

    private func send(force: Bool = false) {
        sendUDP()
        guard linked, connection != nil else { return }
        let frame = pad.frame()
        if !force, frame == lastQueued { return }
        lastQueued = frame
        if outbound.count >= 2 {
            outbound.removeFirst(outbound.count - 1)
        }
        if let last = outbound.last, sameDigital(last, frame) {
            outbound[outbound.count - 1] = frame
        } else {
            outbound.append(frame)
        }
        pump()
    }

    private func sendUDP() {
        guard linked, let udp else { return }
        seq &+= 1
        var packet = Data()
        var n = seq.littleEndian
        withUnsafeBytes(of: &n) { packet.append(contentsOf: $0) }
        packet.append(pad.frame())
        udp.send(content: packet, completion: .idempotent)
    }

    /// Repeats the latest state. A lost Wi-Fi packet is replaced a few
    /// milliseconds later instead of blocking every click behind it.
    private func startHeartbeat() {
        holdRefresh?.cancel()
        holdRefresh = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(8))
                guard !Task.isCancelled else { return }
                await MainActor.run { self?.sendUDP() }
            }
        }
    }

    /// Bytes 8...13 are triggers, buttons, and the d-pad. Stick motion can
    /// replace a queued frame. A button edge cannot, or a tap disappears.
    private func sameDigital(_ a: Data, _ b: Data) -> Bool {
        a.count >= 14 && b.count >= 14 && a.subdata(in: 8..<14) == b.subdata(in: 8..<14)
    }

    private func pump() {
        guard !sending, linked, let connection, !outbound.isEmpty else { return }
        sending = true
        let frame = outbound.removeFirst()
        let meta = NWProtocolWebSocket.Metadata(opcode: .binary)
        let context = NWConnection.ContentContext(identifier: "pad", metadata: [meta])
        connection.send(content: frame, contentContext: context, isComplete: true, completion: .contentProcessed { [weak self] error in
            Task { @MainActor in
                guard let self, self.connection === connection else { return }
                self.sending = false
                guard error == nil, self.linked else { return }
                self.pump()
            }
        })
    }

    private func watchControllers() {
        guard tokens.isEmpty else {
            attachCurrentController()
            return
        }
        let center = NotificationCenter.default
        tokens.append(center.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.attachCurrentController() }
        })
        tokens.append(center.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.controller = nil
                self.controllerConnected = false
                self.releasePad()
                self.attachCurrentController()
            }
        })
        tokens.append(center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.releasePad() }
        })
        tokens.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.pullController() }
        })
        attachCurrentController()
    }

    private func attachCurrentController() {
        if let existing = GCController.controllers().first(where: { $0.extendedGamepad != nil }) {
            bind(existing)
        }
    }

    private func bind(_ controller: GCController) {
        guard controller.extendedGamepad != nil else { return }
        self.controller = controller
        controllerConnected = true
        controller.extendedGamepad?.valueChangedHandler = { [weak self] gamepad, _ in
            let snapshot = PadSnapshot(gamepad: gamepad)
            Task { @MainActor in
                guard let self else { return }
                self.controllerConnected = true
                self.pad = snapshot
                self.send()
            }
        }
        pullController()
    }

    private func pullController() {
        guard let gamepad = controller?.extendedGamepad else { return }
        controllerConnected = true
        pad = PadSnapshot(gamepad: gamepad)
        send()
    }
}

private func closeCode(data: Data?, context: NWConnection.ContentContext?) -> Int {
    guard let meta = context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata,
          case .close = meta.opcode,
          let data, data.count >= 2 else { return 0 }
    return Int(data[0]) << 8 | Int(data[1])
}
