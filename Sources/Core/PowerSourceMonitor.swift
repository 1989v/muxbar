import Foundation
import IOKit
import IOKit.ps

private final class MonitorWeakBox<T: AnyObject> {
    weak var value: T?
    init(_ v: T) { value = v }
}

public protocol PowerSourceMonitor: AnyObject {
    /// AC 어댑터 분리(AC → Battery transition) 시 1회 호출. 자동으로 stop. 재구독 필요시 다시 호출.
    @MainActor func onACDisconnect(_ handler: @escaping @MainActor () -> Void)
    @MainActor func stop()
}

public final class IOKitPowerSourceMonitor: PowerSourceMonitor {
    private var runLoopSource: CFRunLoopSource?
    private var handler: (@MainActor () -> Void)?
    private var contextBox: MonitorWeakBox<IOKitPowerSourceMonitor>?

    public init() {}

    @MainActor
    public func onACDisconnect(_ handler: @escaping @MainActor () -> Void) {
        stop()  // clean up any prior subscription
        self.handler = handler

        let box = MonitorWeakBox(self)
        self.contextBox = box
        let context = Unmanaged.passUnretained(box).toOpaque()

        // IOPSNotificationCreateRunLoopSource must be attached to a run loop;
        // main run loop delivers on main thread.
        let src = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            let box = Unmanaged<MonitorWeakBox<IOKitPowerSourceMonitor>>.fromOpaque(ctx).takeUnretainedValue()
            DispatchQueue.main.async { box.value?.checkAndFireIfDisconnected() }
        }, context)?.takeRetainedValue()
        guard let src else { return }
        self.runLoopSource = src
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
    }

    @MainActor
    private func checkAndFireIfDisconnected() {
        guard !isOnAC() else { return }
        handler?()
        stop()
    }

    @MainActor
    public func stop() {
        // Remove from run loop FIRST so no new callbacks get scheduled.
        if let src = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .defaultMode)
        }
        runLoopSource = nil
        // Drop the box. Any in-flight DispatchQueue.main.async closure still holds it via capture
        // until it runs; callback delivery is fenced by IOKit run-loop-source removal above.
        contextBox = nil
        handler = nil
    }

    private func isOnAC() -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return true }
        for src in sources {
            guard let desc = IOPSGetPowerSourceDescription(info, src)?.takeUnretainedValue() as? [String: Any],
                  let type = desc[kIOPSTypeKey] as? String,
                  type == kIOPSInternalBatteryType,
                  let state = desc[kIOPSPowerSourceStateKey] as? String
            else { continue }
            return state == kIOPSACPowerValue
        }
        return true  // no internal battery found — laptop without battery (Mac mini etc.) — assume AC
    }
}
