import SwiftUI
import NagaKit

struct ContentView: View {
    @StateObject private var model = AppModel()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: model.connected ? "computermouse.fill" : "computermouse")
                    .foregroundStyle(model.connected ? Color.green : Color.secondary)
                Text(model.status).lineLimit(2).foregroundStyle(.secondary)
                Spacer()
                if model.busy { ProgressView().controlSize(.small) }
                Button("Read from Mouse") { model.read() }.disabled(model.busy)
            }
            .padding(12)

            Divider()

            List {
                ForEach(Naga.groups, id: \.self) { group in
                    Section(group) {
                        ForEach(Naga.buttons.filter { $0.group == group }) { button in
                            ButtonRow(model: model, button: button)
                        }
                    }
                }
            }

            Divider()

            HStack {
                Button("Open…") { model.open() }
                Button("Save…") { model.save() }
                Button("Factory Defaults") { model.factoryDefaults() }
                Spacer()
                if model.pendingCount > 0 {
                    Text("\(model.pendingCount) change(s) not applied").foregroundStyle(.orange)
                    Button("Revert") { model.revert() }
                }
                Button("Apply to Mouse") { model.apply() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.busy || model.pendingCount == 0 || !model.connected)
            }
            .padding(12)
        }
        .frame(minWidth: 760, minHeight: 600)
        .onAppear { model.read() }
    }
}

struct ButtonRow: View {
    @ObservedObject var model: AppModel
    let button: NagaButton

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Circle()
                .fill(model.isChanged(button.id) ? Color.orange : Color.clear)
                .frame(width: 7, height: 7)
            Text(button.name).frame(width: 170, alignment: .leading)
            if model.action(button.id) == nil {
                Text(model.connected ? "Not reported by the mouse" : "—").foregroundStyle(.secondary)
            } else if !button.editable {
                Text(model.action(button.id)!.summary + " (locked so you can always click)").foregroundStyle(.secondary)
            } else {
                ActionEditor(action: model.binding(button.id), buttonID: button.id)
            }
            Spacer()
        }
        .padding(.vertical, 2)
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
    case raw = "Other (not decoded)"
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
