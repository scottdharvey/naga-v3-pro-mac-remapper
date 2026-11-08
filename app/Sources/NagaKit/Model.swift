import Foundation

// MARK: - Buttons

public struct NagaButton: Identifiable, Hashable {
    public let id: UInt8
    public let name: String
    public let group: String
    public let editable: Bool
}

public enum Naga {
    public static let profile: UInt8 = 0x01

    /// Physical buttons confirmed on the Naga V3 Pro (see CLAUDE.md).
    public static let buttons: [NagaButton] = [
        NagaButton(id: 0x01, name: "Left click", group: "Top", editable: false),
        NagaButton(id: 0x02, name: "Right click", group: "Top", editable: true),
        NagaButton(id: 0x39, name: "Top button 3", group: "Top", editable: true),
        NagaButton(id: 0x0B, name: "DPI button (front)", group: "Top", editable: true),
        NagaButton(id: 0x0C, name: "DPI button (rear)", group: "Top", editable: true),
        NagaButton(id: 0x6A, name: "Button behind wheel", group: "Top", editable: true),
        NagaButton(id: 0x03, name: "Wheel click", group: "Scroll wheel", editable: true),
        NagaButton(id: 0x09, name: "Wheel up", group: "Scroll wheel", editable: true),
        NagaButton(id: 0x0A, name: "Wheel down", group: "Scroll wheel", editable: true),
        NagaButton(id: 0x34, name: "Wheel tilt left", group: "Scroll wheel", editable: true),
        NagaButton(id: 0x35, name: "Wheel tilt right", group: "Scroll wheel", editable: true),
    ] + (0..<12).map { i in
        NagaButton(id: 0x40 + UInt8(i), name: "Side button \(i + 1)", group: "12-button side panel", editable: true)
    } + [
        NagaButton(id: 0x50, name: "Top row, front", group: "6-button side panel", editable: true),
        NagaButton(id: 0x51, name: "Top row, middle", group: "6-button side panel", editable: true),
        NagaButton(id: 0x52, name: "Top row, back", group: "6-button side panel", editable: true),
        NagaButton(id: 0x55, name: "Bottom row, front", group: "6-button side panel", editable: true),
        NagaButton(id: 0x54, name: "Bottom row, middle", group: "6-button side panel", editable: true),
        NagaButton(id: 0x53, name: "Bottom row, back", group: "6-button side panel", editable: true),
        NagaButton(id: 0x05, name: "Forward button", group: "2-button side panel", editable: true),
        NagaButton(id: 0x04, name: "Back button", group: "2-button side panel", editable: true),
        NagaButton(id: 0x0E, name: "Profile button (bottom)", group: "Other", editable: true),
    ]

    public static let groups = ["Top", "Scroll wheel", "12-button side panel", "6-button side panel", "2-button side panel", "Other"]

    /// Ids the mouse reports that aren't in the UI. They're kept in saved files and restored, never edited.
    public static let hiddenIDs: [UInt8] = []

    public static var allIDs: [UInt8] { buttons.map(\.id) + hiddenIDs }

    /// Factory mapping read from this mouse (profile byte excluded): id -> bytes 2...9.
    static let factoryTail: [UInt8: [UInt8]] = {
        var t: [UInt8: [UInt8]] = [
            0x01: [0x00, 0x01, 0x01, 0x01, 0, 0, 0, 0], 0x02: [0x00, 0x01, 0x01, 0x02, 0, 0, 0, 0],
            0x03: [0x00, 0x01, 0x01, 0x03, 0, 0, 0, 0], 0x04: [0x00, 0x01, 0x01, 0x04, 0, 0, 0, 0],
            0x05: [0x00, 0x01, 0x01, 0x05, 0, 0, 0, 0], 0x09: [0x00, 0x01, 0x01, 0x09, 0, 0, 0, 0],
            0x0A: [0x00, 0x01, 0x01, 0x0A, 0, 0, 0, 0], 0x0B: [0x00, 0x06, 0x01, 0x01, 0, 0, 0, 0],
            0x0C: [0x00, 0x06, 0x01, 0x02, 0, 0, 0, 0], 0x0E: [0x00, 0x07, 0x01, 0x04, 0, 0, 0, 0],
            0x34: [0x00, 0x0E, 0x01, 0x68, 0x00, 0x14, 0, 0], 0x35: [0x00, 0x0E, 0x01, 0x69, 0x00, 0x14, 0, 0],
            0x39: [0x00, 0x0C, 0x01, 0x39, 0, 0, 0, 0], 0x6A: [0x00, 0x12, 0x01, 0x01, 0, 0, 0, 0],
        ]
        let sideKeys: [UInt8] = [0x1E, 0x1F, 0x20, 0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x2D, 0x2E]
        for (i, k) in sideKeys.enumerated() { t[0x40 + UInt8(i)] = [0x00, 0x02, 0x01, 0x00, k, 0, 0, 0] }
        for i in 0..<6 { t[0x50 + UInt8(i)] = [0x00, 0x02, 0x01, 0x00, sideKeys[i], 0, 0, 0] }
        return t
    }()

    public static func factoryBytes(profile: UInt8 = Naga.profile) -> [UInt8: [UInt8]] {
        var out: [UInt8: [UInt8]] = [:]
        for (id, tail) in factoryTail { out[id] = [profile, id] + tail }
        return out
    }
}

// MARK: - Actions

public enum ButtonAction: Equatable, Hashable {
    case mouse(UInt8)
    case key(modifiers: UInt8, key: UInt8)
    case dpiUp, dpiDown
    case profileCycle
    case scrollModeToggle
    case tiltLeft, tiltRight
    case firmwareDefault          // type 0C with the button's own id (what top button 3 has at factory)
    case disabled                 // type 00: button does nothing
    case raw([UInt8])             // 7 bytes: type, 01, params

    /// Decodes the 10 bytes returned by 0x8C.
    public init(bytes m: [UInt8]) {
        guard m.count == 10 else { self = .raw([]); return }
        let tail = Array(m[3..<10])
        switch (m[3], m[5]) {
        case (0x00, _): self = .disabled
        case (0x01, let n): self = .mouse(n)
        case (0x02, _): self = .key(modifiers: m[5], key: m[6])
        case (0x06, 0x01): self = .dpiUp
        case (0x06, 0x02): self = .dpiDown
        case (0x07, 0x04): self = .profileCycle
        case (0x12, 0x01): self = .scrollModeToggle
        case (0x0E, 0x68) where m[6] == 0x00 && m[7] == 0x14: self = .tiltLeft
        case (0x0E, 0x69) where m[6] == 0x00 && m[7] == 0x14: self = .tiltRight
        case (0x0C, let b) where b == m[1]: self = .firmwareDefault
        default: self = .raw(tail)
        }
    }

    /// The 10 bytes to write with 0x0C.
    public func bytes(profile: UInt8, button: UInt8) -> [UInt8] {
        var t: [UInt8]
        switch self {
        case .mouse(let n): t = [0x01, 0x01, n]
        case .key(let mod, let key): t = [0x02, 0x01, mod, key]
        case .dpiUp: t = [0x06, 0x01, 0x01]
        case .dpiDown: t = [0x06, 0x01, 0x02]
        case .profileCycle: t = [0x07, 0x01, 0x04]
        case .scrollModeToggle: t = [0x12, 0x01, 0x01]
        case .tiltLeft: t = [0x0E, 0x01, 0x68, 0x00, 0x14]
        case .tiltRight: t = [0x0E, 0x01, 0x69, 0x00, 0x14]
        case .firmwareDefault: t = [0x0C, 0x01, button]
        case .disabled: t = [0x00, 0x01]
        case .raw(let r): t = r
        }
        t = Array(t.prefix(7))
        t += [UInt8](repeating: 0, count: 7 - t.count)
        return [profile, button, 0x00] + t
    }

    public var summary: String {
        switch self {
        case .mouse(let n): return MouseFunction.name(n)
        case .key(let mod, let key): return Modifiers.symbols(mod) + HIDKey.name(key)
        case .dpiUp: return "DPI up"
        case .dpiDown: return "DPI down"
        case .profileCycle: return "Profile cycle"
        case .scrollModeToggle: return "Scroll mode toggle"
        case .tiltLeft: return "Scroll left"
        case .tiltRight: return "Scroll right"
        case .firmwareDefault: return "Firmware default"
        case .disabled: return "Unbound"
        case .raw(let r): return "Unknown action: " + r.map { String(format: "%02X", $0) }.joined(separator: " ")
        }
    }
}

public struct MouseFunction: Identifiable, Hashable {
    public let code: UInt8
    public let name: String
    public var id: UInt8 { code }
    public static let all: [MouseFunction] = [
        MouseFunction(code: 0x01, name: "Left click"), MouseFunction(code: 0x02, name: "Right click"),
        MouseFunction(code: 0x03, name: "Middle click"), MouseFunction(code: 0x04, name: "Back"),
        MouseFunction(code: 0x05, name: "Forward"), MouseFunction(code: 0x09, name: "Scroll up"),
        MouseFunction(code: 0x0A, name: "Scroll down"),
    ]
    public static func name(_ n: UInt8) -> String {
        all.first(where: { $0.code == n })?.name ?? String(format: "Mouse 0x%02X", n)
    }
}

/// Modifier byte: standard USB HID bitmask (left-hand modifiers). Confirmed with ⌘ (0x08) on a Naga V3 Pro.
public enum Modifiers {
    public static let control: UInt8 = 0x01
    public static let shift: UInt8 = 0x02
    public static let option: UInt8 = 0x04
    public static let command: UInt8 = 0x08
    public static func symbols(_ m: UInt8) -> String {
        var s = ""
        if m & control != 0 { s += "⌃" }
        if m & option != 0 { s += "⌥" }
        if m & shift != 0 { s += "⇧" }
        if m & command != 0 { s += "⌘" }
        return s
    }
}

public struct HIDKey: Identifiable, Hashable {
    public let code: UInt8
    public let name: String
    public var id: UInt8 { code }

    public static let all: [HIDKey] = {
        var k: [HIDKey] = []
        for (i, c) in "ABCDEFGHIJKLMNOPQRSTUVWXYZ".enumerated() { k.append(HIDKey(code: 0x04 + UInt8(i), name: String(c))) }
        for i in 1...9 { k.append(HIDKey(code: 0x1D + UInt8(i), name: "\(i)")) }
        k.append(HIDKey(code: 0x27, name: "0"))
        let named: [(UInt8, String)] = [
            (0x28, "Return"), (0x29, "Escape"), (0x2A, "Delete (Backspace)"), (0x2B, "Tab"), (0x2C, "Space"),
            (0x2D, "-"), (0x2E, "="), (0x2F, "["), (0x30, "]"), (0x31, "\\"), (0x33, ";"), (0x34, "'"),
            (0x35, "`"), (0x36, ","), (0x37, "."), (0x38, "/"), (0x39, "Caps Lock"),
            (0x46, "Print Screen"), (0x47, "Scroll Lock"), (0x48, "Pause"), (0x49, "Insert"), (0x4A, "Home"),
            (0x4B, "Page Up"), (0x4C, "Forward Delete"), (0x4D, "End"), (0x4E, "Page Down"),
            (0x4F, "Right Arrow"), (0x50, "Left Arrow"), (0x51, "Down Arrow"), (0x52, "Up Arrow"),
        ]
        k += named.map { HIDKey(code: $0.0, name: $0.1) }
        for i in 0..<12 { k.append(HIDKey(code: 0x3A + UInt8(i), name: "F\(i + 1)")) }
        for i in 0..<12 { k.append(HIDKey(code: 0x68 + UInt8(i), name: "F\(i + 13)")) }
        return k
    }()

    public static func name(_ code: UInt8) -> String {
        all.first(where: { $0.code == code })?.name ?? String(format: "Key 0x%02X", code)
    }
}

// MARK: - Config files (same format as `razerprobe backup`)

public struct ConfigEntry: Codable {
    public let button: String
    public let hypershift: Int
    public let bytes: String
    public let description: String
    public init(button: String, hypershift: Int, bytes: String, description: String) {
        self.button = button; self.hypershift = hypershift; self.bytes = bytes; self.description = description
    }
}

public struct ConfigFile: Codable {
    public let format: String
    public let created: String
    public let productID: String
    public let firmware: String
    public let profile: String
    public let entries: [ConfigEntry]

    public init(productID: Int, firmware: String, profile: UInt8, mappings: [UInt8: [UInt8]]) {
        format = "naga-config/1"
        created = ISO8601DateFormatter().string(from: Date())
        self.productID = String(format: "%04X", productID)
        self.firmware = firmware
        self.profile = String(format: "%02X", profile)
        entries = mappings.keys.sorted().map { id in
            let b = mappings[id]!
            let name = Naga.buttons.first(where: { $0.id == id })?.name ?? String(format: "id %02X", id)
            return ConfigEntry(button: String(format: "%02X", id), hypershift: 0,
                               bytes: b.map { String(format: "%02X", $0) }.joined(separator: " "),
                               description: "\(name): \(ButtonAction(bytes: b).summary)")
        }
    }

    /// id -> 10 bytes, normal layer only, with the profile byte replaced.
    public func mappings(profile: UInt8) -> [UInt8: [UInt8]] {
        var out: [UInt8: [UInt8]] = [:]
        for e in entries where e.hypershift == 0 {
            let parts = e.bytes.split(separator: " ").compactMap { UInt8($0, radix: 16) }
            guard parts.count == 10 else { continue }
            var b = parts
            b[0] = profile
            if out[b[1]] == nil { out[b[1]] = b }
        }
        return out
    }
}
