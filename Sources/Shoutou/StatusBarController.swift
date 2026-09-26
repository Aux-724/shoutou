import AppKit
import ShoutouCore
import SwiftUI

@MainActor
final class StatusBarController: NSObject, NSWindowDelegate {
    private let statusItem: NSStatusItem
    private let panel: CenterPanel
    private let host: NSHostingController<QuestBoardView>
    private let store: QuestStore
    private let chrome: AppChrome
    private let defaults = UserDefaults(suiteName: "local.luoyidong.shoutou") ?? .standard
    private var lastClose: Date?
    private var ignoreResignUntil = Date.distantPast
    private var isPlacing = false
    private var isClosing = false
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var resizeMonitor: Any?
    private let minPanelWidth: CGFloat = 320
    private let minPanelHeight: CGFloat = 420
    private let resizeThickness: CGFloat = 7
    private let resizeCorner: CGFloat = 18

    init(store: QuestStore, chrome: AppChrome) {
        self.store = store
        self.chrome = chrome
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        host = NSHostingController(rootView: QuestBoardView(store: store, chrome: chrome))
        panel = CenterPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 440),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovable = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.acceptsMouseMovedEvents = true
        panel.title = "手头"
        panel.contentViewController = host
        panel.delegate = self
        host.view.wantsLayer = true
        host.view.layer?.backgroundColor = NSColor.clear.cgColor
        installResizeMonitor()

        if let button = statusItem.button {
            if let image = NSImage(systemSymbolName: "flag.fill", accessibilityDescription: "手头") {
                let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
                image.isTemplate = true
                button.image = image.withSymbolConfiguration(config)
            }
            button.imagePosition = .imageLeading
            button.font = NSFont.systemFont(ofSize: 13, weight: .medium)
            button.target = self
            button.action = #selector(handleClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        chrome.onPinnedChange = { [weak self] pinned in
            self?.applyPinned(pinned)
        }
        store.onChange = { [weak self] in
            self?.refreshMenuBar()
        }
        refreshMenuBar()
    }

    func toggleFromHotkey() {
        if panel.isVisible {
            closePanel()
        } else {
            show()
        }
    }

    func showOnLaunchIfNeeded() {
        let shouldShow = chrome.isPinned || defaults.bool(forKey: "didAutoOpen") == false
        guard shouldShow else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.show()
            self?.defaults.set(true, forKey: "didAutoOpen")
        }
    }

    func show() {
        guard !panel.isVisible else { return }
        NSApp.activate()
        let size = preferredSize(on: screenUnderMouse())
        place(size: size)
        ignoreResignUntil = Date().addingTimeInterval(0.3)
        panel.orderFrontRegardless()
        panel.makeKey()
        statusItem.button?.isHighlighted = true
        if !chrome.isPinned {
            installMonitors()
        }
        ensureResizeHandles()
        chrome.refreshLoginStatus()
    }

    func refreshMenuBar() {
        guard let button = statusItem.button else { return }
        let title = store.menuBarTitle
        button.title = title
        button.toolTip = store.menuBarToolTip
        button.setAccessibilityLabel("手头 \(title)")
    }

    func windowDidResignKey(_ notification: Notification) {
        guard !chrome.isPinned, Date() > ignoreResignUntil else { return }
        closePanel()
    }

    func windowDidMove(_ notification: Notification) {
        guard chrome.isPinned, !isPlacing else { return }
        savePosition()
    }

    @objc private func handleClick() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showQuitMenu()
            return
        }
        if let lastClose, Date().timeIntervalSince(lastClose) < 0.25 {
            return
        }
        if panel.isVisible {
            closePanel()
        } else {
            show()
        }
    }

    private func applyPinned(_ pinned: Bool) {
        if pinned {
            removeMonitors()
            if panel.isVisible {
                savePosition()
            }
        } else if panel.isVisible {
            installMonitors()
        }
    }

    private func closePanel() {
        guard panel.isVisible, !isClosing else { return }
        isClosing = true
        removeMonitors()
        panel.orderOut(nil)
        statusItem.button?.isHighlighted = false
        lastClose = Date()
        store.flush()
        isClosing = false
    }

    private func closeFromOutsideClick() {
        guard !chrome.isPinned else { return }
        closePanel()
    }

    private func installMonitors() {
        guard globalMonitor == nil else { return }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                self?.closeFromOutsideClick()
            }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown, event.keyCode == 53, !self.chrome.isPinned {
                self.closePanel()
                return nil
            }
            if event.type != .keyDown, event.window !== self.panel {
                self.closeFromOutsideClick()
            }
            return event
        }
    }

    private func removeMonitors() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    private func preferredSize(on screen: NSScreen) -> NSSize {
        let limit = screen.visibleFrame.insetBy(dx: 24, dy: 24)
        let raw: NSSize
        if defaults.object(forKey: "panelWidth") != nil, defaults.object(forKey: "panelHeight") != nil {
            raw = NSSize(width: defaults.double(forKey: "panelWidth"), height: defaults.double(forKey: "panelHeight"))
        } else {
            raw = NSSize(width: 380, height: 560)
        }
        return NSSize(
            width: min(max(raw.width, minPanelWidth), max(limit.width, minPanelWidth)),
            height: min(max(raw.height, minPanelHeight), max(limit.height, minPanelHeight))
        )
    }

    private func saveSize() {
        defaults.set(Double(panel.frame.width), forKey: "panelWidth")
        defaults.set(Double(panel.frame.height), forKey: "panelHeight")
    }

    private func ensureResizeHandles() {
        guard let content = panel.contentView, content.bounds.width > 1, content.bounds.height > 1 else { return }
        content.subviews.compactMap { $0 as? ResizeHandle }.forEach { $0.removeFromSuperview() }
        installResizeHandles()
    }

    private func installResizeHandles() {
        guard let content = panel.contentView else { return }
        let bounds = content.bounds
        let t = resizeThickness
        let c = resizeCorner
        let flipped = content.isFlipped
        let topY = flipped ? 0 : bounds.height - t
        let bottomY = flipped ? bounds.height - t : 0
        let topMask: NSView.AutoresizingMask = flipped ? [.width] : [.width, .minYMargin]
        let bottomMask: NSView.AutoresizingMask = flipped ? [.width, .minYMargin] : [.width]
        let topCornerY = flipped ? 0 : bounds.height - c
        let bottomCornerY = flipped ? bounds.height - c : 0
        let topLeftMask: NSView.AutoresizingMask = flipped ? [] : [.minYMargin]
        let bottomLeftMask: NSView.AutoresizingMask = flipped ? [.minYMargin] : []
        let topRightMask: NSView.AutoresizingMask = flipped ? [.minXMargin] : [.minXMargin, .minYMargin]
        let bottomRightMask: NSView.AutoresizingMask = flipped ? [.minXMargin, .minYMargin] : [.minXMargin]
        addResizeHandle(.left, frame: NSRect(x: 0, y: 0, width: t, height: bounds.height), mask: [.height], in: content)
        addResizeHandle(.right, frame: NSRect(x: bounds.width - t, y: 0, width: t, height: bounds.height), mask: [.minXMargin, .height], in: content)
        addResizeHandle(.bottom, frame: NSRect(x: 0, y: bottomY, width: bounds.width, height: t), mask: bottomMask, in: content)
        addResizeHandle(.top, frame: NSRect(x: 0, y: topY, width: bounds.width, height: t), mask: topMask, in: content)
        addResizeHandle([.bottom, .left], frame: NSRect(x: 0, y: bottomCornerY, width: c, height: c), mask: bottomLeftMask, in: content)
        addResizeHandle([.bottom, .right], frame: NSRect(x: bounds.width - c, y: bottomCornerY, width: c, height: c), mask: bottomRightMask, in: content)
        addResizeHandle([.top, .left], frame: NSRect(x: 0, y: topCornerY, width: c, height: c), mask: topLeftMask, in: content)
        addResizeHandle([.top, .right], frame: NSRect(x: bounds.width - c, y: topCornerY, width: c, height: c), mask: topRightMask, in: content)
    }

    private func addResizeHandle(_ edges: PanelEdges, frame: NSRect, mask: NSView.AutoresizingMask, in content: NSView) {
        let handle = ResizeHandle(edges: edges)
        handle.frame = frame
        handle.autoresizingMask = mask
        handle.onBegan = { [weak self] in
            MainActor.assumeIsolated {
                self?.isPlacing = true
            }
        }
        handle.onEnded = { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isPlacing = false
                self.saveSize()
                if self.chrome.isPinned {
                    self.savePosition()
                }
            }
        }
        content.addSubview(handle)
    }

    private func installResizeMonitor() {
        resizeMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            guard let self, let handle = self.resizeHandle(at: event) else { return event }
            handle.mouseDown(with: event)
            return nil
        }
    }

    private func resizeHandle(at event: NSEvent) -> ResizeHandle? {
        guard panel.isVisible, event.window === panel, let content = panel.contentView else { return nil }
        let local = content.convert(event.locationInWindow, from: nil)
        let handles = content.subviews.compactMap { $0 as? ResizeHandle }
        return handles.reversed().first { $0.frame.contains(local) }
    }

    private func place(size: NSSize) {
        let screen: NSScreen
        let origin: NSPoint
        if chrome.isPinned, let saved = savedOrigin(), let savedScreen = screenContaining(saved) {
            screen = savedScreen
            origin = saved
        } else {
            screen = screenUnderMouse()
            let visible = screen.visibleFrame
            origin = NSPoint(
                x: visible.midX - size.width / 2,
                y: visible.midY - size.height / 2
            )
        }
        isPlacing = true
        panel.setFrame(
            NSRect(origin: clamped(origin, size: size, in: screen.visibleFrame), size: size),
            display: true
        )
        isPlacing = false
    }

    private func screenContaining(_ origin: NSPoint) -> NSScreen? {
        let probe = NSPoint(x: origin.x + 8, y: origin.y + 8)
        return NSScreen.screens.first { $0.frame.contains(probe) }
    }

    private func screenUnderMouse() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    private func clamped(_ origin: NSPoint, size: NSSize, in visible: NSRect) -> NSPoint {
        let x = min(max(origin.x, visible.minX), max(visible.minX, visible.maxX - size.width))
        let y = min(max(origin.y, visible.minY), max(visible.minY, visible.maxY - size.height))
        return NSPoint(x: x, y: y)
    }

    private func savePosition() {
        guard let screen = panel.screen else { return }
        let visible = screen.visibleFrame
        let frame = screen.frame
        defaults.set(true, forKey: "hasPinnedPosition")
        defaults.set(panel.frame.origin.x - visible.minX, forKey: "pinnedOffsetX")
        defaults.set(panel.frame.origin.y - visible.minY, forKey: "pinnedOffsetY")
        defaults.set(frame.origin.x, forKey: "pinnedScreenX")
        defaults.set(frame.origin.y, forKey: "pinnedScreenY")
        defaults.set(frame.size.width, forKey: "pinnedScreenW")
        defaults.set(frame.size.height, forKey: "pinnedScreenH")
    }

    private func savedOrigin() -> NSPoint? {
        guard defaults.bool(forKey: "hasPinnedPosition") else { return nil }
        let screenX = defaults.double(forKey: "pinnedScreenX")
        let screenY = defaults.double(forKey: "pinnedScreenY")
        let screenW = defaults.double(forKey: "pinnedScreenW")
        let screenH = defaults.double(forKey: "pinnedScreenH")
        guard let screen = NSScreen.screens.first(where: { candidate in
            abs(candidate.frame.origin.x - screenX) < 2
                && abs(candidate.frame.origin.y - screenY) < 2
                && abs(candidate.frame.size.width - screenW) < 2
                && abs(candidate.frame.size.height - screenH) < 2
        }) else {
            return nil
        }
        let visible = screen.visibleFrame
        return NSPoint(
            x: visible.minX + defaults.double(forKey: "pinnedOffsetX"),
            y: visible.minY + defaults.double(forKey: "pinnedOffsetY")
        )
    }

    private func showQuitMenu() {
        guard let button = statusItem.button else { return }
        let menu = NSMenu()
        let item = NSMenuItem(title: "退出手头", action: #selector(quit), keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button)
    }

    @objc private func quit() {
        store.flush()
        NSApp.terminate(nil)
    }
}

private struct PanelEdges: OptionSet {
    let rawValue: Int
    static let top = PanelEdges(rawValue: 1 << 0)
    static let bottom = PanelEdges(rawValue: 1 << 1)
    static let left = PanelEdges(rawValue: 1 << 2)
    static let right = PanelEdges(rawValue: 1 << 3)

    var cursor: NSCursor {
        if #available(macOS 15, *) {
            let position: NSCursor.FrameResizePosition
            switch (contains(.top), contains(.bottom), contains(.left), contains(.right)) {
            case (true, _, true, _):
                position = .topLeft
            case (true, _, _, true):
                position = .topRight
            case (_, true, true, _):
                position = .bottomLeft
            case (_, true, _, true):
                position = .bottomRight
            case (true, _, _, _):
                position = .top
            case (_, true, _, _):
                position = .bottom
            case (_, _, true, _):
                position = .left
            default:
                position = .right
            }
            return NSCursor.frameResize(position: position, directions: .all)
        }
        if contains(.left) || contains(.right) {
            return .resizeLeftRight
        }
        return .resizeUpDown
    }
}

private final class CenterPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class ResizeHandle: NSView {
    let edges: PanelEdges
    var onBegan: (() -> Void)?
    var onEnded: (() -> Void)?

    init(edges: PanelEdges) {
        self.edges = edges
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: edges.cursor)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .cursorUpdate, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    override func cursorUpdate(with event: NSEvent) {
        edges.cursor.set()
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        onBegan?()
        let startFrame = window.frame
        let startMouse = NSEvent.mouseLocation
        let edges = edges
        window.trackEvents(
            matching: [.leftMouseDragged, .leftMouseUp],
            timeout: .infinity,
            mode: .eventTracking
        ) { event, stop in
            guard let event else { return }
            let mouse = NSEvent.mouseLocation
            let frame = resizedFrame(
                start: startFrame,
                dx: mouse.x - startMouse.x,
                dy: mouse.y - startMouse.y,
                edges: edges,
                screen: window.screen
            )
            window.setFrame(frame, display: true)
            if event.type == .leftMouseUp {
                stop.pointee = true
            }
        }
        onEnded?()
    }
}

private func resizedFrame(
    start: NSRect,
    dx: CGFloat,
    dy: CGFloat,
    edges: PanelEdges,
    screen: NSScreen?
) -> NSRect {
    var frame = start
    if edges.contains(.left) {
        frame.origin.x += dx
        frame.size.width -= dx
    }
    if edges.contains(.right) {
        frame.size.width += dx
    }
    if edges.contains(.bottom) {
        frame.origin.y += dy
        frame.size.height -= dy
    }
    if edges.contains(.top) {
        frame.size.height += dy
    }

    let minWidth: CGFloat = 320
    let minHeight: CGFloat = 420
    let maxWidth = max((screen?.visibleFrame.width ?? 1400) - 24, minWidth)
    let maxHeight = max((screen?.visibleFrame.height ?? 1000) - 24, minHeight)

    if frame.width < minWidth {
        if edges.contains(.left) {
            frame.origin.x = start.maxX - minWidth
        }
        frame.size.width = minWidth
    } else if frame.width > maxWidth {
        if edges.contains(.left) {
            frame.origin.x = start.maxX - maxWidth
        }
        frame.size.width = maxWidth
    }

    if frame.height < minHeight {
        if edges.contains(.bottom) {
            frame.origin.y = start.maxY - minHeight
        }
        frame.size.height = minHeight
    } else if frame.height > maxHeight {
        if edges.contains(.bottom) {
            frame.origin.y = start.maxY - maxHeight
        }
        frame.size.height = maxHeight
    }
    return frame
}
