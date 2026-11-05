import SwiftUI
import AppKit

/// An AppKit search field supports explicit first-responder focus in the library.
struct NativeSearchField: NSViewRepresentable {
    @Binding var text: String
    var focusRequest: Int
    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }
    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.placeholderString = "Search screenshots, text, or tags…"
        field.font = .systemFont(ofSize: 17)
        field.controlSize = .large
        field.isBordered = false
        field.focusRingType = .none
        field.isBezeled = false
        field.drawsBackground = false
        field.cell?.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.delegate = context.coordinator
        field.setAccessibilityLabel("Search screenshots, extracted text, tags, or collections")
        return field
    }
    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.text = $text
        if field.stringValue != text { field.stringValue = text }
        if context.coordinator.lastRequest != focusRequest {
            context.coordinator.lastRequest = focusRequest
            DispatchQueue.main.async { field.window?.makeFirstResponder(field) }
        }
    }
    @MainActor final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        var lastRequest = 0
        init(text: Binding<String>) { self.text = text }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.cancelOperation(_:)), let field = control as? NSTextField else { return false }
            field.stringValue = ""; text.wrappedValue = ""
            return true
        }
        func controlTextDidChange(_ notification: Notification) {
            if let field = notification.object as? NSTextField { text.wrappedValue = field.stringValue }
        }
    }
}
