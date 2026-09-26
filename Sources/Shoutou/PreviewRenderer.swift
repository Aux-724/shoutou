import AppKit
import ShoutouCore
import SwiftUI

@MainActor
enum PreviewRenderer {
    static func writeAll() {
        write(name: "empty-light", scheme: .light, fill: false)
        write(name: "empty-dark", scheme: .dark, fill: false)
        write(name: "board-light", scheme: .light, fill: true)
        write(name: "board-dark", scheme: .dark, fill: true)
    }

    private static func write(name: String, scheme: ColorScheme, fill: Bool) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("shoutou-preview-\(UUID().uuidString).json")
        let store = QuestStore(fileURL: url)
        if fill {
            populate(store)
        }
        let view = QuestBoardView(store: store, chrome: AppChrome())
            .environment(\.colorScheme, scheme)
            .frame(width: 380)
        let host = NSHostingController(rootView: view)
        let fitted = host.sizeThatFits(in: NSSize(width: 380, height: 1200))
        let size = NSSize(width: 380, height: max(fitted.height, 200))
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        window.contentViewController = host
        window.setContentSize(size)
        window.setFrameOrigin(NSPoint(x: 80, y: 120))
        window.level = .floating
        window.makeKeyAndOrderFront(nil)
        let until = Date().addingTimeInterval(0.35)
        while Date() < until {
            RunLoop.current.run(mode: .default, before: until)
        }
        host.view.layoutSubtreeIfNeeded()
        let bounds = host.view.bounds
        guard let rep = host.view.bitmapImageRepForCachingDisplay(in: bounds) else {
            print("render failed \(name)")
            window.close()
            return
        }
        host.view.cacheDisplay(in: bounds, to: rep)
        window.close()
        guard let png = rep.representation(using: .png, properties: [:]) else {
            print("png failed \(name)")
            return
        }
        let out = URL(fileURLWithPath: "/tmp/shoutou-\(name).png")
        do {
            try png.write(to: out)
            print(out.path)
        } catch {
            print("write failed \(name)")
        }
    }

    private static func populate(_ store: QuestStore) {
        if let parked = store.add(title: "整理参考文献", subtaskTitle: "把重复的条目删掉") {
            store.park(parked.id)
        }
        if let done = store.add(title: "导出预实验数据", subtaskTitle: "存成 csv") {
            store.complete(done.id)
        }
        store.add(title: "回导师关于开题的邮件", subtaskTitle: "附上上周的进度表")
        store.add(title: "修问卷的跳题", subtaskTitle: "第 6 题选否应跳到第 9 题")
        store.add(title: "改排除标准", subtaskTitle: "把反应时小于 100ms 的试次标出来")
    }
}
