//
//  matters.swift
//  notchpro
//

import AppKit
import Defaults
import Foundation
import SwiftUI

let downloadSneakSize: CGSize = .init(width: 65, height: 1)
let batterySneakSize: CGSize = .init(width: 160, height: 1)

let shadowPadding: CGFloat = 24
let windowTopInset: CGFloat = 8

typealias NotchScreenLayout = NotchDisplayLayout

let openNotchSize: CGSize = .init(width: 640, height: 265)

@MainActor func getOpenNotchSize() -> CGSize {
    getOpenNotchContentSize(isDetailExpanded: PortfolioManager.shared.isDetailExpanded)
}

@MainActor func getWindowSize(
    screenUUID: String? = nil,
    notchState: NotchState = .open
) -> CGSize {
    guard let layout = notchDisplayLayout(for: screenUUID) else {
        let open = getOpenNotchSize()
        return CGSize(width: open.width, height: open.height + shadowPadding + windowTopInset)
    }
    return layout.windowSize(
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
    notchDisplayLayout(for: screenUUID)?.frame
}

@MainActor func getClosedNotchSize(screenUUID: String? = nil) -> CGSize {
    notchDisplayLayout(for: screenUUID)?.closedIslandSize()
        ?? CGSize(width: 160, height: Defaults[.nonNotchHeight])
}

@MainActor func layoutDiagnostics(
    screenUUID: String?,
    notchState: NotchState,
    isDetailExpanded: Bool
) -> NotchLayoutDiagnostics? {
    guard let layout = notchDisplayLayout(for: screenUUID) else { return nil }
    return layout.diagnostics(notchState: notchState, isDetailExpanded: isDetailExpanded)
}
