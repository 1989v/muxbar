import SwiftUI
import Core

public struct ClosedLidMenuItem: View {
    @ObservedObject public var store: ClosedLidStore
    public let onTurnOn: (Duration?) -> Void
    public let onTurnOff: () -> Void

    @State private var showingPicker = false
    @State private var now = Date()

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

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
                Text("Closed-lid mode")
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
                Text("sleep blocked (system-wide)")
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
        .onReceive(tick) { now = $0 }
    }

    private var stateLabel: String {
        switch store.state {
        case .off:
            return "OFF"
        case .on(let expiresAt):
            guard let expiresAt else { return "ON · ∞" }
            let remaining = max(0, Int(expiresAt.timeIntervalSince(now)))
            let h = remaining / 3600
            let m = (remaining % 3600) / 60
            let s = remaining % 60
            return String(format: "ON · %d:%02d:%02d", h, m, s)
        }
    }

    private var durationPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Duration").font(.caption).foregroundStyle(.secondary)
            ForEach(durationOptions, id: \.label) { opt in
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

    private var durationOptions: [(label: String, duration: Duration?)] {
        [
            ("1 hour", .seconds(3600)),
            ("4 hours", .seconds(14400)),
            ("8 hours", .seconds(28800)),
            ("∞ (until manual off)", nil),
        ]
    }
}
