import Foundation
import IOKit
import IOKit.hid

public enum RazerError: Error, LocalizedError {
    case notFound
    case openFailed(IOReturn)
    case noTransaction
    case ioFailed(String)
    case status(UInt8)
    case verifyFailed(UInt8)

    public var errorDescription: String? {
        switch self {
        case .notFound:
            return "Razer Naga V3 Pro not found. Connect it by USB cable or the HyperSpeed dongle (Bluetooth isn't supported)."
        case .openFailed(let r):
            return String(format: "Couldn't open the mouse (0x%08X). Allow this app in System Settings > Privacy & Security > Input Monitoring, then reopen it.", UInt32(bitPattern: r))
        case .noTransaction:
            return "The mouse didn't answer any known transaction ID."
        case .ioFailed(let s):
            return s
        case .status(let s):
            return String(format: "The mouse returned status 0x%02X.", s)
        case .verifyFailed(let b):
            return String(format: "Button 0x%02X didn't verify after writing.", b)
        }
    }
}

/// Talks to the Razer control interface (90-byte feature reports, report ID 0).
/// Not thread-safe: use from one serial queue.
public final class RazerDevice {
    public static let vendorID = 0x1532
    private let manager: IOHIDManager
    private let device: IOHIDDevice
    public let productID: Int
    public let productName: String
    private var tid: UInt8 = 0x1F

    private static func intProp(_ d: IOHIDDevice, _ key: String) -> Int {
        (IOHIDDeviceGetProperty(d, key as CFString) as? NSNumber)?.intValue ?? -1
    }

    public init() throws {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: RazerDevice.vendorID] as CFDictionary)
        _ = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        let devices = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
        // Only ever talk to a Naga V3 Pro: the button layout and commands are specific to it,
        // and writing them to another Razer device could misconfigure it.
        guard let d = devices.first(where: {
            RazerDevice.intProp($0, kIOHIDMaxFeatureReportSizeKey) >= 90 &&
            ((IOHIDDeviceGetProperty($0, kIOHIDProductKey as CFString) as? String) ?? "").localizedCaseInsensitiveContains("Naga V3 Pro")
        }) else {
            throw RazerError.notFound
        }
        device = d
        productID = RazerDevice.intProp(d, kIOHIDProductIDKey)
        productName = (IOHIDDeviceGetProperty(d, kIOHIDProductKey as CFString) as? String) ?? "Razer device"
        let r = IOHIDDeviceOpen(d, IOOptionBits(kIOHIDOptionsTypeNone))
        guard r == kIOReturnSuccess else { throw RazerError.openFailed(r) }
        var found = false
        for t: UInt8 in [0x1F, 0xFF, 0x3F] {
            tid = t
            if let resp = try? transact(cls: 0x00, cmd: 0x81, size: 0x02), resp[0] == 0x02 { found = true; break }
        }
        guard found else { throw RazerError.noTransaction }
    }

    deinit {
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    /// Sends one command and returns the 90-byte reply (byte 0 = status).
    public func transact(cls: UInt8, cmd: UInt8, size: UInt8, args: [UInt8] = []) throws -> [UInt8] {
        var req = [UInt8](repeating: 0, count: 90)
        req[1] = tid; req[5] = size; req[6] = cls; req[7] = cmd
        for (i, a) in args.prefix(80).enumerated() { req[8 + i] = a }
        var crc: UInt8 = 0
        for i in 2..<88 { crc ^= req[i] }
        req[88] = crc
        let sr = IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, 0, req, req.count)
        guard sr == kIOReturnSuccess else {
            throw RazerError.ioFailed(String(format: "Sending to the mouse failed (0x%08X).", UInt32(bitPattern: sr)))
        }
        for _ in 0..<10 {
            usleep(40_000)
            var resp = [UInt8](repeating: 0, count: 90)
            var len: CFIndex = 90
            let gr = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 0, &resp, &len)
            guard gr == kIOReturnSuccess else {
                throw RazerError.ioFailed(String(format: "Reading from the mouse failed (0x%08X).", UInt32(bitPattern: gr)))
            }
            if resp[0] == 0x01 { continue }   // busy
            return resp
        }
        throw RazerError.ioFailed("The mouse stayed busy.")
    }

    public func firmware() -> String {
        guard let r = try? transact(cls: 0x00, cmd: 0x81, size: 0x02), r[0] == 0x02 else { return "?" }
        return String(format: "%d.%02d", r[8], r[9])
    }

    /// Reads one button mapping (class 0x02 cmd 0x8C). Returns the 10 data bytes, or nil if the id doesn't exist.
    public func readMapping(profile: UInt8, button: UInt8) throws -> [UInt8]? {
        let r = try transact(cls: 0x02, cmd: 0x8C, size: 0x0A, args: [profile, button, 0x00])
        guard r[0] == 0x02 else { return nil }
        return Array(r[8..<18])
    }

    /// Writes one 10-byte mapping (class 0x02 cmd 0x0C) and verifies it by reading it back.
    public func writeMapping(_ bytes: [UInt8]) throws {
        precondition(bytes.count == 10)
        guard bytes[1] != 0x01 else { return }   // never touch left click
        let r = try transact(cls: 0x02, cmd: 0x0C, size: 0x0A, args: bytes)
        guard r[0] == 0x02 else { throw RazerError.status(r[0]) }
        usleep(35_000)
        guard try readMapping(profile: bytes[0], button: bytes[1]) == bytes else { throw RazerError.verifyFailed(bytes[1]) }
    }
}
