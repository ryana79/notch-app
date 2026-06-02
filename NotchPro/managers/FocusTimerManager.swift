//
//  FocusTimerManager.swift
//  NotchPro
//

import AppKit
import Combine
import Defaults
import Foundation

@MainActor
final class FocusTimerManager: ObservableObject {
    static let shared = FocusTimerManager()

    @Published private(set) var remainingSeconds: Int = 0
    @Published private(set) var isRunning = false
    @Published private(set) var isPaused = false

    private var timer: Timer?
    private var endDate: Date?

    var displayTime: String {
        let m = remainingSeconds / 60
        let s = remainingSeconds % 60
        return String(format: "%02d:%02d", m, s)
    }

    var progress: Double {
        let total = Defaults[.focusTimerDurationMinutes] * 60
        guard total > 0 else { return 0 }
        return 1.0 - Double(remainingSeconds) / Double(total)
    }

    func start(minutes: Int? = nil) {
        let duration = minutes ?? Defaults[.focusTimerDurationMinutes]
        remainingSeconds = duration * 60
        endDate = Date().addingTimeInterval(TimeInterval(remainingSeconds))
        isRunning = true
        isPaused = false
        startTicking()
    }

    func pause() {
        guard isRunning, !isPaused else { return }
        isPaused = true
        timer?.invalidate()
        timer = nil
    }

    func resume() {
        guard isRunning, isPaused else { return }
        isPaused = false
        endDate = Date().addingTimeInterval(TimeInterval(remainingSeconds))
        startTicking()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        isPaused = false
        remainingSeconds = 0
        endDate = nil
    }

    private func startTicking() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    private func tick() {
        guard let endDate else { return }
        remainingSeconds = max(0, Int(endDate.timeIntervalSinceNow.rounded()))
        if remainingSeconds <= 0 {
            stop()
            NSSound.beep()
        }
    }
}
