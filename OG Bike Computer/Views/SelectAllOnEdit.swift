//
//  SelectAllOnEdit.swift
//  OG Bike Computer
//
//  Selects a text field's whole contents when it starts editing, so typing
//  replaces it. Works on alert text fields, which ignore TextField(selection:).
//

import SwiftUI
import UIKit

private struct SelectAllOnEdit: ViewModifier {
    let isActive: Bool

    func body(content: Content) -> some View {
        content.onReceive(NotificationCenter.default.publisher(for: UITextField.textDidBeginEditingNotification)) { note in
            // The notification fires for every text field in the app, so only
            // act while our own alert is up.
            guard isActive, let field = note.object as? UITextField else { return }
            // UIKit places the caret after begin-editing, so select on the next pass.
            DispatchQueue.main.async { field.selectAll(nil) }
        }
    }
}

extension View {
    func selectAllOnEdit(when isActive: Bool) -> some View {
        modifier(SelectAllOnEdit(isActive: isActive))
    }
}
