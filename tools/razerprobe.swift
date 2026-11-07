// razerprobe.swift: READ-ONLY probe for the Razer HID control interface on macOS.
// Step 1 of the Naga V3 Pro onboard-remapping project: find the control interface
// and confirm we can talk Razer's 90-byte feature-report protocol from macOS.
//
// Build:  swiftc -O tools/razerprobe.swift -o razerprobe -framework IOKit
// Usage:  ./razerprobe list
//         ./razerprobe info [--pid 00A8]
//         ./razerprobe sweep <class> [size]
//         ./razerprobe get <class> <cmd> <size> [arg bytes...] [--pid XXXX] [--tid 1F]
// All numbers are hex. Everything is read-only except `setkey`, which writes one side button and needs --yes.

import Foundation
import IOKit
import IOKit.hid

let razerVID = 0x1532
var listenLabels: [String] = []   // used by the `listen` input-report callback
let tidCandidates: [UInt8] = [0x1F, 0xFF, 0x3F]   // transaction IDs used by different Razer generations
let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

struct Iface {
    let device: IOHIDDevice
    let pid: Int
    let product: String
    let usagePage: Int
    let usage: Int
    let maxFeature: Int
    let location: Int
}

func intProp(_ d: IOHIDDevice, _ key: String) -> Int {
    (IOHIDDeviceGetProperty(d, key as CFString) as? NSNumber)?.intValue ?? -1
}
func strProp(_ d: IOHIDDevice, _ key: String) -> String {
    (IOHIDDeviceGetProperty(d, key as CFString) as? String) ?? "?"
}
func hex4(_ v: Int) -> String { String(format: "0x%04X", v) }
func hexBytes<S: Sequence>(_ b: S) -> String where S.Element == UInt8 {
    b.map { String(format: "%02X", $0) }.joined(separator: " ")
}
func ioErr(_ r: IOReturn) -> String {
    let code = UInt32(bitPattern: r)
    switch code {
    case 0xE00002E2: return "0xE00002E2 (not permitted: give Terminal Input Monitoring access)"
    case 0xE00002C1: return "0xE00002C1 (not privileged)"
    case 0xE00002C5: return "0xE00002C5 (exclusive access held by another process)"
    default: return String(format: "0x%08X", code)
    }
}

func enumerate() -> [Iface] {
    IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: razerVID] as CFDictionary)
    let r = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    if r != kIOReturnSuccess { print("warning: IOHIDManagerOpen returned \(ioErr(r))") }
    guard let set = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return [] }
    return set.map { d in
        Iface(device: d,
              pid: intProp(d, kIOHIDProductIDKey),
              product: strProp(d, kIOHIDProductKey),
              usagePage: intProp(d, kIOHIDPrimaryUsagePageKey),
              usage: intProp(d, kIOHIDPrimaryUsageKey),
              maxFeature: intProp(d, kIOHIDMaxFeatureReportSizeKey),
              location: intProp(d, kIOHIDLocationIDKey))
    }.sorted { ($0.pid, $0.location, $0.usagePage, $0.usage) < ($1.pid, $1.location, $1.usagePage, $1.usage) }
}

// Razer report layout (90 bytes):
// [0] status  [1] transaction id  [2..3] remaining packets  [4] protocol type
// [5] data size  [6] command class  [7] command id  [8..87] args  [88] crc  [89] reserved
func buildReport(tid: UInt8, cls: UInt8, cmd: UInt8, size: UInt8, args: [UInt8]) -> [UInt8] {
    var r = [UInt8](repeating: 0, count: 90)
    r[1] = tid; r[5] = size; r[6] = cls; r[7] = cmd
    for (i, a) in args.prefix(80).enumerated() { r[8 + i] = a }
    var crc: UInt8 = 0
    for i in 2..<88 { crc ^= r[i] }
    r[88] = crc
    return r
}

let statusNames: [UInt8: String] = [0x00: "new", 0x01: "busy", 0x02: "ok", 0x03: "failed",
                                     0x04: "timeout", 0x05: "not supported"]

func transact(_ d: IOHIDDevice, tid: UInt8, cls: UInt8, cmd: UInt8, size: UInt8, args: [UInt8] = []) -> [UInt8]? {
    let req = buildReport(tid: tid, cls: cls, cmd: cmd, size: size, args: args)
    let sr = IOHIDDeviceSetReport(d, kIOHIDReportTypeFeature, 0, req, req.count)
    guard sr == kIOReturnSuccess else { print("    SetReport failed: \(ioErr(sr))"); return nil }
    for _ in 0..<10 {
        usleep(50_000)
        var resp = [UInt8](repeating: 0, count: 90)
        var len: CFIndex = 90
        let gr = IOHIDDeviceGetReport(d, kIOHIDReportTypeFeature, 0, &resp, &len)
        guard gr == kIOReturnSuccess else { print("    GetReport failed: \(ioErr(gr))"); return nil }
        if resp[0] == 0x01 { continue }   // device busy, poll again
        return resp
    }
    print("    device stayed busy")
    return nil
}

func describe(_ resp: [UInt8]) -> String {
    let st = statusNames[resp[0]] ?? String(format: "0x%02X", resp[0])
    let n = min(Int(resp[5]), 80)
    return "status=\(st) size=\(resp[5]) data=[\(hexBytes(resp[8..<(8 + n)]))]"
}

func openDev(_ i: Iface) -> Bool {
    let r = IOHIDDeviceOpen(i.device, IOOptionBits(kIOHIDOptionsTypeNone))
    if r != kIOReturnSuccess { print("  open failed: \(ioErr(r))"); return false }
    return true
}

func findTid(_ i: Iface) -> UInt8? {
    for t in tidCandidates {
        if let r = transact(i.device, tid: t, cls: 0x00, cmd: 0x81, size: 0x02), r[0] == 0x02 { return t }
    }
    return nil
}

// ---- Button mapping (class 0x02, read 0x8C / write 0x0C) ----
// Reply layout observed: [0] profile [1] button [2] hypershift [3] action type [4] 01 (unknown) [5..] params
//   type 01 mouse button: params [01?, mouse button]; type 02 key: params [modifier, HID usage]
let knownButtons: [UInt8] = [0x01, 0x02, 0x03, 0x04, 0x05, 0x09, 0x0A, 0x0B, 0x0C, 0x0E, 0x34, 0x35, 0x39] + Array(UInt8(0x40)...UInt8(0x4B)) + Array(UInt8(0x50)...UInt8(0x55)) + [0x6A]

func readMap(_ d: IOHIDDevice, tid: UInt8, p: UInt8, b: UInt8) -> [UInt8]? {
    guard let r = transact(d, tid: tid, cls: 0x02, cmd: 0x8C, size: 0x0A, args: [p, b, 0x00]), r[0] == 0x02 else { return nil }
    return Array(r[8..<18])
}

func buttonName(_ b: UInt8) -> String {
    let names: [UInt8: String] = [0x01: "left", 0x02: "right", 0x03: "middle", 0x04: "2btn back", 0x05: "2btn forward",
                                  0x09: "wheel up", 0x0A: "wheel down", 0x0B: "DPI front", 0x0C: "DPI rear",
                                  0x0E: "profile (bottom)", 0x34: "tilt left", 0x35: "tilt right",
                                  0x39: "top button 3", 0x6A: "behind wheel 1",
                                  0x50: "6btn top front", 0x51: "6btn top mid", 0x52: "6btn top back",
                                  0x53: "6btn bot back", 0x54: "6btn bot mid", 0x55: "6btn bot front"]
    if (0x40...0x4B).contains(b) { return "side \(Int(b) - 0x3F)" }
    return names[b] ?? "?"
}

func keyName(_ k: UInt8) -> String {
    switch k {
    case 0x04...0x1D: return String(Character(UnicodeScalar(UInt8(ascii: "a") + (k - 0x04))))
    case 0x1E...0x26: return String(Int(k) - 0x1D)
    case 0x27: return "0"
    case 0x2D: return "-"
    case 0x2E: return "="
    case 0x3A...0x45: return "F\(Int(k) - 0x39)"
    case 0x68...0x73: return "F\(Int(k) - 0x5B)"
    default: return String(format: "HID 0x%02X", k)
    }
}

func decode(_ m: [UInt8]) -> String {
    switch m[3] {
    case 0x01:
        let n: [UInt8: String] = [1: "left click", 2: "right click", 3: "middle click", 4: "back", 5: "forward",
                                  9: "scroll up", 0x0A: "scroll down"]
        return "mouse " + (n[m[5]] ?? String(format: "button 0x%02X", m[5]))
    case 0x02:
        return "key " + keyName(m[6]) + (m[5] != 0 ? String(format: " +mod 0x%02X", m[5]) : "")
    default:
        return String(format: "type 0x%02X (not decoded)", m[3])
    }
}

// ---- CLI ----
var argv = Array(CommandLine.arguments.dropFirst())
func takeOpt(_ name: String) -> String? {
    guard let i = argv.firstIndex(of: name), i + 1 < argv.count else { return nil }
    let v = argv[i + 1]; argv.removeSubrange(i...(i + 1)); return v
}
func stripHex(_ s: String) -> String { s.lowercased().hasPrefix("0x") ? String(s.dropFirst(2)) : s }
func parseByte(_ s: String) -> UInt8? { UInt8(stripHex(s), radix: 16) }

let pidFilter = takeOpt("--pid").flatMap { Int(stripHex($0), radix: 16) }
let tidOpt = takeOpt("--tid").flatMap(parseByte)
let command = argv.first ?? "help"

let all = enumerate().filter { pidFilter == nil || $0.pid == pidFilter! }
var candidates = all.filter { $0.maxFeature >= 90 }
if candidates.isEmpty { candidates = all }

// ---- Backup / restore / generic writes ----
struct BackupEntry: Codable {
    let button: String       // hex id, e.g. "40"
    let hypershift: Int      // 0 = normal layer, 1 = Hypershift layer
    let bytes: String        // the 10 bytes 0x8C returned, hex, space separated
    let description: String  // human-readable, informational only
}
struct BackupFile: Codable {
    let format: String
    let created: String
    let productID: String
    let firmware: String
    let profile: String
    let entries: [BackupEntry]
}

func parseHexList(_ s: String) -> [UInt8]? {
    let parts = s.split(separator: " ").map { UInt8($0, radix: 16) }
    return parts.contains(where: { $0 == nil }) ? nil : parts.map { $0! }
}

func readMapHS(_ d: IOHIDDevice, tid: UInt8, p: UInt8, b: UInt8, hs: UInt8) -> [UInt8]? {
    guard let r = transact(d, tid: tid, cls: 0x02, cmd: 0x8C, size: 0x0A, args: [p, b, hs]), r[0] == 0x02 else { return nil }
    return Array(r[8..<18])
}

// Writes one 10-byte mapping with 0x0C and reads it back. Returns true only if the read-back matches.
func writeMap(_ d: IOHIDDevice, tid: UInt8, _ w: [UInt8]) -> (ok: Bool, after: [UInt8]?) {
    guard let r = transact(d, tid: tid, cls: 0x02, cmd: 0x0C, size: 0x0A, args: w) else { return (false, nil) }
    if r[0] != 0x02 { print("  write status: \(statusNames[r[0]] ?? String(format: "0x%02X", r[0]))"); return (false, nil) }
    usleep(50_000)
    let after = readMapHS(d, tid: tid, p: w[0], b: w[1], hs: w[2])
    return (after == w, after)
}

func appendBackupLog(_ text: String) {
    let line = ISO8601DateFormatter().string(from: Date()) + " " + text + "\n"
    let url = URL(fileURLWithPath: "mapping-backup.txt")
    if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); h.closeFile() }
    else { try? line.write(to: url, atomically: true, encoding: .utf8) }
}

func decodeFull(_ m: [UInt8]) -> String {
    guard m.count >= 10 else { return "?" }
    switch m[3] {
    case 0x00: return "disabled"
    case 0x01, 0x02: return decode(m)
    case 0x06: return m[5] == 0x01 ? "DPI stage up?" : (m[5] == 0x02 ? "DPI stage down?" : "DPI action \(hexBytes(m[5..<7]))")
    case 0x07: return "profile action? [\(hexBytes(m[5..<7]))]"
    case 0x0E: return "repeating mouse \(String(format: "0x%02X", m[5])) (tilt?) [\(hexBytes(m[5..<8]))]"
    default: return decode(m)
    }
}

func openControl() -> (Iface, UInt8)? {
    guard let i = candidates.first(where: { $0.maxFeature >= 90 && $0.product.localizedCaseInsensitiveContains("Naga V3 Pro") }) else {
        print("Naga V3 Pro control interface not found. Is the mouse on cable or dongle? (Other Razer devices are not supported.)"); return nil
    }
    guard openDev(i) else { return nil }
    guard let tid = tidOpt ?? findTid(i) else { print("No working transaction ID."); return nil }
    return (i, tid)
}


switch command {
case "list":
    if all.isEmpty { print("No Razer HID devices found (is the mouse on USB cable or the HyperSpeed dongle, not Bluetooth?)") }
    for i in all {
        let mark = i.maxFeature >= 90 ? "  <- likely control interface" : ""
        print("\(i.product)  pid=\(hex4(i.pid))  usage=\(hex4(i.usagePage))/\(hex4(i.usage))  maxFeature=\(i.maxFeature)  loc=\(String(format: "0x%08X", i.location))\(mark)")
    }

case "info":
    let queries: [(String, UInt8, UInt8, UInt8)] = [
        ("firmware", 0x00, 0x81, 0x02), ("serial", 0x00, 0x82, 0x16), ("device mode", 0x00, 0x84, 0x02),
        ("poll rate", 0x00, 0x85, 0x01), ("DPI", 0x04, 0x85, 0x07), ("battery", 0x07, 0x80, 0x02)]
    for i in candidates {
        print("\n== \(i.product) pid=\(hex4(i.pid)) usage=\(hex4(i.usagePage))/\(hex4(i.usage)) maxFeature=\(i.maxFeature)")
        guard openDev(i) else { continue }
        guard let tid = tidOpt ?? findTid(i) else { print("  no transaction ID got an OK response on this interface"); continue }
        print(String(format: "  transaction id 0x%02X works", tid))
        for (name, c, m, s) in queries {
            guard let r = transact(i.device, tid: tid, cls: c, cmd: m, size: s) else { continue }
            var line = "  \(name): \(describe(r))"
            if name == "serial", r[0] == 0x02 {
                let txt = String(bytes: r[8..<(8 + 0x16)].filter { $0 >= 0x20 && $0 < 0x7F }, encoding: .ascii) ?? ""
                line += "  \"\(txt)\""
            }
            print(line)
        }
    }

case "get":
    let nums = argv.dropFirst().compactMap(parseByte)
    guard nums.count >= 3, nums.count == argv.count - 1 else { print("usage: get <class> <cmd> <size> [args...]  (hex)"); exit(1) }
    let (c, m, s) = (nums[0], nums[1], nums[2])
    guard m >= 0x80 else { print("Refusing: cmd < 0x80 is a SET command. This tool is read-only."); exit(1) }
    for i in candidates {
        print("\n== \(i.product) pid=\(hex4(i.pid)) usage=\(hex4(i.usagePage))/\(hex4(i.usage))")
        guard openDev(i) else { continue }
        guard let tid = tidOpt ?? findTid(i) else { print("  no working transaction ID"); continue }
        if let r = transact(i.device, tid: tid, cls: c, cmd: m, size: s, args: Array(nums.dropFirst(3))) {
            print("  \(describe(r))")
            print("  raw: \(hexBytes(r))")
        }
    }

case "sweep":
    // Try every GET command id (0x80-0xFF) in one class and report which ones the mouse recognizes.
    // "not supported" = the command doesn't exist; "ok" or "failed" = it exists (failed often means wrong args/size).
    let nums = argv.dropFirst().compactMap(parseByte)
    guard let c = nums.first else { print("usage: sweep <class> [size]  (hex)"); exit(1) }
    let s: UInt8 = nums.count > 1 ? nums[1] : 0x00
    for i in candidates {
        print("\n== \(i.product) pid=\(hex4(i.pid)) class=\(String(format: "0x%02X", c)) size=\(String(format: "0x%02X", s))")
        guard openDev(i) else { continue }
        guard let tid = tidOpt ?? findTid(i) else { print("  no working transaction ID"); continue }
        for m in UInt8(0x80)...UInt8(0xFF) {
            guard let r = transact(i.device, tid: tid, cls: c, cmd: m, size: s) else { continue }
            if r[0] == 0x05 { continue }
            print(String(format: "  cmd 0x%02X: ", m) + describe(r))
        }
    }

case "mapscan":
    // Hypothesis test: 0x8C / 0x8E exist but "fail" with empty args, so they likely take
    // (profile, button, hypershift) arguments. Try those combos and print any that succeed.
    // Read-only: these are still GET commands.
    let nums = argv.dropFirst().compactMap(parseByte)
    let m: UInt8 = nums.first ?? 0x8C
    guard m >= 0x80 else { print("Refusing: read-only."); exit(1) }
    let s: UInt8 = nums.count > 1 ? nums[1] : 0x0A
    let swap = argv.contains("swap")          // try [button, profile] instead of [profile, button]
    let profiles: [UInt8] = nums.count > 2 ? [nums[2]] : [0x00, 0x01]
    for i in candidates {
        print("\n== mapscan cmd=\(String(format: "0x%02X", m)) size=\(String(format: "0x%02X", s)) layout=\(swap ? "button,profile" : "profile,button")")
        guard openDev(i) else { continue }
        guard let tid = tidOpt ?? findTid(i) else { print("  no working transaction ID"); continue }
        var hits = 0, failed = 0
        for p in profiles {
            for b in UInt8(0x01)...UInt8(0x7F) {
                let a: [UInt8] = swap ? [b, p, 0x00] : [p, b, 0x00]
                guard let r = transact(i.device, tid: tid, cls: 0x02, cmd: m, size: s, args: a) else { continue }
                if r[0] == 0x02 {
                    hits += 1
                    print(String(format: "  profile 0x%02X button 0x%02X: ", p, b) + describe(r))
                } else { failed += 1 }
            }
        }
        print("  \(hits) ok, \(failed) not ok")
    }

case "buttons":
    // Read and decode the current mapping for every button id that 0x8C answered for.
    let nums = argv.dropFirst().compactMap(parseByte)
    let p: UInt8 = nums.first ?? 0x01
    guard let i = candidates.first, openDev(i), let tid = tidOpt ?? findTid(i) else { exit(1) }
    print(String(format: "Profile 0x%02X (hypershift off)", p))
    for b in knownButtons {
        guard let m = readMap(i.device, tid: tid, p: p, b: b) else { continue }
        let label = buttonName(b).padding(toLength: 14, withPad: " ", startingAt: 0)
        print(String(format: "  0x%02X ", b) + label + decode(m) + "   [" + hexBytes(m[3..<10]) + "]")
    }

case "setkey":
    // WRITES to the mouse. Changes one side button (0x40-0x4B) to a different keyboard key.
    // Copies the current mapping bytes exactly and only changes the modifier and key bytes,
    // saves the old value to mapping-backup.txt, then reads it back to verify.
    guard argv.contains("--yes") else {
        print("setkey WRITES to the mouse. Re-run with --yes to confirm.")
        print("usage: setkey <profile> <button 40-4B> <hid key> [modifier] --yes")
        exit(1)
    }
    argv.removeAll { $0 == "--yes" }
    let nums = argv.dropFirst().compactMap(parseByte)
    guard nums.count >= 3, nums.count == argv.count - 1 else { print("usage: setkey <profile> <button 40-4B> <hid key> [modifier] --yes"); exit(1) }
    let (p, b, key) = (nums[0], nums[1], nums[2])
    let mod: UInt8 = nums.count > 3 ? nums[3] : 0x00
    guard (0x40...0x4B).contains(b) else { print("For now only side buttons 0x40-0x4B can be changed."); exit(1) }
    guard let i = candidates.first, openDev(i), let tid = tidOpt ?? findTid(i) else { exit(1) }
    guard let before = readMap(i.device, tid: tid, p: p, b: b) else { print("Couldn't read the current mapping. Nothing was written."); exit(1) }
    guard before[0] == p, before[1] == b, before[3] == 0x02 else {
        print("Current mapping [\(hexBytes(before))] isn't a plain key mapping. Nothing was written."); exit(1)
    }
    print("before: \(decode(before))   [\(hexBytes(before))]")
    let stamp = ISO8601DateFormatter().string(from: Date())
    let line = "\(stamp) profile=\(String(format: "%02X", p)) button=\(String(format: "%02X", b)) before=[\(hexBytes(before))]\n"
    let url = URL(fileURLWithPath: "mapping-backup.txt")
    if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); h.closeFile() }
    else { try? line.write(to: url, atomically: true, encoding: .utf8) }
    var w = before
    w[5] = mod; w[6] = key
    guard let r = transact(i.device, tid: tid, cls: 0x02, cmd: 0x0C, size: 0x0A, args: w) else { print("Write request failed to send."); exit(1) }
    print("write: \(statusNames[r[0]] ?? String(format: "0x%02X", r[0]))")
    usleep(100_000)
    guard let after = readMap(i.device, tid: tid, p: p, b: b) else { print("Couldn't read back."); exit(1) }
    print("after:  \(decode(after))   [\(hexBytes(after))]")
    print(after == w ? "Verified: the mouse now reports the new mapping." : "Read-back does NOT match what was written.")
    print(String(format: "To undo: ./razerprobe setkey %02X %02X %02X %02X --yes", p, b, before[6], before[5]))

case "backup":
    // Read-only. Saves every button mapping (normal + Hypershift layer) for one profile to a JSON file.
    let rest = Array(argv.dropFirst())
    guard let path = rest.first else { print("usage: backup <file.json> [profile]"); exit(1) }
    let p: UInt8 = rest.count > 1 ? (parseByte(rest[1]) ?? 0x01) : 0x01
    guard let ctl = openControl() else { exit(1) }
    let (i, tid) = ctl
    var fw = "?"
    if let r = transact(i.device, tid: tid, cls: 0x00, cmd: 0x81, size: 0x02), r[0] == 0x02 { fw = String(format: "%02X.%02X", r[8], r[9]) }
    var entries: [BackupEntry] = []
    for hs in [UInt8(0), UInt8(1)] {
        print("Reading profile \(String(format: "%02X", p)) \(hs == 0 ? "normal" : "Hypershift") layer...")
        for b in UInt8(0x01)...UInt8(0x7F) {
            guard let m = readMapHS(i.device, tid: tid, p: p, b: b, hs: hs) else { continue }
            guard m[2] == hs else { continue }   // mouse answered for a different layer; don't store a duplicate
            entries.append(BackupEntry(button: String(format: "%02X", b), hypershift: Int(hs), bytes: hexBytes(m), description: "\(buttonName(b)): \(decodeFull(m))"))
        }
    }
    let file = BackupFile(format: "naga-config/1", created: ISO8601DateFormatter().string(from: Date()),
                          productID: String(format: "%04X", i.pid), firmware: fw, profile: String(format: "%02X", p), entries: entries)
    let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
    do { try enc.encode(file).write(to: URL(fileURLWithPath: path)) } catch { print("Couldn't write \(path): \(error)"); exit(1) }
    print("Saved \(entries.count) mappings to \(path)")

case "restore":
    // WRITES. Applies a backup file, only touching buttons whose current mapping differs.
    let yes = argv.contains("--yes"); argv.removeAll { $0 == "--yes" }
    let profOverride = takeOpt("--profile").flatMap(parseByte)
    let rest = Array(argv.dropFirst())
    guard let path = rest.first else { print("usage: restore <file.json> [--profile XX] --yes"); exit(1) }
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)), let file = try? JSONDecoder().decode(BackupFile.self, from: data) else { print("Couldn't read \(path)"); exit(1) }
    guard let ctl = openControl() else { exit(1) }
    let (i, tid) = ctl
    if file.productID != String(format: "%04X", i.pid) { print("Warning: backup is from PID \(file.productID), this mouse is \(String(format: "%04X", i.pid)).") }
    var changes: [([UInt8], [UInt8], String)] = []
    var seen = Set<String>()
    for e in file.entries {
        guard var w = parseHexList(e.bytes), w.count == 10 else { print("Bad entry for button \(e.button); aborting."); exit(1) }
        if let p = profOverride { w[0] = p }
        guard seen.insert(hexBytes(w[1...2])).inserted else { continue }   // skip duplicate entries
        guard w[1] != 0x01 else { continue }   // never touch left click
        let cur = readMapHS(i.device, tid: tid, p: w[0], b: w[1], hs: w[2])
        if cur != w { changes.append((w, cur ?? [], e.description)) }
    }
    if changes.isEmpty { print("Mouse already matches \(path)."); exit(0) }
    for (w, cur, desc) in changes { print("  button \(String(format: "%02X", w[1]))\(w[2] == 1 ? " (Hypershift)" : ""): [\(hexBytes(cur))] -> \(desc)") }
    guard yes else { print("\(changes.count) change(s) above. Re-run with --yes to write them."); exit(0) }
    var failed = 0
    for (w, cur, _) in changes {
        appendBackupLog("restore button=\(String(format: "%02X", w[1])) hs=\(w[2]) before=[\(hexBytes(cur))]")
        let res = writeMap(i.device, tid: tid, w)
        if !res.ok { failed += 1; print("  FAILED button \(String(format: "%02X", w[1])): now [\(hexBytes(res.after ?? []))]") }
        usleep(35_000)
    }
    print(failed == 0 ? "Restored \(changes.count) mapping(s), all verified." : "\(failed) of \(changes.count) failed to verify.")

case "set":
    // WRITES one button. usage: set <profile> <button> <action> [args] [--hs] --yes
    //   actions: key <hid> [modifier] | mouse <n> | dpi up|down | raw <type> <params...>
    let yes = argv.contains("--yes"); argv.removeAll { $0 == "--yes" }
    let hs: UInt8 = argv.contains("--hs") ? 1 : 0; argv.removeAll { $0 == "--hs" }
    let a = Array(argv.dropFirst())
    let usage = "usage: set <profile> <button> key <hid> [mod] | mouse <n> | dpi up|down | raw <type> <params...>  [--hs] --yes"
    guard a.count >= 3, let p = parseByte(a[0]), let b = parseByte(a[1]) else { print(usage); exit(1) }
    guard b != 0x01 else { print("Refusing to remap left click."); exit(1) }
    let hexArgs = a.dropFirst(3).compactMap(parseByte)
    var action: [UInt8]
    switch a[2] {
    case "key":
        guard let k = hexArgs.first else { print(usage); exit(1) }
        action = [0x02, 0x01, hexArgs.count > 1 ? hexArgs[1] : 0x00, k]
    case "mouse":
        guard let n = hexArgs.first else { print(usage); exit(1) }
        action = [0x01, 0x01, n]
    case "dpi":
        guard a.count > 3, a[3] == "up" || a[3] == "down" else { print(usage); exit(1) }
        action = [0x06, 0x01, a[3] == "up" ? 0x01 : 0x02]
    case "raw":
        guard let t = hexArgs.first else { print(usage); exit(1) }
        action = [t, 0x01] + Array(hexArgs.dropFirst())
    default:
        print(usage); exit(1)
    }
    var w: [UInt8] = [p, b, hs] + action
    guard w.count <= 10 else { print("Too many parameter bytes."); exit(1) }
    w += [UInt8](repeating: 0, count: 10 - w.count)
    guard let ctl = openControl() else { exit(1) }
    let (i, tid) = ctl
    guard let before = readMapHS(i.device, tid: tid, p: p, b: b, hs: hs) else { print("Couldn't read the current mapping; nothing written."); exit(1) }
    print("before: \(decodeFull(before))   [\(hexBytes(before))]")
    print("new:    \(decodeFull(w))   [\(hexBytes(w))]")
    guard yes else { print("Re-run with --yes to write."); exit(0) }
    appendBackupLog("set profile=\(String(format: "%02X", p)) button=\(String(format: "%02X", b)) hs=\(hs) before=[\(hexBytes(before))]")
    let res = writeMap(i.device, tid: tid, w)
    print("after:  \(decodeFull(res.after ?? []))   [\(hexBytes(res.after ?? []))]")
    print(res.ok ? "Verified." : "Read-back does NOT match.")
    print("Undo: ./razerprobe set \(String(format: "%02X %02X", p, b)) raw \(hexBytes(before[3...3])) \(hexBytes(before[5...].reversed().drop(while: { $0 == 0 }).reversed()))\(hs == 1 ? " --hs" : "") --yes")

case "alphabet":
    // WRITES. Gives every button id the mouse reports (except left/right click and wheel up/down)
    // its own letter or digit, so pressing a physical button shows which id it is.
    // Saves the current state to alphabet-backup.json first. Undo: restore alphabet-backup.json --yes
    let yes = argv.contains("--yes"); argv.removeAll { $0 == "--yes" }
    let p: UInt8 = 0x01
    let keep: Set<UInt8> = [0x01, 0x02, 0x09, 0x0A]
    let chars = Array("abcdefghijklmnopqrstuvwxyz1234567890")
    func hidCode(_ c: Character) -> UInt8 {
        if let a = c.asciiValue, a >= 97, a <= 122 { return 0x04 + (a - 97) }
        if c == "0" { return 0x27 }
        return 0x1D + UInt8(String(c))!          // "1"..."9" -> 0x1E...0x26
    }
    guard let ctl = openControl() else { exit(1) }
    let (i, tid) = ctl
    var current: [UInt8: [UInt8]] = [:]
    for b in UInt8(0x01)...UInt8(0x7F) {
        if let m = readMapHS(i.device, tid: tid, p: p, b: b, hs: 0), m[2] == 0 { current[b] = m }
    }
    let targets = current.keys.sorted().filter { !keep.contains($0) }
    guard targets.count <= chars.count else { print("More ids than characters (\(targets.count))."); exit(1) }
    print("id   button              now                         -> types")
    for (n, b) in targets.enumerated() {
        let name = buttonName(b).padding(toLength: 18, withPad: " ", startingAt: 0)
        let now = decodeFull(current[b]!).padding(toLength: 27, withPad: " ", startingAt: 0)
        print(String(format: "%02X   ", b) + name + "  " + now + " -> \(chars[n])")
    }
    guard yes else { print("\n\(targets.count) buttons would change. Re-run with --yes to write."); exit(0) }
    let backup = BackupFile(format: "naga-config/1", created: ISO8601DateFormatter().string(from: Date()),
                            productID: String(format: "%04X", i.pid), firmware: "?", profile: "01",
                            entries: current.keys.sorted().map { b in
                                BackupEntry(button: String(format: "%02X", b), hypershift: 0,
                                            bytes: hexBytes(current[b]!), description: "\(buttonName(b)): \(decodeFull(current[b]!))") })
    let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
    do { try enc.encode(backup).write(to: URL(fileURLWithPath: "alphabet-backup.json")) }
    catch { print("Couldn't save alphabet-backup.json, nothing written: \(error)"); exit(1) }
    print("\nSaved current state to alphabet-backup.json")
    var failed: [String] = []
    for (n, b) in targets.enumerated() {
        let w: [UInt8] = [p, b, 0x00, 0x02, 0x01, 0x00, hidCode(chars[n]), 0x00, 0x00, 0x00]
        if !writeMap(i.device, tid: tid, w).ok { failed.append(String(format: "%02X", b)) }
        usleep(35_000)
    }
    print(failed.isEmpty ? "All \(targets.count) written and verified." : "Failed to verify: \(failed.joined(separator: " "))")
    print("Press every button in a text field. Undo with: ./razerprobe restore alphabet-backup.json --yes")

case "listen":
    // Read-only. Prints raw input reports from every Razer interface, to see whether a button
    // sends anything at all (and on which interface). Skips the pointer interface unless --mouse.
    let withMouse = argv.contains("--mouse"); argv.removeAll { $0 == "--mouse" }
    let secs = Double(argv.dropFirst().first ?? "20") ?? 20
    for i in all {
        if i.usagePage == 0x0001 && i.usage == 0x0002 && !withMouse { continue }
        guard openDev(i) else { continue }
        let size = max(intProp(i.device, kIOHIDMaxInputReportSizeKey), 64)
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
        listenLabels.append("[\(hex4(i.usagePage))/\(hex4(i.usage))]")
        IOHIDDeviceRegisterInputReportCallback(i.device, buf, size, { ctx, _, _, _, reportID, report, length in
            let idx = Int(bitPattern: ctx) - 1
            let label = idx >= 0 && idx < listenLabels.count ? listenLabels[idx] : "[?]"
            let bytes = UnsafeBufferPointer(start: report, count: length)
            print(label + String(format: " report %02X: ", reportID) + hexBytes(bytes))
            fflush(stdout)
        }, UnsafeMutableRawPointer(bitPattern: listenLabels.count))
        IOHIDDeviceScheduleWithRunLoop(i.device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        print("listening on \(listenLabels.last!)")
    }
    print("Listening for \(Int(secs)) s. Press the button(s) you want to test. Keep the mouse still.")
    fflush(stdout)
    _ = CFRunLoopRunInMode(CFRunLoopMode.defaultMode, secs, false)
    print("Done.")

case "setprofile":
    // WRITES (experimental). Tries to switch the active onboard profile with class 05 cmd 04
    // (the write counterpart of 0x84, which reports 01). Prints profile reads before and after.
    let yes = argv.contains("--yes"); argv.removeAll { $0 == "--yes" }
    let cmd: UInt8 = takeOpt("--cmd").flatMap(parseByte) ?? 0x04
    guard let n = argv.dropFirst().first.flatMap(parseByte), (1...5).contains(n) else { print("usage: setprofile <1-5> [--cmd XX] --yes"); exit(1) }
    guard cmd < 0x80 else { print("cmd must be a SET command (< 0x80)."); exit(1) }
    guard let ctl = openControl() else { exit(1) }
    let (i, tid) = ctl
    func profileState() -> String {
        [UInt8(0x80), 0x81, 0x84].map { c -> String in
            guard let r = transact(i.device, tid: tid, cls: 0x05, cmd: c, size: 0x0A), r[0] == 0x02 else { return String(format: "%02X:?", c) }
            return String(format: "%02X:[", c) + hexBytes(r[8..<(8 + min(Int(r[5]), 4))]) + "]"
        }.joined(separator: "  ")
    }
    let before = profileState()
    print("before: \(before)")
    guard yes else { print(String(format: "Would send class 05 cmd %02X with [%02X]. Re-run with --yes.", cmd, n)); exit(0) }
    appendBackupLog(String(format: "setprofile cmd=%02X n=%02X before=", cmd, n) + before)
    guard let r = transact(i.device, tid: tid, cls: 0x05, cmd: cmd, size: 0x0A, args: [n]) else { print("send failed"); exit(1) }
    print("write status: \(statusNames[r[0]] ?? String(format: "0x%02X", r[0]))")
    usleep(100_000)
    print("after:  \(profileState())")
    print("Undo: ./razerprobe setprofile 1\(cmd == 0x04 ? "" : String(format: " --cmd %02X", cmd)) --yes")

default:
    print("""
    razerprobe: read-only Razer HID probe
      list                         list Razer HID interfaces
      info  [--pid XXXX]           query firmware, serial, DPI, battery, etc.
      get <class> <cmd> <size> [args...] [--pid XXXX] [--tid XX]
                                   send one GET (cmd >= 0x80) and print the reply
      sweep <class> [size]         list which GET commands in a class the mouse recognizes
      mapscan [cmd] [size] [profile] [swap]
                                   probe class 0x02 button-map reads over profile/button ids
      buttons [profile]            show decoded button mappings (default profile 01)
      setkey <profile> <button> <hid key> [modifier] --yes
                                   WRITE: change one side button (40-4B) to a key, verify, print undo
      backup <file.json> [profile] save all mappings (normal + Hypershift) to a file (read-only)
      restore <file.json> [--profile XX] [--yes]
                                   show differences; with --yes write them and verify
      set <profile> <button> key <hid> [mod] | mouse <n> | dpi up|down | raw <type> <params...> [--hs] [--yes]
                                   preview one change; with --yes write it, verify, print undo
      alphabet [--yes]             give every reported button id its own letter (backs up first)
      listen [seconds] [--mouse]   print raw input reports from the mouse (read-only)
      setprofile <1-5> [--cmd XX] [--yes]
                                   EXPERIMENTAL: try to switch the active onboard profile
    """)
}
