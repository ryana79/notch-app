//
//  NotchVisibilityCoordinator.swift
//  NotchPro
//

import Defaults
import Foundation

/// Pauses background timers when glance widgets are not visible (notch closed + no status rail).
@MainActor
enum NotchVisibilityCoordinator {
    static func update(notchOpen: Bool, statusRailVisible: Bool) {
        let widgetsVisible = notchOpen || statusRailVisible

        if Defaults[.showWeatherGlance], widgetsVisible {
            WeatherManager.shared.resumeRefreshTimer()
        } else {
            WeatherManager.shared.pauseRefreshTimer()
        }

        if Defaults[.showPortfolioGlance], widgetsVisible {
            PortfolioManager.shared.resumeRefreshTimer()
        } else {
            PortfolioManager.shared.pauseRefreshTimer()
        }

        ClipboardHistoryManager.shared.updatePolling(notchOpen: notchOpen)
    }
}
