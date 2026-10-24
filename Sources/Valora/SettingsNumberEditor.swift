import AppKit
import SwiftUI

/// Alcove 1.7.9 edits numbers inside the existing capsule. Valid input updates
/// the slider immediately; Return closes the editor, while Escape and blur do
/// not roll the value back (live reference captures, 2026-10-18).
struct SettingsNumberEditor: NSViewRepresentable {
    @Binding var text: String
    let label: String
    let onEdit: (String) -> String?
    let onFinish: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: text)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .monospacedSystemFont(ofSize: 13.5, weight: .regular)
        field.textColor = .labelColor
        field.alignment = .right
        field.lineBreakMode = .byClipping
        field.setAccessibilityLabel(label)
        field.delegate = context.coordinator
        DispatchQueue.main.async { [weak field] in
            guard let field, let window = field.window else { return }
            window.makeFirstResponder(field)
            field.selectText(nil)
        }
        return field
    }
    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
    }
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SettingsNumberEditor
        init(_ parent: SettingsNumberEditor) { self.parent = parent }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            let input = field.stringValue
            let normalized = parent.onEdit(input) ?? input
            parent.text = normalized
            if normalized != input { field.stringValue = normalized }
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if selector == #selector(NSResponder.insertNewline(_:)) {
                control.window?.makeFirstResponder(nil)
                parent.onFinish()
                return true
            }
            // The reference leaves editing active on Escape.
            return selector == #selector(NSResponder.cancelOperation(_:))
        }
    }
}
