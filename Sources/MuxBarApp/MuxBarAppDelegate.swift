import AppKit
import MuxLogging

@MainActor
final class MuxBarAppDelegate: NSObject, NSApplicationDelegate {
    private let logger = MuxLogging.logger("AppDelegate")

    func applicationWillFinishLaunching(_ notification: Notification) {
        // LSUIElement 에이전트는 idle/시스템 압박 시 자동 종료 대상이 됨.
        // Info.plist 의 NSSupports*Termination=false 와 함께 런타임 카운터로 이중 opt-out.
        ProcessInfo.processInfo.disableAutomaticTermination("menu bar agent")
        ProcessInfo.processInfo.disableSuddenTermination()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("launched pid=\(getpid())")

        let nc = NSWorkspace.shared.notificationCenter
        let events: [(Notification.Name, String)] = [
            (NSWorkspace.willSleepNotification, "willSleep"),
            (NSWorkspace.didWakeNotification, "didWake"),
            (NSWorkspace.willPowerOffNotification, "willPowerOff"),
        ]
        for (name, label) in events {
            nc.addObserver(forName: name, object: nil, queue: .main) { _ in
                MuxLogging.logger("AppDelegate").info("\(label)")
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        logger.critical("willTerminate")
    }
}
