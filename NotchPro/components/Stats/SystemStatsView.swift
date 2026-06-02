//
//  SystemStatsView.swift
//  NotchPro
//

import Defaults
import SwiftUI

struct SystemStatsView: View {
    @ObservedObject private var stats = SystemStatsManager.shared

    var body: some View {
        HStack(spacing: 12) {
            statItem(icon: "cpu", label: "CPU", value: "\(stats.cpuPercent)%", color: cpuColor)
            statItem(icon: "memorychip", label: "RAM", value: "\(stats.memoryPercent)%", color: memoryColor)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var cpuColor: Color {
        stats.cpuPercent > 70 ? .red : stats.cpuPercent > 40 ? .orange : .green
    }

    private var memoryColor: Color {
        stats.memoryPercent > 80 ? .red : stats.memoryPercent > 60 ? .orange : .green
    }

    private func statItem(icon: String, label: String, value: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption.weight(.semibold).monospacedDigit())
            }
        }
    }
}

struct SystemStatsGlance: View {
    @ObservedObject private var stats = SystemStatsManager.shared
    @Default(.showSystemStats) private var showSystemStats

    var body: some View {
        if showSystemStats {
            HStack(spacing: 6) {
                Text("CPU \(stats.cpuPercent)%")
                Text("·")
                Text("RAM \(stats.memoryPercent)%")
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.white.opacity(0.7))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.white.opacity(0.08))
            .clipShape(Capsule())
        }
    }
}
