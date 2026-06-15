//
//  NotchDisplayLayout.swift
//  NotchPro
//
//  Per-display island layout derived from NSScreen geometry — no hardcoded model sizes.
//

import AppKit
import Defaults
import Foundation

/// Visual treatment for the island on a given display.
enum IslandDisplayVariant: Equatable {
    /// Mac with camera housing — island wraps the cutout.
    case notchedCamera
    /// External monitor or Mac without housing — centered floating pill.
    case floatingPill
    /// Narrow or low-resolution display — compact chrome.
    case compact
}

/// Snapshot of layout inputs/outputs for debug overlay and logging.
struct NotchLayoutDiagnostics: Equatable {
    let screenUUID: String?
    let frame: CGRect
    let visibleFrame: CGRect
    let safeAreaTop: CGFloat
    let auxiliaryTopLeft: CGRect?
    let auxiliaryTopRight: CGRect?
    let variant: IslandDisplayVariant
    let housingWidth: CGFloat?
    let islandCenterX: CGFloat
    let islandFrame: CGRect
    let islandSize: CGSize
}

/// Per-display layout derived from NSScreen safe areas and auxiliary top regions.
struct NotchDisplayLayout {
    let screen: NSScreen

    var frame: CGRect { screen.frame }
    var visibleFrame: CGRect { screen.visibleFrame }

    var hasCameraHousing: Bool {
        screen.safeAreaInsets.top > 0
    }

    var leftMenuBarWidth: CGFloat {
        screen.auxiliaryTopLeftArea?.width ?? 0
    }

    var rightMenuBarWidth: CGFloat {
        screen.auxiliaryTopRightArea?.width ?? 0
    }

    var hasAuxiliaryTopAreas: Bool {
        leftMenuBarWidth > 0 && rightMenuBarWidth > 0
    }

    /// Width of the camera housing gap between left/right menu-bar regions.
    var cameraHousingWidth: CGFloat? {
        guard hasCameraHousing, hasAuxiliaryTopAreas else { return nil }
        let gap = frame.width - leftMenuBarWidth - rightMenuBarWidth
        return gap > 0 ? gap : nil
    }

    var variant: IslandDisplayVariant {
        if frame.width < 1100 || visibleFrame.width < 900 {
            return hasCameraHousing ? .compact : .compact
        }
        if hasCameraHousing, cameraHousingWidth != nil {
            return .notchedCamera
        }
        return .floatingPill
    }

    var menuBarHeight: CGFloat {
        let fromVisibleFrame = max(0, frame.maxY - visibleFrame.maxY)
        if hasCameraHousing {
            return max(screen.safeAreaInsets.top, fromVisibleFrame)
        }
        return fromVisibleFrame
    }

    /// Horizontal center for the island on this display.
    var islandCenterX: CGFloat {
        if let housing = cameraHousingWidth {
            return frame.minX + leftMenuBarWidth + housing / 2
        }
        return frame.midX
    }

    /// Maximum width that avoids overlapping menu-bar items on notched displays.
    var maxSafeIslandWidth: CGFloat {
        let edgeMargin: CGFloat = 8
        if hasAuxiliaryTopAreas {
            return max(120, frame.width - edgeMargin * 2)
        }
        let fraction = variant == .compact ? 0.72 : 0.88
        return max(160, min(frame.width - edgeMargin * 2, visibleFrame.width * fraction))
    }

    var openContentTopInset: CGFloat {
        switch variant {
        case .notchedCamera:
            return windowTopInset
        case .floatingPill:
            return max(windowTopInset, 10)
        case .compact:
            return windowTopInset
        }
    }

    @MainActor func closedIslandSize() -> CGSize {
        let height = resolvedClosedHeight()
        let width = resolvedClosedWidth(forHeight: height)
        return CGSize(width: width, height: height)
    }

    @MainActor func openIslandSize(isDetailExpanded: Bool) -> CGSize {
        let content = getOpenNotchContentSize(isDetailExpanded: isDetailExpanded)
        var width = min(content.width, maxSafeIslandWidth)
        let topPadding = openContentTopInset
        let bottomShadow = hasCameraHousing ? min(shadowPadding, 12) : shadowPadding
        var height = content.height + topPadding + bottomShadow
        height = min(height, frame.height - 8)
        if isDetailExpanded {
            width = min(max(width, min(720, maxSafeIslandWidth)), maxSafeIslandWidth)
            height = min(max(height, 380), frame.height - 6)
        }
        return CGSize(width: width, height: height)
    }

    @MainActor func windowSize(notchState: NotchState, isDetailExpanded: Bool) -> CGSize {
        if notchState == .open {
            return openIslandSize(isDetailExpanded: isDetailExpanded)
        }
        let closed = closedIslandSize()
        let railWidth = getStatusRailMinWidth(for: self)
        let width = min(max(closed.width, railWidth), maxSafeIslandWidth)
        let height = min(menuBarHeight + closed.height + 12, frame.height - 6)
        return CGSize(width: width, height: height)
    }

    func islandFrame(for size: CGSize) -> CGRect {
        let centeredX = islandCenterX - size.width / 2
        let minX = hasAuxiliaryTopAreas ? frame.minX + 4 : frame.minX + 8
        let maxX = frame.maxX - size.width - 4
        let x = min(max(centeredX, minX), maxX)
        let y = max(frame.minY, frame.maxY - size.height)
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }

    func windowFrame(for size: CGSize) -> NSRect {
        NSRectFromCGRect(islandFrame(for: size))
    }

    /// Backward-compatible aliases used by header/content views.
    var hasPhysicalNotch: Bool { hasCameraHousing }
    var physicalNotchWidth: CGFloat { cameraHousingWidth ?? 0 }
    var notchCenterX: CGFloat { islandCenterX }

    @MainActor func diagnostics(notchState: NotchState, isDetailExpanded: Bool) -> NotchLayoutDiagnostics {
        let size = windowSize(notchState: notchState, isDetailExpanded: isDetailExpanded)
        return NotchLayoutDiagnostics(
            screenUUID: screen.displayUUID,
            frame: frame,
            visibleFrame: visibleFrame,
            safeAreaTop: screen.safeAreaInsets.top,
            auxiliaryTopLeft: screen.auxiliaryTopLeftArea,
            auxiliaryTopRight: screen.auxiliaryTopRightArea,
            variant: variant,
            housingWidth: cameraHousingWidth,
            islandCenterX: islandCenterX,
            islandFrame: islandFrame(for: size),
            islandSize: size
        )
    }

    // MARK: - Private

    @MainActor private func resolvedClosedHeight() -> CGFloat {
        switch variant {
        case .notchedCamera:
            if Defaults[.notchHeightMode] == .matchRealNotchSize {
                return screen.safeAreaInsets.top
            }
            if Defaults[.notchHeightMode] == .matchMenuBar {
                return menuBarHeight
            }
            return Defaults[.notchHeight]
        case .floatingPill, .compact:
            if Defaults[.nonNotchHeightMode] == .matchMenuBar {
                return max(Defaults[.nonNotchHeight], menuBarHeight)
            }
            return Defaults[.nonNotchHeight]
        }
    }

    @MainActor private func resolvedClosedWidth(forHeight height: CGFloat) -> CGFloat {
        let shellPadding: CGFloat = 4
        switch variant {
        case .notchedCamera:
            if let housing = cameraHousingWidth {
                return housing + shellPadding
            }
            return min(maxSafeIslandWidth * 0.22, maxSafeIslandWidth)
        case .floatingPill:
            let railMin = getStatusRailMinWidth(for: self)
            let pillMin = max(120, min(maxSafeIslandWidth * 0.28, railMin))
            return min(pillMin, maxSafeIslandWidth)
        case .compact:
            return min(getStatusRailMinWidth(for: self), maxSafeIslandWidth)
        }
    }
}

// MARK: - Shared helpers

@MainActor func notchDisplayLayout(for screenUUID: String?, followMouse: Bool = false) -> NotchDisplayLayout? {
    guard let screen = activeIslandScreen(preferredUUID: screenUUID, followMouse: followMouse) else { return nil }
    return NotchDisplayLayout(screen: screen)
}

@MainActor func getOpenNotchContentSize(isDetailExpanded: Bool) -> CGSize {
    var height: CGFloat = 220
    var sideWidgets = 0

    if Defaults[.showWeatherGlance] { sideWidgets += 1 }
    if Defaults[.showPortfolioGlance] { sideWidgets += 1 }
    if Defaults[.showWorkoutGlance] { sideWidgets += 1; height = max(height, 340) }
    if Defaults[.showCalendar] { sideWidgets += 1; height = max(height, 320) }
    if Defaults[.showFocusTimer] { sideWidgets += 1 }
    if Defaults[.showSystemStats] { sideWidgets += 1 }

    if sideWidgets >= 4 {
        height = max(height, 330)
    } else if sideWidgets >= 3 {
        height = max(height, 305)
    } else if Defaults[.showFocusTimer] || Defaults[.showSystemStats] {
        height = max(height, 245)
    } else if Defaults[.showWeatherGlance] {
        height = max(height, 255)
    }

    var width: CGFloat = 680
    if isDetailExpanded {
        width = 720
        height = max(height, 380)
    }

    return CGSize(width: width, height: height)
}

@MainActor func statusRailContentMinWidth() -> CGFloat {
    var width: CGFloat = 24

    if Defaults[.showWeatherGlance] { width += 118 }
    if Defaults[.showPortfolioGlance] { width += 80 }
    if Defaults[.showWorkoutGlance] { width += 72 }
    if Defaults[.showCalendar] { width += 58 }
    if Defaults[.showFocusTimer] { width += 50 }
    if Defaults[.showBatteryIndicator] { width += 54 }

    return width
}

@MainActor func getStatusRailMinWidth(for layout: NotchDisplayLayout) -> CGFloat {
    min(max(statusRailContentMinWidth(), 120), layout.maxSafeIslandWidth)
}

@MainActor func getStatusRailMinWidth(screenUUID: String? = nil) -> CGFloat {
    guard let layout = notchDisplayLayout(for: screenUUID) else {
        return getOpenNotchContentSize(isDetailExpanded: false).width
    }
    return getStatusRailMinWidth(for: layout)
}

/// Resolve the active screen for the island window (never assumes NSScreen.main alone).
@MainActor func activeIslandScreen(preferredUUID: String?, followMouse: Bool) -> NSScreen? {
    if followMouse, let mouseScreen = NSScreen.screenWithMouse {
        return mouseScreen
    }
    if let uuid = preferredUUID, let screen = NSScreen.screen(withUUID: uuid) {
        return screen
    }
    return NSScreen.preferredNotchScreen ?? NSScreen.main
}
