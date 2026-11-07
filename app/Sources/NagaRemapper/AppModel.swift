import AppKit
import SwiftUI
import UniformTypeIdentifiers
import NagaKit

final class AppModel: ObservableObject {
    @Published var status = "Not connected"
    @Published var busy = false
    @Published var connected = false
    /// What the mouse currently holds: id -> 10 bytes.
    @Published var onMouse: [UInt8: [UInt8]] = [:]
    /// Pending changes not yet written to the mouse: id -> 10 bytes.
    @Published var pending: [UInt8: [UInt8]] = [:]

    private var device: RazerDevice?
    private var firmware = "?"
    private let queue = DispatchQueue(label: "naga.device")
    let profile = Naga.profile

    var pendingCount: Int { pending.count }

    // MARK: Reading state

    func effectiveBytes(_ id: UInt8) -> [UInt8]? { pending[id] ?? onMouse[id] }

    func action(_ id: UInt8) -> ButtonAction? { effectiveBytes(id).map(ButtonAction.init(bytes:)) }

    func isChanged(_ id: UInt8) -> Bool { pending[id] != nil }

    func binding(_ id: UInt8) -> Binding<ButtonAction> {
        Binding(get: { self.action(id) ?? .raw([]) },
                set: { self.setAction($0, for: id) })
    }

    func setAction(_ a: ButtonAction, for id: UInt8) {
        setBytes(a.bytes(profile: profile, button: id), for: id)
    }

    private func setBytes(_ b: [UInt8], for id: UInt8) {
        if b == onMouse[id] { pending[id] = nil } else { pending[id] = b }
    }

    // MARK: Device operations

    func read() {
        run("Reading the mouse…") { dev in
            var map: [UInt8: [UInt8]] = [:]
            for id in Naga.allIDs {
                if let b = try dev.readMapping(profile: self.profile, button: id) { map[id] = b }
            }
            DispatchQueue.main.async {
                self.onMouse = map
                self.pending = self.pending.filter { map[$0.key] != $0.value }
            }
            return "Connected: \(dev.productName), firmware \(self.firmware)"
        }
    }

    func apply() {
        let changes = pending.sorted { $0.key < $1.key }
        guard !changes.isEmpty else { return }
        run("Writing \(changes.count) change(s)…") { dev in
            var done: [UInt8: [UInt8]] = [:]
            var failures: [String] = []
            for (id, b) in changes {
                do { try dev.writeMapping(b); done[id] = b } catch {
                    failures.append(String(format: "0x%02X: ", id) + error.localizedDescription)
                }
                usleep(35_000)
            }
            DispatchQueue.main.async {
                for (id, b) in done { self.onMouse[id] = b; self.pending[id] = nil }
            }
            return failures.isEmpty ? "Wrote and verified \(done.count) change(s)."
                                    : "Wrote \(done.count); failed: " + failures.joined(separator: "; ")
        }
    }

    private func run(_ message: String, _ work: @escaping (RazerDevice) throws -> String) {
        busy = true
        status = message
        queue.async {
            let result: String
            do {
                if self.device == nil {
                    let d = try RazerDevice()
                    self.device = d
                    self.firmware = d.firmware()
                }
                result = try work(self.device!)
                DispatchQueue.main.async { self.connected = true }
            } catch {
                self.device = nil
                result = error.localizedDescription
                DispatchQueue.main.async { self.connected = false }
            }
            DispatchQueue.main.async { self.status = result; self.busy = false }
        }
    }

    // MARK: Files and presets

    func revert() { pending = [:] }

    func factoryDefaults() {
        for (id, b) in Naga.factoryBytes(profile: profile) where id != 0x01 { setBytes(b, for: id) }
        status = "Factory defaults loaded. Click Apply to write them to the mouse."
    }

    func save() {
        var merged = onMouse
        for (id, b) in pending { merged[id] = b }
        guard !merged.isEmpty else { status = "Nothing to save yet. Read the mouse first."; return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "naga-profile.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let file = ConfigFile(productID: 0x00E7, firmware: firmware, profile: profile, mappings: merged)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try enc.encode(file).write(to: url)
            status = "Saved \(url.lastPathComponent)" + (pending.isEmpty ? "." : " (includes changes not yet applied).")
        } catch { status = "Couldn't save: \(error.localizedDescription)" }
    }

    func open() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let file = try JSONDecoder().decode(ConfigFile.self, from: Data(contentsOf: url))
            let maps = file.mappings(profile: profile)
            for (id, b) in maps where id != 0x01 && Naga.allIDs.contains(id) { setBytes(b, for: id) }
            status = "Loaded \(url.lastPathComponent): \(pending.count) change(s). Click Apply to write them."
        } catch { status = "Couldn't open that file: \(error.localizedDescription)" }
    }
}
