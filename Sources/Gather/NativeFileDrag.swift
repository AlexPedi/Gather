import SwiftUI
import AppKit
import GatherCore

/// Use AppKit's file pasteboard directly, including its copy-only drag operation.
struct NativeFileDrag: NSViewRepresentable {
    let item: Screenshot
    let model: AppModel
    let select: () -> Void
    func makeNSView(context: Context) -> FileDragView { FileDragView() }
    func updateNSView(_ view: FileDragView, context: Context) {
        view.item = item; view.model = model; view.select = select
    }
}

final class FileDragView: NSView, NSDraggingSource {
    var item: Screenshot?
    weak var model: AppModel?
    var select: (() -> Void)?
    private var origin: NSPoint?
    private var dragging = false
    override func mouseDown(with event: NSEvent) {
        origin = convert(event.locationInWindow, from: nil)
        dragging = false
        select?()
    }
    override func mouseUp(with event: NSEvent) {
        defer { origin = nil; dragging = false }
        if !dragging, event.clickCount == 2, let item, let model, !model.batchMode { model.openImage(item) }
    }
    override func mouseDragged(with event: NSEvent) {
        guard !dragging, let origin, let item, let model, !model.cleanupBusy else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard hypot(point.x - origin.x, point.y - origin.y) >= 4 else { return }
        dragging = true
        do {
            let url = try DragFileExport.copy(item: item, directory: model.dragDirectory)
            let drag = NSDraggingItem(pasteboardWriter: url as NSURL)
            let image = NSImage(contentsOf: url) ?? NSWorkspace.shared.icon(forFile: url.path)
            let size = NSSize(width: 150, height: 110)
            drag.setDraggingFrame(NSRect(origin: NSPoint(x: point.x - 75, y: point.y - 55), size: size), contents: image)
            beginDraggingSession(with: [drag], event: event, source: self)
        } catch {
            model.error = "Could not drag this image.\n\(error.localizedDescription)"
        }
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }
}

extension View {
    func nativeFileDrag(item: Screenshot, model: AppModel, select: @escaping () -> Void) -> some View {
        overlay { NativeFileDrag(item: item, model: model, select: select) }
    }
}
