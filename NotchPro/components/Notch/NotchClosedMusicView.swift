//
//  NotchClosedMusicView.swift
//  NotchPro
//

import Defaults
import SwiftUI

struct NotchClosedMusicView: View {
    @ObservedObject var musicManager = MusicManager.shared
    @EnvironmentObject var vm: NotchProViewModel

    let albumArtNamespace: Namespace.ID
    var totalWidth: CGFloat

    @Default(.useMusicVisualizer) private var useMusicVisualizer
    @Default(.playerColorTinting) private var playerColorTinting
    @Default(.coloredSpectrogram) private var coloredSpectrogram
    @Default(.performanceMode) private var performanceMode

    @State private var pulse = false
    @State private var sweep = false
    @State private var ringPulse = false

    private var accentColor: Color {
        if playerColorTinting {
            return Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.6)
        }
        return Color.effectiveAccent
    }

    private var barHeight: CGFloat {
        max(28, vm.effectiveClosedNotchHeight + 4)
    }

    private var artSize: CGFloat {
        max(26, min(barHeight - 4, 32))
    }

    /// Transparent gap over the physical notch — not a black box.
    private var notchGap: CGFloat {
        max(36, vm.closedNotchSize.width - 24)
    }

    private var progress: Double {
        guard musicManager.songDuration > 0 else { return 0 }
        if musicManager.isPlaying {
            let delta = Date().timeIntervalSince(musicManager.timestampDate)
            let elapsed = musicManager.elapsedTime + delta * musicManager.playbackRate
            return min(max(elapsed / musicManager.songDuration, 0), 1)
        }
        return min(max(musicManager.elapsedTime / musicManager.songDuration, 0), 1)
    }

    private var showPlaybackEffects: Bool {
        musicManager.isPlaying && !performanceMode
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            capsuleBackground
                .frame(width: totalWidth, height: barHeight)

            HStack(spacing: 0) {
                leftCluster
                    .frame(maxWidth: .infinity, alignment: .trailing)

                Color.clear
                    .frame(width: notchGap)
                    .allowsHitTesting(false)

                rightCluster
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: totalWidth, height: barHeight)
            .padding(.horizontal, 8)

            progressBar
        }
        .frame(width: totalWidth, height: barHeight + 6, alignment: .center)
        .onAppear { startAnimations() }
        .onChange(of: musicManager.isPlaying) { _, _ in startAnimations() }
    }

    private var capsuleBackground: some View {
        Capsule(style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        accentColor.opacity(musicManager.isPlaying ? 0.5 : 0.18),
                        Color(white: 0.06),
                        accentColor.opacity(musicManager.isPlaying ? 0.38 : 0.12),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .overlay {
                if musicManager.isPlaying {
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    .clear,
                                    accentColor.opacity(0.28),
                                    .white.opacity(0.1),
                                    accentColor.opacity(0.2),
                                    .clear,
                                ],
                                startPoint: sweep ? .leading : .trailing,
                                endPoint: sweep ? .trailing : .leading
                            )
                        )
                        .blendMode(.plusLighter)
                }
            }
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                accentColor.opacity(pulse ? 0.95 : 0.45),
                                .white.opacity(0.2),
                                accentColor.opacity(pulse ? 0.7 : 0.35),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.2
                    )
            }
            .shadow(color: accentColor.opacity(musicManager.isPlaying ? 0.55 : 0.15), radius: pulse ? 14 : 8)
    }

    private var progressBar: some View {
        GeometryReader { geo in
            Capsule()
                .fill(accentColor.opacity(0.95))
                .frame(width: max(4, geo.size.width * progress), height: 2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: totalWidth - 20, height: 2)
        .offset(y: 3)
    }

    private var leftCluster: some View {
        HStack(spacing: 8) {
            albumArtCluster

            VStack(alignment: .leading, spacing: 1) {
                MarqueeText(
                    .constant(musicManager.songTitle),
                    font: .caption.weight(.semibold),
                    nsFont: .caption1,
                    textColor: .white,
                    minDuration: 0.4,
                    frameWidth: 108
                )
                MarqueeText(
                    .constant(musicManager.artistName),
                    font: .caption2,
                    nsFont: .caption2,
                    textColor: accentColor.opacity(0.9),
                    minDuration: 0.4,
                    frameWidth: 108
                )
            }
            .frame(width: 108, alignment: .leading)
        }
        .padding(.trailing, 4)
    }

    private var albumArtCluster: some View {
        ZStack {
            if showPlaybackEffects {
                MusicPlayingAura(color: accentColor, isPlaying: true)
                    .frame(width: artSize + 16, height: artSize + 16)
                    .scaleEffect(ringPulse ? 1.06 : 0.94)
                    .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: ringPulse)

                AlbumArtRing(color: accentColor, lineWidth: 2)
                    .frame(width: artSize + 8, height: artSize + 8)
                    .scaleEffect(ringPulse ? 1.04 : 0.96)
                    .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: ringPulse)
            }

            Image(nsImage: musicManager.albumArt)
                .resizable()
                .aspectRatio(1, contentMode: .fill)
                .frame(width: artSize, height: artSize)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(.white.opacity(0.15), lineWidth: 0.5)
                }
                .matchedGeometryEffect(id: "albumArt", in: albumArtNamespace)
        }
        .frame(width: artSize + 10, height: artSize + 10)
    }

    private var rightCluster: some View {
        HStack(spacing: 10) {
            if useMusicVisualizer && musicManager.isPlaying {
                spectrumBars
            } else if musicManager.isPlaying {
                Image(systemName: "waveform.path")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [accentColor, .white.opacity(0.85)],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .symbolEffect(.variableColor.iterative.reversing, options: .repeating, value: musicManager.isPlaying)
            }

            Button {
                musicManager.togglePlay()
            } label: {
                Image(systemName: musicManager.isPlaying ? "pause.fill" : "play.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(accentColor.opacity(0.4))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 4)
    }

    private var spectrumBars: some View {
        Rectangle()
            .fill(coloredSpectrogram ? accentColor.gradient : Color.white.gradient)
            .frame(width: 28, height: 16)
            .matchedGeometryEffect(id: "spectrum", in: albumArtNamespace)
            .shadow(color: accentColor.opacity(0.5), radius: 4)
            .mask {
                AudioSpectrumView(isPlaying: .constant(musicManager.isPlaying))
                    .frame(width: 22, height: 16)
            }
    }

    private func startAnimations() {
        pulse = false
        sweep = false
        ringPulse = false

        guard musicManager.isPlaying else { return }

        withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
            pulse = true
        }
        withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
            sweep = true
        }
        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
            ringPulse = true
        }
    }
}
