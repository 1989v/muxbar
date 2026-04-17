import SwiftUI

@main
struct MuxBarApp: App {
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
