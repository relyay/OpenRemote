import Foundation
import GameController

/// One full pad snapshot. The server applies the difference, so every frame is complete.
/// Positive stick and hat Y is down, matching the Linux Xbox 360 driver.
struct PadSnapshot: Equatable, Sendable {
    var lx: Double = 0
    var ly: Double = 0
    var rx: Double = 0
    var ry: Double = 0
    var lt: Double = 0
    var rt: Double = 0
    var hatX: Int8 = 0
    var hatY: Int8 = 0
    var buttons: UInt16 = 0

    static let a: UInt16 = 1 << 0
    static let b: UInt16 = 1 << 1
    static let x: UInt16 = 1 << 2
    static let y: UInt16 = 1 << 3
    static let lb: UInt16 = 1 << 4
    static let rb: UInt16 = 1 << 5
    static let back: UInt16 = 1 << 6
    static let start: UInt16 = 1 << 7
    static let guide: UInt16 = 1 << 8
    static let l3: UInt16 = 1 << 9
    static let r3: UInt16 = 1 << 10

    init() {}

    init(gamepad: GCExtendedGamepad) {
        let left = deadzone(Double(gamepad.leftThumbstick.xAxis.value), Double(-gamepad.leftThumbstick.yAxis.value))
        let right = deadzone(Double(gamepad.rightThumbstick.xAxis.value), Double(-gamepad.rightThumbstick.yAxis.value))
        lx = left.0
        ly = left.1
        rx = right.0
        ry = right.1
        lt = Double(gamepad.leftTrigger.value)
        rt = Double(gamepad.rightTrigger.value)
        if gamepad.dpad.left.isPressed { hatX = -1 }
        if gamepad.dpad.right.isPressed { hatX = 1 }
        if gamepad.dpad.up.isPressed { hatY = -1 }
        if gamepad.dpad.down.isPressed { hatY = 1 }
        func bit(_ button: GCControllerButtonInput, _ mask: UInt16) {
            if button.isPressed { buttons |= mask }
        }
        bit(gamepad.buttonA, Self.a)
        bit(gamepad.buttonB, Self.b)
        bit(gamepad.buttonX, Self.x)
        bit(gamepad.buttonY, Self.y)
        bit(gamepad.leftShoulder, Self.lb)
        bit(gamepad.rightShoulder, Self.rb)
        if let options = gamepad.buttonOptions { bit(options, Self.back) }
        bit(gamepad.buttonMenu, Self.start)
        if let home = gamepad.buttonHome { bit(home, Self.guide) }
        if let leftClick = gamepad.leftThumbstickButton { bit(leftClick, Self.l3) }
        if let rightClick = gamepad.rightThumbstickButton { bit(rightClick, Self.r3) }
    }

    func frame() -> Data {
        var data = Data(count: 14)
        data.withUnsafeMutableBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            write(axis(lx), to: bytes, at: 0)
            write(axis(ly), to: bytes, at: 2)
            write(axis(rx), to: bytes, at: 4)
            write(axis(ry), to: bytes, at: 6)
            bytes[8] = trigger(lt)
            bytes[9] = trigger(rt)
            var bits = buttons.littleEndian
            withUnsafeBytes(of: &bits) { src in
                bytes[10] = src[0]
                bytes[11] = src[1]
            }
            bytes[12] = UInt8(bitPattern: hatX)
            bytes[13] = UInt8(bitPattern: hatY)
        }
        return data
    }
}

func deadzone(_ x: Double, _ y: Double) -> (Double, Double) {
    let dead = AppSettings.stickDeadzone
    let mag = hypot(x, y)
    if mag < dead || mag == 0 { return (0, 0) }
    let scaled = min(1, (mag - dead) / (1 - dead))
    let curved = pow(scaled, AppSettings.stickCurve)
    return (x * curved / mag, y * curved / mag)
}

private func axis(_ value: Double) -> Int16 {
    let scaled = (value * 32767).rounded()
    return Int16(min(32767, max(-32767, scaled)))
}

private func trigger(_ value: Double) -> UInt8 {
    let scaled = (min(1, max(0, value)) * 255).rounded()
    return UInt8(scaled)
}

private func write(_ value: Int16, to bytes: UnsafeMutableBufferPointer<UInt8>, at offset: Int) {
    var little = value.littleEndian
    withUnsafeBytes(of: &little) { src in
        bytes[offset] = src[0]
        bytes[offset + 1] = src[1]
    }
}
