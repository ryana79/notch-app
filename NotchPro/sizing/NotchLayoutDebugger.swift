//
//  NotchLayoutDebugger.swift
//  NotchPro
//

import AppKit
import Defaults
import Foundation
import SwiftUI

extension Defaults.Keys {
    static let showNotchLayoutDebug = Key<Bool>("showNotchLayoutDebug", default: false)
}

enum NotchLayoutDebugger {
    @MainActor static func log(_ diagnostics: NotchLayoutDiagnostics) {
        #if DEBUG
        NSLog(
            """
            [NotchLayout] screen=\(diagnostics.screenUUID ?? "?") \
            variant=\(diagnostics.variant) \
            frame=\(fmt(diagnostics.frame)) \
            visible=\(fmt(diagnostics.visibleFrame)) \
            safeTop=\(diagnostics.safeAreaTop) \
            auxL=\(fmt(diagnostics.auxiliaryTopLeft)) \
            auxR=\(fmt(diagnostics.auxiliaryTopRight)) \
            housingW=\(diagnostics.housingWidth.map { String(format: "%.1f", $0) } ?? "nil") \
            centerX=\(String(format: "%.1f", diagnostics.islandCenterX)) \
            island=\(fmt(diagnostics.islandFrame))
            """
        )
        #else
        if Defaults[.showNotchLayoutDebug] {
            NSLog("[NotchLayout] \(diagnostics.screenUUID ?? "?") \(diagnostics.variant) island=\(fmt(diagnostics.islandFrame))")
        }
        #endif
    }

    private static func fmt(_ rect: CGRect?) -> String {
        guard let rect else { return "nil" }
        return String(format: "(%.0f,%.0f,%.0f×%.0f)", rect.origin.x, rect.origin.y, rect.width, rect.height)
    }

    private static func fmt(_ rect: CGRect) -> String {
        fmt(Optional(rect))
    }
}

struct NotchLayoutDebugOverlay: View {
    let diagnostics: NotchLayoutDiagnostics

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Layout debug").font(.caption2.weight(.bold))
            line("variant", "\(diagnostics.variant)")
            line("safeTop", String(format: "%.0f", diagnostics.safeAreaTop))
            line("housing", diagnostics.housingWidth.map { String(format: "%.0f", $0) } ?? "—")
            line("island", frameString(diagnostics.islandFrame))
            line("centerX", String(format: "%.0f", diagnostics.islandCenterX))
        }
        .font(.system(size: 9, design: .monospaced))
        .foregroundStyle(.green)
        .padding(6)
        .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 6))
        .allowsHitTesting(false)
    }

    private func line(_ key: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(key).foregroundStyle(.white.opacity(0.55))
            Text(value)
        }
    }

    private func frameString(_ rect: CGRect) -> String {
        String(format: "%.0f,%.0f %.0f×%.0f", rect.origin.x, rect.origin.y, rect.width, rect.height)
    }
}
