//
//  NotchStatusRail.swift
//  NotchPro
//

import Defaults
import SwiftUI

struct NotchStatusRail: View {
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared

    var body: some View {
        HStack(spacing: NotchProDesign.compactSpacing) {
            NotchWeatherPill()
            NotchCalendarGlance()
            FocusTimerGlance()
            if Defaults[.showBatteryIndicator] {
                batteryPill
            }
        }
    }

    private var batteryPill: some View {
        NotchProPill(tint: batteryTint) {
            HStack(spacing: 4) {
                Image(systemName: batteryIcon)
                    .font(.caption2)
                    .foregroundStyle(batteryTint)
                if Defaults[.showBatteryPercentage] {
                    Text("\(batteryModel.levelBattery)%")
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
        }
    }

    private var batteryTint: Color {
        if batteryModel.isCharging { return .green }
        if batteryModel.levelBattery <= 20 { return .orange }
        return .white
    }

    private var batteryIcon: String {
        if batteryModel.isCharging { return "bolt.fill" }
        if batteryModel.levelBattery <= 20 { return "battery.25" }
        return "battery.100"
    }
}
