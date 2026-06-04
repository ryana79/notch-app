//
//  sizeMatters.swift
//  notchpro
//
//  Created by Harsh Vardhan  Goswami  on 05/08/24.
//

import Defaults
import Foundation
import SwiftUI

let downloadSneakSize: CGSize = .init(width: 65, height: 1)
let batterySneakSize: CGSize = .init(width: 160, height: 1)

let shadowPadding: CGFloat = 24
/// Extra space above open content so top corner radius isn't clipped at the screen edge.
let windowTopInset: CGFloat = 8

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

    return .init(width: 680, height: height)
}

@MainActor func getWindowSize() -> CGSize {
    let open = getOpenNotchSize()
    return .init(width: open.width, height: open.height + shadowPadding + windowTopInset)
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

@MainActor func getClosedNotchSize(screenUUID: String? = nil) -> CGSize {
    // Default notch size, to avoid using optionals
    var notchHeight: CGFloat = Defaults[.nonNotchHeight]
    var notchWidth: CGFloat = 185

    var selectedScreen = NSScreen.main

    if let uuid = screenUUID {
        selectedScreen = NSScreen.screen(withUUID: uuid)
    }

    // Check if the screen is available
    if let screen = selectedScreen {
        // Calculate and set the exact width of the notch
        if let topLeftNotchpadding: CGFloat = screen.auxiliaryTopLeftArea?.width,
           let topRightNotchpadding: CGFloat = screen.auxiliaryTopRightArea?.width
        {
            notchWidth = screen.frame.width - topLeftNotchpadding - topRightNotchpadding + 4
        }

        // Check if the Mac has a notch
        if screen.safeAreaInsets.top > 0 {
            // This is a display WITH a notch - use notch height settings
            notchHeight = Defaults[.notchHeight]
            if Defaults[.notchHeightMode] == .matchRealNotchSize {
                notchHeight = screen.safeAreaInsets.top
            } else if Defaults[.notchHeightMode] == .matchMenuBar {
                notchHeight = screen.frame.maxY - screen.visibleFrame.maxY
            }
        } else {
            // This is a display WITHOUT a notch - use non-notch height settings
            notchHeight = Defaults[.nonNotchHeight]
            if Defaults[.nonNotchHeightMode] == .matchMenuBar {
                notchHeight = screen.frame.maxY - screen.visibleFrame.maxY
            }
        }
    }

    return .init(width: notchWidth, height: notchHeight)
}
