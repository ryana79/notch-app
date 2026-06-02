//
//  ApplicationRelauncher.swift
//  NotchPro
//

import AppKit

enum ApplicationRelauncher {
    static func restart() {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }

        let workspace = NSWorkspace.shared

        guard let appURL = workspace.urlForApplication(withBundleIdentifier: bundleIdentifier)
        else { return }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true

        workspace.openApplication(at: appURL, configuration: configuration, completionHandler: nil)

        quitCompletely()
    }

    /// Terminates NotchPro and kills helper processes (mediaremote adapter, etc.).
    static func quitCompletely() {
        killHelperProcesses()
        NSApplication.shared.terminate(nil)
    }

    static func killHelperProcesses() {
        let bundlePath = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = [
            "-c",
            """
            pkill -f "mediaremote-adapter.pl.*\(bundlePath)" 2>/dev/null || true
            pkill -f "mediaremote-adapter.pl.*NotchPro.app" 2>/dev/null || true
            """,
        ]
        try? task.run()
        task.waitUntilExit()
    }
}
