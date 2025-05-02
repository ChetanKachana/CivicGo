// Inside View+Extensions.swift (or any other appropriate Swift file)

import SwiftUI

#if canImport(UIKit)
// Extension to provide a common way to dismiss the keyboard
extension View {
    func hideKeyboard() {
        // Sends the resignFirstResponder action through the responder chain
        // to hopefully find the currently focused text field and dismiss its keyboard.
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
#endif
