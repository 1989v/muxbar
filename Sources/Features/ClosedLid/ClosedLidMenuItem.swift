import SwiftUI
import Core

public struct ClosedLidMenuItem: View {
    @ObservedObject public var store: ClosedLidStore
    public let onTurnOn: (Duration?) -> Void
    public let onTurnOff: () -> Void

    @State private var showingPicker = false
    @State private var now = Date()

    public init(
        store: ClosedLidStore,
        onTurnOn: @escaping (Duration?) -> Void,
        onTurnOff: @escaping () -> Void
    ) {
        self.store = store
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
            else { showingPicker = true }
        }
        .popover(isPresented: $showingPicker, arrowEdge: .leading) {
            durationPicker
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

    private var durationPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L.closedLidDuration).font(.caption).foregroundStyle(.secondary)
            ForEach(Self.durationOptions(), id: \.label) { opt in
                Button(opt.label) {
                    showingPicker = false
                    onTurnOn(opt.duration)
                }
                .buttonStyle(.plain)
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
            }
        }
        .padding(8)
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
