import SwiftUI
import NagaKit

struct ContentView: View {
    @StateObject private var model = AppModel()

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(model: model)

            ScrollView {
                VStack(spacing: 16) {
                    ForEach(Naga.groups, id: \.self) { group in
                        GroupCard(model: model, group: group)
                    }
                }
                .padding(20)
            }
            .background(Color(nsColor: .underPageBackgroundColor))

            FooterView(model: model)
        }
        .frame(minWidth: 820, minHeight: 640)
        .onAppear { model.read() }
    }
}

// MARK: - Header

struct HeaderView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.65)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "computermouse.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 2) {
                Text("Naga Remapper").font(.title2.weight(.semibold))
                Text(model.status)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            StatusPill(connected: model.connected, busy: model.busy)

            Button { model.read() } label: {
                Label("Read from Mouse", systemImage: "arrow.clockwise")
            }
            .disabled(model.busy)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }
}

struct StatusPill: View {
    let connected: Bool
    let busy: Bool

    var body: some View {
        HStack(spacing: 6) {
            if busy {
                ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 10, height: 10)
            } else {
                Circle().fill(connected ? Color.green : Color.secondary).frame(width: 8, height: 8)
            }
            Text(busy ? "Working…" : (connected ? "Connected" : "Not connected"))
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
    }
}

// MARK: - Groups

struct GroupCard: View {
    @ObservedObject var model: AppModel
    let group: String

    private var buttons: [NagaButton] { Naga.buttons.filter { $0.group == group } }

    private var icon: String {
        switch group {
        case "Top": return "cursorarrow.click.2"
        case "Scroll wheel": return "arrow.up.and.down.circle"
        case "12-button side panel": return "square.grid.3x3"
        case "6-button side panel": return "square.grid.3x2"
        case "2-button side panel": return "arrow.left.arrow.right.circle"
        default: return "ellipsis.circle"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: icon).foregroundStyle(Color.accentColor)
                Text(group).font(.headline)
                Spacer()
                let changed = buttons.filter { model.isChanged($0.id) }.count
                if changed > 0 {
                    Text("\(changed) changed")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            ForEach(Array(buttons.enumerated()), id: \.element.id) { index, button in
                ButtonRow(model: model, button: button)
                if index < buttons.count - 1 {
                    Divider().padding(.leading, 14)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        )
        .shadow(color: .black.opacity(0.04), radius: 3, y: 1)
    }
}

struct ButtonRow: View {
    @ObservedObject var model: AppModel
    let button: NagaButton
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(model.isChanged(button.id) ? Color.orange : Color.clear)
                .frame(width: 3, height: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text(button.name)
                Text(String(format: "ID 0x%02X", button.id))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 170, alignment: .leading)

            if model.action(button.id) == nil {
                Text(model.connected ? "Not reported by the mouse" : "—").foregroundStyle(.secondary)
            } else if !button.editable {
                Label(model.action(button.id)!.summary + " · locked so you can always click", systemImage: "lock.fill")
                    .foregroundStyle(.secondary)
            } else {
                ActionEditor(action: model.binding(button.id), buttonID: button.id)
            }

            Spacer()

            if model.isChanged(button.id) {
                Text("Changed")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.orange.opacity(0.15)))
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(hovering ? Color.primary.opacity(0.035) : Color.clear)
        .onHover { hovering = $0 }
    }
}

// MARK: - Footer

struct FooterView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            Button { model.open() } label: { Label("Open…", systemImage: "folder") }
            Button { model.save() } label: { Label("Save…", systemImage: "square.and.arrow.down") }
            Button { model.factoryDefaults() } label: { Label("Factory Defaults", systemImage: "arrow.counterclockwise") }

            Spacer()

            if model.pendingCount > 0 {
                Text("\(model.pendingCount) change\(model.pendingCount == 1 ? "" : "s") not applied")
                    .font(.callout)
                    .foregroundStyle(.orange)
                Button("Revert") { model.revert() }
            }
            Button { model.apply() } label: {
                Label("Apply to Mouse", systemImage: "arrow.down.to.line")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(model.busy || model.pendingCount == 0 || !model.connected)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}

enum ActionKind: String, CaseIterable, Identifiable {
    case keyboard = "Keyboard key"
    case mouse = "Mouse function"
    case dpiUp = "DPI up"
    case dpiDown = "DPI down"
    case scrollLeft = "Scroll left (tilt)"
    case scrollRight = "Scroll right (tilt)"
    case scrollMode = "Scroll mode toggle"
    case profileCycle = "Profile cycle"
    case firmwareDefault = "Firmware default"
    case disabled = "Unbound (does nothing)"
    case raw = "Unknown action"
    var id: String { rawValue }

    init(_ a: ButtonAction) {
        switch a {
        case .key: self = .keyboard
        case .mouse: self = .mouse
        case .dpiUp: self = .dpiUp
        case .dpiDown: self = .dpiDown
        case .tiltLeft: self = .scrollLeft
        case .tiltRight: self = .scrollRight
        case .scrollModeToggle: self = .scrollMode
        case .profileCycle: self = .profileCycle
        case .firmwareDefault: self = .firmwareDefault
        case .disabled: self = .disabled
        case .raw: self = .raw
        }
    }

    func defaultAction() -> ButtonAction {
        switch self {
        case .keyboard: return .key(modifiers: 0, key: 0x04)
        case .mouse: return .mouse(0x03)
        case .dpiUp: return .dpiUp
        case .dpiDown: return .dpiDown
        case .scrollLeft: return .tiltLeft
        case .scrollRight: return .tiltRight
        case .scrollMode: return .scrollModeToggle
        case .profileCycle: return .profileCycle
        case .firmwareDefault: return .firmwareDefault
        case .disabled: return .disabled
        case .raw: return .raw([])
        }
    }
}

struct ActionEditor: View {
    @Binding var action: ButtonAction
    let buttonID: UInt8

    private var kindBinding: Binding<ActionKind> {
        Binding(get: { ActionKind(action) },
                set: { newKind in if newKind != ActionKind(action) { action = newKind.defaultAction() } })
    }

    var body: some View {
        HStack(spacing: 8) {
            Picker("", selection: kindBinding) {
                ForEach(ActionKind.allCases.filter { $0 != .raw || ActionKind(action) == .raw }) { k in
                    Text(k.rawValue).tag(k)
                }
            }
            .labelsHidden()
            .frame(width: 190)

            switch action {
            case .key(let mods, let key):
                modifierToggle("⌃", Modifiers.control, mods, key)
                modifierToggle("⌥", Modifiers.option, mods, key)
                modifierToggle("⇧", Modifiers.shift, mods, key)
                modifierToggle("⌘", Modifiers.command, mods, key)
                Picker("", selection: Binding(get: { key }, set: { action = .key(modifiers: mods, key: $0) })) {
                    if !HIDKey.all.contains(where: { $0.code == key }) {
                        Text(HIDKey.name(key)).tag(key)
                    }
                    ForEach(HIDKey.all) { k in Text(k.name).tag(k.code) }
                }
                .labelsHidden()
                .frame(width: 170)
            case .mouse(let n):
                Picker("", selection: Binding(get: { n }, set: { action = .mouse($0) })) {
                    if !MouseFunction.all.contains(where: { $0.code == n }) {
                        Text(MouseFunction.name(n)).tag(n)
                    }
                    ForEach(MouseFunction.all) { f in Text(f.name).tag(f.code) }
                }
                .labelsHidden()
                .frame(width: 170)
            case .raw:
                Text(action.summary).font(.system(.body, design: .monospaced)).foregroundStyle(.secondary)
            default:
                EmptyView()
            }
        }
    }

    private func modifierToggle(_ symbol: String, _ bit: UInt8, _ mods: UInt8, _ key: UInt8) -> some View {
        Toggle(symbol, isOn: Binding(get: { mods & bit != 0 },
                                     set: { on in action = .key(modifiers: on ? (mods | bit) : (mods & ~bit), key: key) }))
            .toggleStyle(.button)
    }
}
