import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct SephiriaOptimizerApplication: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppViewModel()

    var body: some Scene {
        WindowGroup("Sephiria Optimizer") {
            ContentView(model: model)
        }
        .defaultSize(width: 1_440, height: 900)
        .commands {
            CommandGroup(after: .newItem) {
                Button("게임 인벤토리 캡처") { model.captureFromGame() }
            }
        }
    }
}
