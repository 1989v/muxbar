import Foundation
import IOKit

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

    public init() {}

    @MainActor
    public func onLidOpen(_ handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        self.lastClosed = readClamshellClosed() ?? false

        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        IONotificationPortSetDispatchQueue(port, DispatchQueue.main)
        self.notifyPort = port

        guard let matching = IOServiceMatching("AppleClamshellState") else { return }
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard svc != 0 else { return }
        self.service = svc

        let context = Unmanaged.passUnretained(self).toOpaque()
        var note: io_object_t = 0
        let kr = IOServiceAddInterestNotification(
            port, svc, kIOGeneralInterest,
            { (ctx, _, _, _) in
                guard let ctx else { return }
                let me = Unmanaged<IOKitLidStateMonitor>.fromOpaque(ctx).takeUnretainedValue()
                DispatchQueue.main.async { me.recheck() }
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
        if notification != 0 { IOObjectRelease(notification); notification = 0 }
        if service != 0 { IOObjectRelease(service); service = 0 }
        if let port = notifyPort { IONotificationPortDestroy(port) }
        notifyPort = nil
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
