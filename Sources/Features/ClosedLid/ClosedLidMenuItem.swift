import SwiftUI
import Core

public struct ClosedLidMenuItem: View {
    @ObservedObject public var store: ClosedLidStore
    @ObservedObject public var preferences: ClosedLidPreferences
    public let onTurnOn: (Duration?, Bool) -> Void
    public let onTurnOff: () -> Void

    @State private var showingPicker = false
    @State private var customMode = false
    @State private var customMinutesText: String = ""
    @State private var now = Date()

    public init(
        store: ClosedLidStore,
        preferences: ClosedLidPreferences,
        onTurnOn: @escaping (Duration?, Bool) -> Void,
        onTurnOff: @escaping () -> Void
    ) {
        self.store = store
        self.preferences = preferences
        self.onTurnOn = onTurnOn
        self.onTurnOff = onTurnOff
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Image(systemName: store.state.isOn ? "lock.fill" : "lock")
                    .foregroundStyle(store.state.isOn ? .red : .secondary)
                Text(L.menuClosedLid)
                Spacer()
                if store.isToggling {
                    ProgressView().scaleEffect(0.6)
                } else {
                    Text(stateLabel)
                        .font(.caption)
                        .foregroundStyle(store.state.isOn ? .red : .secondary)
                }
            }
            if store.state.isOn {
                Text(L.closedLidSubtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            if store.state.isOn { onTurnOff() }
            else {
                customMode = false
                customMinutesText = String(preferences.lastCustomMinutes)
                showingPicker = true
            }
        }
        .popover(isPresented: $showingPicker, arrowEdge: .leading) {
            if customMode { customDurationView } else { presetPickerView }
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { date in
            if store.state.isOn { now = date }
        }
    }

    private var stateLabel: String {
        switch store.state {
        case .off:
            return L.closedLidStateOff
        case .on(let expiresAt):
            guard let expiresAt else { return L.closedLidStateOnInf }
            let remaining = max(0, Int(expiresAt.timeIntervalSince(now)))
            let h = remaining / 3600
            let m = (remaining % 3600) / 60
            let s = remaining % 60
            let timeStr = String(format: "%d:%02d:%02d", h, m, s)
            return L.closedLidStateOnTimer(timeStr)
        }
    }

    private var presetPickerView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L.closedLidDuration).font(.caption).foregroundStyle(.secondary)

            Toggle(isOn: $preferences.alsoStopKeepAwakeOnEnd) {
                Text(L.closedLidAlsoStopKeepAwake).font(.caption)
            }
            .toggleStyle(.checkbox)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)

            Divider()

            ForEach(Self.durationOptions(), id: \.label) { opt in
                Button(opt.label) {
                    showingPicker = false
                    onTurnOn(opt.duration, preferences.alsoStopKeepAwakeOnEnd)
                }
                .buttonStyle(.plain)
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
            }

            Button(L.closedLidDurationCustom) {
                customMode = true
            }
            .buttonStyle(.plain)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
        }
        .padding(8)
        .frame(minWidth: 220)
    }

    private var customDurationView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(L.closedLidDurationCustomBack) {
                customMode = false
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack {
                TextField(L.closedLidDurationCustomMinutesPlaceholder, text: $customMinutesText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                Text("min").foregroundStyle(.secondary).font(.caption)
            }

            Button(L.closedLidDurationCustomStart) {
                guard let minutes = Int(customMinutesText.trimmingCharacters(in: .whitespaces)),
                      minutes > 0 else { return }
                preferences.lastCustomMinutes = minutes
                showingPicker = false
                onTurnOn(.seconds(minutes * 60), preferences.alsoStopKeepAwakeOnEnd)
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(12)
        .frame(minWidth: 220)
    }

    private static func durationOptions() -> [(label: String, duration: Duration?)] {
        [
            (L.closedLidDuration30m, .seconds(1800)),
            (L.closedLidDuration1h, .seconds(3600)),
            (L.closedLidDuration4h, .seconds(14400)),
            (L.closedLidDuration8h, .seconds(28800)),
            (L.closedLidDurationInf, nil),
        ]
    }
}
