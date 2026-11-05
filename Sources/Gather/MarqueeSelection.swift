import SwiftUI
import AppKit

struct ScreenshotFrames: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct MarqueeSelection: NSViewRepresentable {
    let model: AppModel
    let frames: [UUID: CGRect]
    func makeNSView(context: Context) -> MarqueeView { MarqueeView() }
    func updateNSView(_ view: MarqueeView, context: Context) {
        view.model = model; view.frames = frames
        if !model.batchMode && view.selecting { view.cancelSelection() }
    }
    static func dismantleNSView(_ view: MarqueeView, coordinator: ()) { view.stopMonitoring() }
}

final class MarqueeView: NSView {
    weak var model: AppModel?
    var frames: [UUID: CGRect] = [:]
    private var monitor: Any?
    private var origin: NSPoint?
    private var rectangle: CGRect?
    private var initial: Set<UUID> = []
    private var clickedID: UUID?
    private var rightButton = false
    private(set) var selecting = false
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopMonitoring()
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .rightMouseDown, .rightMouseDragged, .rightMouseUp, .keyDown]) { [weak self] event in
            let consumed = MainActor.assumeIsolated {
                guard let self else { return false }
                return self.handle(event) == nil
            }
            return consumed ? nil : event
        }
    }
    func stopMonitoring() {
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        cancelSelection()
    }
    func cancelSelection() {
        origin = nil; rectangle = nil; selecting = false; needsDisplay = true
    }
    private func handle(_ event: NSEvent) -> NSEvent? {
        guard let model, event.window === window else { return event }
        if event.type == .keyDown {
            if event.keyCode == 53, origin != nil {
                cancelSelection(); model.endBatchSelection(); return nil
            }
            return event
        }
        let point = convert(event.locationInWindow, from: nil)
        let down = event.type == .leftMouseDown || event.type == .rightMouseDown
        if down {
            guard visibleRect.contains(point), !model.batchBusy, !model.deleting, !model.cleanupBusy else { return event }
            let hit = frames.first { $0.value.contains(point) }?.key
            let right = event.type == .rightMouseDown
            // Ordinary card drags continue to export the screenshot to other apps.
            guard right || model.batchMode || hit == nil else { return event }
            origin = point; clickedID = hit; rightButton = right; selecting = false
            initial = event.modifierFlags.intersection([.command, .shift]).isEmpty ? [] : model.batchSelection
            return nil
        }
        guard let origin else { return event }
        if event.type == .leftMouseDragged || event.type == .rightMouseDragged {
            guard hypot(point.x - origin.x, point.y - origin.y) >= 4 || selecting else { return nil }
            selecting = true
            let rect = CGRect(x: min(origin.x, point.x), y: min(origin.y, point.y), width: abs(point.x - origin.x), height: abs(point.y - origin.y))
            rectangle = rect
            model.batchMode = true
            model.batchSelection = initial.union(frames.compactMap { rect.intersects($0.value) ? $0.key : nil })
            needsDisplay = true
            autoscroll(with: event)
            return nil
        }
        if event.type == .leftMouseUp || event.type == .rightMouseUp {
            let wasSelecting = selecting
            cancelSelection()
            if !wasSelecting {
                if rightButton { showMenu(event, itemID: clickedID) }
                else if let clickedID { model.toggleBatchSelection(clickedID) }
                else { model.batchSelection = [] }
            }
            return nil
        }
        return event
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let rectangle else { return }
        NSColor.controlAccentColor.withAlphaComponent(0.12).setFill()
        NSBezierPath(rect: rectangle).fill()
        NSColor.controlAccentColor.setStroke()
        let border = NSBezierPath(rect: rectangle.insetBy(dx: 0.5, dy: 0.5)); border.lineWidth = 1; border.stroke()
    }
    private var menuItemID: UUID?
    private func showMenu(_ event: NSEvent, itemID: UUID?) {
        guard let model else { return }
        menuItemID = itemID
        let menu = NSMenu()
        func add(_ title: String, _ action: Selector, enabled: Bool = true) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self; item.isEnabled = enabled; menu.addItem(item)
        }
        menu.autoenablesItems = false
        if let itemID {
            add(model.batchSelection.contains(itemID) ? "Deselect Screenshot" : "Select Screenshot", #selector(selectScreenshot))
            add("Copy Text", #selector(copyText), enabled: !(model.items.first { $0.id == itemID }?.extractedText.isEmpty ?? true))
            add("Open Image", #selector(openImage))
            add("Show in Finder", #selector(showInFinder))
            add("Favorite / Unfavorite", #selector(toggleFavorite))
            menu.addItem(.separator())
            add("Delete Screenshot…", #selector(deleteScreenshot), enabled: model.canDelete)
        } else {
            add("Select Screenshots", #selector(startSelection))
        }
        add("Select All", #selector(selectAllScreenshots))
        if model.batchMode { add("Done Selecting", #selector(doneSelecting)) }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
    @objc private func selectScreenshot() {
        guard let model, let menuItemID else { return }
        model.batchMode = true; model.toggleBatchSelection(menuItemID)
    }
    @objc private func startSelection() { model?.batchMode = true }
    @objc private func selectAllScreenshots() { guard let model else { return }; model.batchMode = true; model.batchSelection = Set(model.visible.map(\.id)) }
    @objc private func doneSelecting() { model?.endBatchSelection() }
    @objc private func copyText() { if let model, let item = model.items.first(where: { $0.id == menuItemID }) { model.copyText(item) } }
    @objc private func openImage() { if let model, let item = model.items.first(where: { $0.id == menuItemID }) { model.openImage(item) } }
    @objc private func showInFinder() { if let model, let item = model.items.first(where: { $0.id == menuItemID }) { model.showInFinder(item) } }
    @objc private func toggleFavorite() { if let model, let menuItemID { model.update(menuItemID) { $0.favorite.toggle() } } }
    @objc private func deleteScreenshot() { if let menuItemID { model?.requestDeletion([menuItemID]) } }
}
