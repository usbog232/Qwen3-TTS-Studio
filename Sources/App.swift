import SwiftUI

@main
struct Qwen3TTSStudioApp: App {
    @StateObject private var app = AppState()

    var body: some Scene {
        WindowGroup("Qwen3-TTS Studio") {
            RootView()
                .environmentObject(app)
                .frame(minWidth: 880, minHeight: 640)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 980, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
