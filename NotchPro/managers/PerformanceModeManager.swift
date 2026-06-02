//
//  PerformanceModeManager.swift
//  notchpro
//

import Defaults
import Foundation

enum PerformanceModeManager {
    static func apply(preset: LayoutPreset) {
        switch preset {
        case .balanced:
            Defaults[.performanceMode] = false
            Defaults[.useMusicVisualizer] = true
            Defaults[.playerColorTinting] = true
            Defaults[.lightingEffect] = false
            Defaults[.showNotHumanFace] = false
            Defaults[.showCalendar] = true
            Defaults[.showWeatherGlance] = true
            Defaults[.showMirror] = false
            Defaults[.expandedDragDetection] = true
            Defaults[.enableShadow] = true
            Defaults[.glassmorphismEnabled] = true
            Defaults[.accentGlowEnabled] = true
            Defaults[.showFocusTimer] = false
            Defaults[.showSystemStats] = false
            Defaults[.sliderColor] = .albumArt
        case .minimal:
            Defaults[.performanceMode] = true
            Defaults[.useMusicVisualizer] = false
            Defaults[.playerColorTinting] = false
            Defaults[.lightingEffect] = false
            Defaults[.showNotHumanFace] = false
            Defaults[.showCalendar] = false
            Defaults[.showMirror] = false
            Defaults[.expandedDragDetection] = false
            Defaults[.enableShadow] = false
            Defaults[.glassmorphismEnabled] = false
            Defaults[.showFocusTimer] = false
            Defaults[.showSystemStats] = false
            Defaults[.showWeatherGlance] = false
            Defaults[.accentGlowEnabled] = false
        case .media:
            Defaults[.performanceMode] = false
            Defaults[.useMusicVisualizer] = true
            Defaults[.playerColorTinting] = true
            Defaults[.lightingEffect] = true
            Defaults[.showCalendar] = false
            Defaults[.showMirror] = false
            Defaults[.expandedDragDetection] = true
            Defaults[.enableShadow] = true
            Defaults[.glassmorphismEnabled] = true
        case .productivity:
            Defaults[.performanceMode] = true
            Defaults[.useMusicVisualizer] = false
            Defaults[.playerColorTinting] = false
            Defaults[.lightingEffect] = false
            Defaults[.showNotHumanFace] = false
            Defaults[.showCalendar] = true
            Defaults[.showMirror] = false
            Defaults[.expandedDragDetection] = false
            Defaults[.hudReplacement] = true
            Defaults[.enableShadow] = false
            Defaults[.glassmorphismEnabled] = true
            Defaults[.showWeatherGlance] = true
        case .utility:
            Defaults[.performanceMode] = true
            Defaults[.useMusicVisualizer] = false
            Defaults[.playerColorTinting] = false
            Defaults[.lightingEffect] = false
            Defaults[.showNotHumanFace] = false
            Defaults[.showCalendar] = false
            Defaults[.notchProShelf] = true
            Defaults[.hudReplacement] = true
            Defaults[.showBatteryIndicator] = true
            Defaults[.expandedDragDetection] = true
            Defaults[.enableShadow] = false
            Defaults[.glassmorphismEnabled] = false
        case .custom:
            break
        }
    }

    static func applyPerformanceMode(_ enabled: Bool) {
        if enabled {
            Defaults[.useMusicVisualizer] = false
            Defaults[.lightingEffect] = false
            Defaults[.playerColorTinting] = false
            Defaults[.showNotHumanFace] = false
            Defaults[.enableShadow] = false
            if Defaults[.layoutPreset] != .custom {
                Defaults[.layoutPreset] = .custom
            }
        }
    }
}
