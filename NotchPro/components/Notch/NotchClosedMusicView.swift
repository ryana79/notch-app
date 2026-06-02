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
        max(30, vm.effectiveClosedNotchHeight + 6)
    }

    private var artSize: CGFloat {
        max(24, min(barHeight - 6, 30))
    }

    private var titleWidth: CGFloat {
        min(88, max(56, totalWidth * 0.26))
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

            HStack(spacing: 8) {
                Group {
                    albumArtCluster

                    VStack(alignment: .leading, spacing: 1) {
                        MarqueeText(
                            .constant(musicManager.songTitle),
                            font: .caption.weight(.semibold),
                            nsFont: .caption1,
                            textColor: .white,
                            minDuration: 0.4,
                            frameWidth: titleWidth
                        )
                        MarqueeText(
                            .constant(musicManager.artistName),
                            font: .caption2,
                            nsFont: .caption2,
                            textColor: accentColor.opacity(0.9),
                            minDuration: 0.4,
                            frameWidth: titleWidth
                        )
                    }
                    .frame(width: titleWidth, alignment: .leading)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                        vm.open()
                    }
                }

                Spacer(minLength: 0)

                if useMusicVisualizer && musicManager.isPlaying {
                    spectrumBars
                } else if musicManager.isPlaying {
                    Image(systemName: "waveform.path")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(accentColor.opacity(0.9))
                        .symbolEffect(.variableColor.iterative.reversing, options: .repeating, value: musicManager.isPlaying)
                }

                playbackToggle
            }
            .padding(.horizontal, 14)
            .frame(width: totalWidth, height: barHeight)
            .clipped()

            progressBar
        }
        .frame(width: totalWidth, height: barHeight + 6, alignment: .center)
        .onAppear { startAnimations() }
        .onChange(of: musicManager.isPlaying) { _, _ in startAnimations() }
    }

    private var playbackToggle: some View {
        Button {
            musicManager.togglePlay()
        } label: {
            Group {
                if musicManager.isPlaying {
                    HStack(spacing: 2.5) {
                        Capsule().fill(.white.opacity(0.9)).frame(width: 2.5, height: 10)
                        Capsule().fill(.white.opacity(0.9)).frame(width: 2.5, height: 10)
                    }
                } else {
                    Image(systemName: "play.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
            .frame(width: 22, height: 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .zIndex(2)
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
                                colors: [.clear, accentColor.opacity(0.28), .white.opacity(0.1), .clear],
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
        .frame(width: totalWidth - 24, height: 2)
        .offset(y: 3)
    }

    private var albumArtCluster: some View {
        ZStack {
            if showPlaybackEffects {
                MusicPlayingAura(color: accentColor, isPlaying: true)
                    .frame(width: artSize + 16, height: artSize + 16)
                    .scaleEffect(ringPulse ? 1.06 : 0.94)

                AlbumArtRing(color: accentColor, lineWidth: 2)
                    .frame(width: artSize + 8, height: artSize + 8)
                    .scaleEffect(ringPulse ? 1.04 : 0.96)
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
        .frame(width: artSize + 12, height: artSize + 12)
    }

    private var spectrumBars: some View {
        Rectangle()
            .fill(coloredSpectrogram ? accentColor.gradient : Color.white.gradient)
            .frame(width: 22, height: 14)
            .matchedGeometryEffect(id: "spectrum", in: albumArtNamespace)
            .mask {
                AudioSpectrumView(
                    isPlaying: .constant(musicManager.isPlaying),
                    isVisible: useMusicVisualizer && musicManager.isPlaying
                )
                    .frame(width: 18, height: 14)
            }
    }

    private func startAnimations() {
        pulse = false
        sweep = false
        ringPulse = false
        guard musicManager.isPlaying else { return }
        withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { pulse = true }
        withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) { sweep = true }
        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { ringPulse = true }
    }
}
