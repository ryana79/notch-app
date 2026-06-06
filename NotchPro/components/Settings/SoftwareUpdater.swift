//
//  SoftwareUpdater.swift
//  notchpro
//

import Sparkle
import SwiftUI

@MainActor
final class AppUpdateManager: NSObject, ObservableObject {
    static let shared = AppUpdateManager()

    @Published private(set) var updateAvailable = false
    @Published private(set) var latestVersion: String?
    @Published private(set) var isChecking = false
    @Published private(set) var lastChecked: Date?

    private weak var updater: SPUUpdater?
    private let configuredKey = "didConfigureSparkleDefaults"

    private override init() {
        super.init()
    }

    func bind(updater: SPUUpdater) {
        self.updater = updater
        if !UserDefaults.standard.bool(forKey: configuredKey) {
            updater.automaticallyChecksForUpdates = true
            updater.automaticallyDownloadsUpdates = true
            UserDefaults.standard.set(true, forKey: configuredKey)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.checkInBackground()
        }
    }

    func checkInBackground() {
        updater?.checkForUpdatesInBackground()
    }

    func checkForUpdates() {
        updater?.checkForUpdates()
    }

    func setChecking(_ value: Bool) {
        isChecking = value
    }

    func markNoUpdateFound() {
        updateAvailable = false
        latestVersion = nil
        isChecking = false
        lastChecked = Date()
    }

    func markUpdateFound(version: String) {
        updateAvailable = true
        latestVersion = version
        isChecking = false
        lastChecked = Date()
    }
}

extension AppUpdateManager: SPUUpdaterDelegate {
    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let version = item.displayVersionString
        Task { @MainActor in
            AppUpdateManager.shared.markUpdateFound(version: version)
        }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        Task { @MainActor in
            AppUpdateManager.shared.markNoUpdateFound()
        }
    }

    nonisolated func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        Task { @MainActor in
            AppUpdateManager.shared.isChecking = false
            AppUpdateManager.shared.lastChecked = Date()
        }
    }
}

final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false

    init(updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }
}

struct SettingsUpdateBanner: View {
    @ObservedObject private var updates = AppUpdateManager.shared
    let updater: SPUUpdater

    var body: some View {
        if updates.updateAvailable, let latest = updates.latestVersion {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Update available")
                        .font(.headline)
                    Text("NotchPro \(latest) is ready. You're on \(Bundle.main.releaseVersionNumber ?? "unknown").")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button("Update Now") {
                    updater.checkForUpdates()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color.orange.opacity(0.12))
        }
    }
}

struct CheckForUpdatesView: View {
    @ObservedObject private var checkForUpdatesViewModel: CheckForUpdatesViewModel
    @ObservedObject private var updates = AppUpdateManager.shared
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        self.checkForUpdatesViewModel = CheckForUpdatesViewModel(updater: updater)
    }

    var body: some View {
        HStack(spacing: 10) {
            Button("Check for Updates…") {
                updates.setChecking(true)
                updater.checkForUpdates()
            }
            .disabled(!checkForUpdatesViewModel.canCheckForUpdates || updates.isChecking)

            if updates.isChecking {
                ProgressView().controlSize(.small)
            } else if let lastChecked = updates.lastChecked {
                Text("Last checked \(lastChecked, style: .relative) ago")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

struct UpdaterSettingsView: View {
    private let updater: SPUUpdater

    @State private var automaticallyChecksForUpdates: Bool
    @State private var automaticallyDownloadsUpdates: Bool

    init(updater: SPUUpdater) {
        self.updater = updater
        self.automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
        self.automaticallyDownloadsUpdates = updater.automaticallyDownloadsUpdates
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Automatically check for updates", isOn: $automaticallyChecksForUpdates)
                .onChange(of: automaticallyChecksForUpdates) { _, newValue in
                    updater.automaticallyChecksForUpdates = newValue
                }

            Toggle("Automatically download updates", isOn: $automaticallyDownloadsUpdates)
                .disabled(!automaticallyChecksForUpdates)
                .onChange(of: automaticallyDownloadsUpdates) { _, newValue in
                    updater.automaticallyDownloadsUpdates = newValue
                }
        }
    }
}
