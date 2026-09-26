import AppKit
import ShoutouCore
import SwiftUI

@MainActor
enum PreviewRenderer {
    static func writeAll() {
        write(name: "board-dark", scheme: .dark, fill: true, composing: false, height: 620)
        write(name: "compose-dark", scheme: .dark, fill: true, composing: true, height: 780)
    }

    private static func write(name: String, scheme: ColorScheme, fill: Bool, composing: Bool, height: CGFloat) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("shoutou-preview-\(UUID().uuidString).json")
        let store = QuestStore(fileURL: url)
        if fill {
            populate(store)
        }
        let chrome = AppChrome()
        chrome.isPinned = false
        let view = QuestBoardView(store: store, chrome: chrome, startsComposing: composing)
            .environment(\.colorScheme, scheme)
            .frame(width: 400, height: height)
        let host = NSHostingController(rootView: view)
        let size = NSSize(width: 400, height: height)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        window.contentViewController = host
        window.setContentSize(size)
        window.setFrameOrigin(NSPoint(x: 2700, y: 360))
        window.level = .floating
        if composing {
            window.makeKeyAndOrderFront(nil)
        } else {
            window.orderFrontRegardless()
        }
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
        store.add(title: "回导师关于开题的邮件", subtaskTitle: "附上上周的进度表")
        if let survey = store.add(title: "修问卷的跳题", subtaskTitle: "第 6 题选否应跳到第 9 题") {
            store.addSubtask(questID: survey.id, title: "检查第 12 题是不是必填")
        }
        if let main = store.add(title: "改排除标准", subtaskTitle: "标出反应时过短的试次") {
            store.addSubtask(questID: main.id, title: "重跑三组种子")
            if let first = main.subtasks.first {
                store.setSubtaskDone(questID: main.id, subtaskID: first.id, isDone: true)
            }
        }
    }
}
