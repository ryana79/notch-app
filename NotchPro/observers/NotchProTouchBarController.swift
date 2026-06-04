//
//  NotchProTouchBarController.swift
//  notchpro
//

import AppKit
import Defaults
import SwiftUI

/// Touch Bar controls for MacBook Pro models with the OLED strip (2016–2020).
/// macOS tints the strip from the frontmost app's controls; vibrant items read best here.
@MainActor
final class NotchProTouchBarController: NSObject, NSTouchBarDelegate {
    static let shared = NotchProTouchBarController()

    private static let toggleNotchID = NSTouchBarItem.Identifier("com.ryana79.notchpro.touchbar.toggleNotch")
    private static let playPauseID = NSTouchBarItem.Identifier("com.ryana79.notchpro.touchbar.playPause")
    private static let previousID = NSTouchBarItem.Identifier("com.ryana79.notchpro.touchbar.previous")
    private static let nextID = NSTouchBarItem.Identifier("com.ryana79.notchpro.touchbar.next")
    private static let screenshotID = NSTouchBarItem.Identifier("com.ryana79.notchpro.touchbar.screenshot")
    private static let shelfID = NSTouchBarItem.Identifier("com.ryana79.notchpro.touchbar.shelf")
    private static let accentGroupID = NSTouchBarItem.Identifier("com.ryana79.notchpro.touchbar.accentGroup")

    private override init() {
        super.init()
    }

    static func configureApp() {
        NSApp.isAutomaticCustomizeTouchBarMenuItemEnabled = true
    }

    func makeTouchBar() -> NSTouchBar {
        let bar = NSTouchBar()
        bar.delegate = self
        bar.customizationIdentifier = .init("com.ryana79.notchpro.touchbar")
        bar.defaultItemIdentifiers = [
            Self.toggleNotchID,
            Self.previousID,
            Self.playPauseID,
            Self.nextID,
            .flexibleSpace,
            Self.screenshotID,
            Self.shelfID,
            Self.accentGroupID,
        ]
        bar.customizationAllowedItemIdentifiers = [
            Self.toggleNotchID,
            Self.previousID,
            Self.playPauseID,
            Self.nextID,
            Self.screenshotID,
            Self.shelfID,
            Self.accentGroupID,
            .flexibleSpace,
            .otherItemsProxy,
        ]
        return bar
    }

    func touchBar(
        _ touchBar: NSTouchBar,
        makeItemForIdentifier identifier: NSTouchBarItem.Identifier
    ) -> NSTouchBarItem? {
        guard Defaults[.enableTouchBar] else { return nil }

        switch identifier {
        case Self.toggleNotchID:
            return buttonItem(
                identifier: identifier,
                title: "Notch",
                symbol: "platter.top.filled.with.iphone.and.arrow.forward.inward",
                tint: .systemTeal
            ) { [weak self] in
                self?.toggleNotch()
            }
        case Self.playPauseID:
            return buttonItem(
                identifier: identifier,
                title: "Play",
                symbol: MusicManager.shared.isPlaying ? "pause.fill" : "play.fill",
                tint: .systemPink
            ) {
                MusicManager.shared.togglePlay()
            }
        case Self.previousID:
            return buttonItem(identifier: identifier, title: "Prev", symbol: "backward.fill", tint: .systemIndigo) {
                MusicManager.shared.previousTrack()
            }
        case Self.nextID:
            return buttonItem(identifier: identifier, title: "Next", symbol: "forward.fill", tint: .systemIndigo) {
                MusicManager.shared.nextTrack()
            }
        case Self.screenshotID:
            return buttonItem(identifier: identifier, title: "Shot", symbol: "camera.viewfinder", tint: .systemOrange) {
                ScreenshotCaptureManager.shared.captureInteractive()
            }
        case Self.shelfID:
            return buttonItem(identifier: identifier, title: "Shelf", symbol: "tray.and.arrow.down.fill", tint: .systemCyan) {
                Task { @MainActor in
                    NotchProCoordinator.shared.currentView = .shelf
                    if NotchProCoordinator.shared.alwaysShowTabs == false {
                        NotchProCoordinator.shared.alwaysShowTabs = true
                    }
                }
            }
        case Self.accentGroupID:
            return accentPickerItem(identifier: identifier)
        default:
            return nil
        }
    }

    private func buttonItem(
        identifier: NSTouchBarItem.Identifier,
        title: String,
        symbol: String,
        tint: NSColor,
        action: @escaping () -> Void
    ) -> NSCustomTouchBarItem {
        let item = NSCustomTouchBarItem(identifier: identifier)
        item.customizationLabel = title

        let button = NSButton(
            image: NSImage(systemSymbolName: symbol, accessibilityDescription: title) ?? NSImage(),
            target: nil,
            action: nil
        )
        button.bezelColor = tint.withAlphaComponent(0.35)
        button.contentTintColor = .white
        button.imagePosition = .imageOnly
        button.isBordered = true
        button.bezelStyle = .rounded
        button.toolTip = title
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true

        let handler = TouchBarActionTarget(action: action)
        objc_setAssociatedObject(button, &TouchBarActionTarget.associationKey, handler, .OBJC_ASSOCIATION_RETAIN)
        button.target = handler
        button.action = #selector(TouchBarActionTarget.invoke)

        item.view = button
        return item
    }

    private func accentPickerItem(identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem {
        let picker = NSColorPickerTouchBarItem(identifier: identifier)
        picker.customizationLabel = "Accent"
        picker.color = NSColor(Color.effectiveAccent)
        picker.showsAlpha = false
        picker.target = self
        picker.action = #selector(accentColorPicked(_:))
        return picker
    }

    @objc private func accentColorPicked(_ sender: NSColorPickerTouchBarItem) {
        let nsColor = sender.color.usingColorSpace(.sRGB) ?? sender.color
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: nsColor, requiringSecureCoding: false) {
            Defaults[.customAccentColorData] = data
            Defaults[.useCustomAccentColor] = true
        }
        NotificationCenter.default.post(name: NSNotification.Name("AccentColorChanged"), object: nil)
    }

    private func toggleNotch() {
        if let appDelegate = NSApp.delegate as? AppDelegate {
            if appDelegate.vm.notchState == .closed {
                appDelegate.vm.open()
            } else {
                appDelegate.vm.close()
            }
        }
    }
}

private final class TouchBarActionTarget: NSObject {
    static var associationKey: UInt8 = 0
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
    }

    @objc func invoke() {
        action()
    }
}
