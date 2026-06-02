//
//  FocusTimerView.swift
//  NotchPro
//

import Defaults
import SwiftUI

struct FocusTimerView: View {
    @ObservedObject private var timer = FocusTimerManager.shared
    @Default(.focusTimerDurationMinutes) private var defaultMinutes

    var body: some View {
        NotchProCard(accent: .orange, accentOpacity: 0.25) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "timer")
                        .foregroundStyle(.orange)
                    Text("Focus")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    if timer.isRunning {
                        Text(timer.displayTime)
                            .font(.system(.body, design: .monospaced).weight(.bold))
                            .foregroundStyle(.orange)
                    }
                }

                if timer.isRunning {
                    ProgressView(value: timer.progress)
                        .tint(.orange)
                    HStack {
                        if timer.isPaused {
                            Button("Resume") { timer.resume() }
                        } else {
                            Button("Pause") { timer.pause() }
                        }
                        Button("Stop", role: .destructive) { timer.stop() }
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                } else {
                    HStack {
                        Stepper("\(defaultMinutes) min", value: $defaultMinutes, in: 5...90, step: 5)
                            .font(.caption)
                        Button("Start") {
                            timer.start(minutes: defaultMinutes)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
            }
        }
    }
}

struct FocusTimerGlance: View {
    @ObservedObject private var timer = FocusTimerManager.shared

    var body: some View {
        if timer.isRunning {
            HStack(spacing: 4) {
                Image(systemName: "timer")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                Text(timer.displayTime)
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.orange)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.orange.opacity(0.15))
            .clipShape(Capsule())
        }
    }
}
