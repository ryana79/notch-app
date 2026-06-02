//
//  NotchProDesign.swift
//  NotchPro
//

import SwiftUI

enum NotchProDesign {
    static let cardRadius: CGFloat = 14
    static let pillRadius: CGFloat = 999
    static let compactSpacing: CGFloat = 6

    /// Lightweight card — solid fill, no blur (battery-friendly).
    static func cardBackground(opacity: Double = 0.08) -> some View {
        RoundedRectangle(cornerRadius: cardRadius, style: .continuous)
            .fill(Color.white.opacity(opacity))
    }

    static func cardBorder(accent: Color = .white, opacity: Double = 0.12) -> some View {
        RoundedRectangle(cornerRadius: cardRadius, style: .continuous)
            .strokeBorder(accent.opacity(opacity), lineWidth: 0.5)
    }
}

struct NotchProCard<Content: View>: View {
    var accent: Color = .white
    var accentOpacity: Double = 0.12
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background {
                ZStack {
                    NotchProDesign.cardBackground()
                    NotchProDesign.cardBorder(accent: accent, opacity: accentOpacity)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: NotchProDesign.cardRadius, style: .continuous))
    }
}

struct NotchProPill<Content: View>: View {
    var tint: Color = .white
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(tint.opacity(0.12))
            .overlay {
                Capsule()
                    .strokeBorder(tint.opacity(0.2), lineWidth: 0.5)
            }
            .clipShape(Capsule())
    }
}

struct AlbumArtRing: View {
    let color: Color
    let lineWidth: CGFloat
    @State private var rotation: Double = 0

    var body: some View {
        Circle()
            .strokeBorder(
                AngularGradient(
                    colors: [
                        color.opacity(0.95),
                        color.opacity(0.25),
                        color.opacity(0.75),
                        color.opacity(0.15),
                        color.opacity(0.95),
                    ],
                    center: .center
                ),
                lineWidth: lineWidth
            )
            .rotationEffect(.degrees(rotation))
            .onAppear {
                withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
}

struct MusicPlayingAura: View {
    let color: Color
    let isPlaying: Bool
    @State private var breathe = false

    var body: some View {
        if isPlaying {
            ZStack {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .stroke(color.opacity(breathe ? 0.45 - Double(index) * 0.1 : 0.2 - Double(index) * 0.05), lineWidth: 1.5)
                        .scaleEffect((breathe ? 1.12 : 0.92) + CGFloat(index) * 0.14)
                        .blur(radius: CGFloat(index) * 1.5)
                }
                Circle()
                    .fill(color.opacity(breathe ? 0.18 : 0.08))
                    .blur(radius: 6)
            }
            .allowsHitTesting(false)
            .onAppear {
                breathe = false
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                    breathe = true
                }
            }
            .onChange(of: isPlaying) { _, playing in
                if playing {
                    breathe = false
                    withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                        breathe = true
                    }
                } else {
                    breathe = false
                }
            }
        }
    }
}

struct NotchAmbientGlow: View {
    let color: Color
    let isActive: Bool

    var body: some View {
        if isActive {
            ZStack {
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [color.opacity(0.45), color.opacity(0.12), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 140
                        )
                    )
                    .frame(height: 100)
                    .blur(radius: 28)
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [color.opacity(0.25), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 80
                        )
                    )
                    .frame(width: 200, height: 40)
                    .blur(radius: 12)
                    .offset(y: 8)
            }
            .allowsHitTesting(false)
        }
    }
}
