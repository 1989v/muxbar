import Foundation
import IOKit

private final class MonitorWeakBox<T: AnyObject> {
    weak var value: T?
    init(_ v: T) { value = v }
}

public protocol LidStateMonitor: AnyObject {
    /// lid가 닫힘→열림 transition 감지 시 1회 호출. 자동 stop.
    @MainActor func onLidOpen(_ handler: @escaping @MainActor () -> Void)
    @MainActor func stop()
}

public final class IOKitLidStateMonitor: LidStateMonitor {
    private var notifyPort: IONotificationPortRef?
    private var notification: io_object_t = 0
    private var service: io_service_t = 0
    private var handler: (@MainActor () -> Void)?
    private var lastClosed: Bool = false
    private var contextBox: MonitorWeakBox<IOKitLidStateMonitor>?

    public init() {}

    @MainActor
    public func onLidOpen(_ handler: @escaping @MainActor () -> Void) {
        stop()  // clean up any prior subscription
        self.handler = handler
        self.lastClosed = readClamshellClosed() ?? false

        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        // Dispatch queue avoids menu-open run-loop mode blocking that CFRunLoopAddSource(.defaultMode) would suffer.
        IONotificationPortSetDispatchQueue(port, DispatchQueue.main)
        self.notifyPort = port

        guard let matching = IOServiceMatching("AppleClamshellState") else { return }
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard svc != 0 else { return }
        self.service = svc

        let box = MonitorWeakBox(self)
        self.contextBox = box
        let context = Unmanaged.passUnretained(box).toOpaque()

        var note: io_object_t = 0
        let kr = IOServiceAddInterestNotification(
            port, svc, kIOGeneralInterest,
            { (ctx, _, _, _) in
                guard let ctx else { return }
                let box = Unmanaged<MonitorWeakBox<IOKitLidStateMonitor>>.fromOpaque(ctx).takeUnretainedValue()
                DispatchQueue.main.async { box.value?.recheck() }
            },
            context, &note
        )
        if kr == KERN_SUCCESS {
            self.notification = note
        }
    }

    @MainActor
    private func recheck() {
        guard let nowClosed = readClamshellClosed() else { return }
        if lastClosed && !nowClosed {
            handler?()
            stop()
            return
        }
        lastClosed = nowClosed
    }

    @MainActor
    public func stop() {
        // Release notification FIRST so no new callbacks get scheduled.
        if notification != 0 { IOObjectRelease(notification); notification = 0 }
        if service != 0 { IOObjectRelease(service); service = 0 }
        if let port = notifyPort { IONotificationPortDestroy(port) }
        notifyPort = nil
        // Drop the box. Any in-flight DispatchQueue.main.async closure still holds it via capture
        // until it runs; callback delivery is fenced by IOKit notification removal above.
        contextBox = nil
        handler = nil
    }

    private func readClamshellClosed() -> Bool? {
        guard let matching = IOServiceMatching("AppleClamshellState") else { return nil }
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard svc != 0 else { return nil }
        defer { IOObjectRelease(svc) }
        let value = IORegistryEntryCreateCFProperty(svc, "AppleClamshellState" as CFString,
                                                     kCFAllocatorDefault, 0)?.takeRetainedValue()
        return value as? Bool
    }
}
