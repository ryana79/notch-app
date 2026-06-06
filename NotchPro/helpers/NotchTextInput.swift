//
//  NotchTextInput.swift
//  NotchPro
//

import AppKit
import SwiftUI

struct NotchTextInputField: View {
    let placeholder: String
    @Binding var text: String
    var axis: Axis = .horizontal
    var lineLimit: ClosedRange<Int>? = nil
    var onSubmit: (() -> Void)? = nil

    var body: some View {
        Group {
            if let lineLimit, axis == .vertical {
                TextField(placeholder, text: $text, axis: .vertical)
                    .lineLimit(lineLimit)
            } else if axis == .vertical {
                TextField(placeholder, text: $text, axis: .vertical)
            } else {
                TextField(placeholder, text: $text)
            }
        }
        .textFieldStyle(.plain)
        .onTapGesture {
            NotchProCoordinator.shared.activateTextInput()
        }
        .onChange(of: text) { _, _ in
            NotchProCoordinator.shared.activateTextInput()
        }
        .onSubmit {
            onSubmit?()
        }
    }
}

extension NotchProCoordinator {
    func activateTextInput() {
        isNotchTextInputActive = true
        if let window = NSApp.windows.first(where: { $0 is NotchProSkyLightWindow || $0 is NotchProWindow }) {
            window.makeKeyAndOrderFront(nil)
        }
    }

    func deactivateTextInput() {
        isNotchTextInputActive = false
    }
}
