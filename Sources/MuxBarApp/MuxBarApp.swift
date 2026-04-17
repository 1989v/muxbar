import SwiftUI
import MuxLogging

@main
struct MuxBarApp: App {
    init() {
        MuxLogging.bootstrap()
        MuxLogging.logger("app").info("muxbar 기동")
    }

    var body: some Scene {
        MenuBarExtra("muxbar", systemImage: "terminal") {
            Text("muxbar 기동됨")
                .padding()
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .menuBarExtraStyle(.window)
    }
}
