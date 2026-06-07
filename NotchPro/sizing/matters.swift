//
//  sizeMatters.swift
//  notchpro
//
//  Created by Harsh Vardhan  Goswami  on 05/08/24.
//

import AppKit
import Defaults
import Foundation
import SwiftUI

let downloadSneakSize: CGSize = .init(width: 65, height: 1)
let batterySneakSize: CGSize = .init(width: 160, height: 1)

let shadowPadding: CGFloat = 24
/// Extra space above open content so top corner radius isn't clipped at the screen edge.
let windowTopInset: CGFloat = 8

/// Per-display layout derived from NSScreen auxiliary safe areas (physical notch).
struct NotchScreenLayout {
    let screen: NSScreen

    var frame: CGRect { screen.frame }

    var hasPhysicalNotch: Bool {
        screen.safeAreaInsets.top > 0
    }

    var leftInset: CGFloat {
        screen.auxiliaryTopLeftArea?.width ?? 0
    }

    var rightInset: CGFloat {
        screen.auxiliaryTopRightArea?.width ?? 0
    }

    var hasAuxiliaryInsets: Bool {
        leftInset > 0 && rightInset > 0
    }

    /// Width of the physical notch cutout in points.
    var physicalNotchWidth: CGFloat {
        if hasAuxiliaryInsets {
            return frame.width - leftInset - rightInset
        }
        if hasPhysicalNotch {
            return min(220, frame.width * 0.128)
        }
        return 185
    }

    /// Horizontal center of the physical notch on this display.
    var notchCenterX: CGFloat {
        // Apple Silicon MacBooks always center the camera notch on the built-in panel.
        if hasPhysicalNotch {
            return frame.midX
        }
        if hasAuxiliaryInsets {
            return frame.minX + leftInset + physicalNotchWidth / 2
        }
        return frame.midX
    }

    /// Small inset inside the open shell so top corner radius isn't clipped.
    var openContentTopInset: CGFloat {
        windowTopInset
    }

    var menuBarHeight: CGFloat {
        if hasPhysicalNotch {
            return max(screen.safeAreaInsets.top, frame.maxY - screen.visibleFrame.maxY)
        }
        return frame.maxY - screen.visibleFrame.maxY
    }

    @MainActor func windowSize(notchState: NotchState, isDetailExpanded: Bool) -> CGSize {
        let screenUUID = screen.displayUUID
        let open = getOpenNotchSize()
        let closed = getClosedNotchSize(screenUUID: screenUUID)

        if notchState == .open {
            var width = min(open.width, frame.width - 12)
            let topPadding = openContentTopInset
            let bottomShadow = hasPhysicalNotch ? min(shadowPadding, 12) : shadowPadding
            var height = open.height + topPadding + bottomShadow
            height = min(height, frame.height - 8)
            if isDetailExpanded {
                width = min(max(width, 720), frame.width - 12)
                height = min(max(height, 380), frame.height - 6)
            }
            return CGSize(width: width, height: height)
        }

        let width = min(getStatusRailMinWidth(screenUUID: screenUUID), frame.width - 12)
        let height = min(menuBarHeight + closed.height + 12, frame.height - 6)
        return CGSize(width: width, height: height)
    }

    func windowFrame(for size: CGSize) -> CGRect {
        let centeredX = notchCenterX - size.width / 2
        let x = min(max(centeredX, frame.minX + 4), frame.maxX - size.width - 4)
        let y = max(frame.minY, frame.maxY - size.height)
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }
}

/// Legacy constant; prefer `getOpenNotchSize()` for layout that depends on enabled widgets.
let openNotchSize: CGSize = .init(width: 640, height: 265)

@MainActor func getOpenNotchSize() -> CGSize {
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
    if PortfolioManager.shared.isDetailExpanded {
        width = 720
        height = max(height, 380)
    }

    return .init(width: width, height: height)
}

@MainActor func getWindowSize(
    screenUUID: String? = nil,
    notchState: NotchState = .open
) -> CGSize {
    let screen = screenUUID.flatMap { NSScreen.screen(withUUID: $0) }
        ?? NSScreen.preferredNotchScreen
    guard let screen else {
        let open = getOpenNotchSize()
        return CGSize(width: open.width, height: open.height + shadowPadding + windowTopInset)
    }
    return NotchScreenLayout(screen: screen).windowSize(
        notchState: notchState,
        isDetailExpanded: PortfolioManager.shared.isDetailExpanded
    )
}
let cornerRadiusInsets: (opened: (top: CGFloat, bottom: CGFloat), closed: (top: CGFloat, bottom: CGFloat)) = (opened: (top: 22, bottom: 28), closed: (top: 8, bottom: 16))

enum MusicPlayerImageSizes {
    static let cornerRadiusInset: (opened: CGFloat, closed: CGFloat) = (
        opened: NotchProDesign.albumArtCornerRadius,
        closed: 4.0
    )
    static let size = (
        opened: CGSize(
            width: NotchProDesign.albumArtSize,
            height: NotchProDesign.albumArtSize
        ),
        closed: CGSize(width: 20, height: 20)
    )
}

@MainActor func getScreenFrame(_ screenUUID: String? = nil) -> CGRect? {
    var selectedScreen = NSScreen.main

    if let uuid = screenUUID {
        selectedScreen = NSScreen.screen(withUUID: uuid)
    }
    
    if let screen = selectedScreen {
        return screen.frame
    }
    
    return nil
}

@MainActor func getStatusRailMinWidth(screenUUID: String? = nil) -> CGFloat {
    let closed = getClosedNotchSize(screenUUID: screenUUID)
    var width: CGFloat = 24

    if Defaults[.showWeatherGlance] { width += 118 }
    if Defaults[.showPortfolioGlance] { width += 80 }
    if Defaults[.showWorkoutGlance] { width += 72 }
    if Defaults[.showCalendar] { width += 58 }
    if Defaults[.showFocusTimer] { width += 50 }
    if Defaults[.showBatteryIndicator] { width += 54 }

    return min(max(closed.width, width), getOpenNotchSize().width)
}

@MainActor func getClosedNotchSize(screenUUID: String? = nil) -> CGSize {
    // Default notch size, to avoid using optionals
    var notchHeight: CGFloat = Defaults[.nonNotchHeight]
    var notchWidth: CGFloat = 185

    var selectedScreen = NSScreen.main

    if let uuid = screenUUID {
        selectedScreen = NSScreen.screen(withUUID: uuid)
    }

    if let screen = selectedScreen {
        let layout = NotchScreenLayout(screen: screen)
        notchWidth = layout.physicalNotchWidth + 4

        if layout.hasPhysicalNotch {
            notchHeight = Defaults[.notchHeight]
            if Defaults[.notchHeightMode] == .matchRealNotchSize {
                notchHeight = screen.safeAreaInsets.top
            } else if Defaults[.notchHeightMode] == .matchMenuBar {
                notchHeight = layout.menuBarHeight
            }
        } else {
            notchHeight = Defaults[.nonNotchHeight]
            if Defaults[.notchHeightMode] == .matchMenuBar {
                notchHeight = layout.menuBarHeight
            }
        }
    }

    return .init(width: notchWidth, height: notchHeight)
}
