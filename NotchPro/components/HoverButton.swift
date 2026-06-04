//
//  HoverButton.swift
//  notchpro
//
//  Created by Kraigo on 04.09.2024.
//

import SwiftUI

struct HoverButton: View {
    var icon: String
    var iconColor: Color = .primary
    var scale: Image.Scale = .medium
    var action: () -> Void
    var contentTransition: ContentTransition = .symbolEffect

    @State private var isHovering = false

    private var diameter: CGFloat {
        scale == .large ? 44 : 34
    }

    private var hoverScale: CGFloat {
        if !isHovering { return 1 }
        return scale == .large ? 1.1 : 1.08
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(isHovering ? 0.16 : 0.08))
                Circle()
                    .strokeBorder(Color.white.opacity(isHovering ? 0.22 : 0.1), lineWidth: 0.5)
                Image(systemName: icon)
                    .font(scale == .large ? .title2.weight(.semibold) : .body.weight(.semibold))
                    .foregroundStyle(iconColor)
                    .contentTransition(contentTransition)
            }
            .frame(width: diameter, height: diameter)
            .scaleEffect(hoverScale)
        }
        .buttonStyle(.plain)
        .animation(.smooth(duration: 0.2), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}
