import AppKit
import ShoutouCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = QuestStore()
    let chrome = AppChrome()
    var statusBar: StatusBarController?
    let hotkey = GlobalHotkey()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let statusBar = StatusBarController(store: store, chrome: chrome)
        self.statusBar = statusBar
        HotkeyBridge.shared.onPress = { [weak statusBar] in
            statusBar?.toggleFromHotkey()
        }
        chrome.hotkeyReady = hotkey.register()
        statusBar.showOnLaunchIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.flush()
    }
}

@main
enum ShoutouMain {
    @MainActor
    static func main() {
        if CommandLine.arguments.contains("--render-preview") {
            let app = NSApplication.shared
            app.setActivationPolicy(.accessory)
            PreviewRenderer.writeAll()
            return
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
