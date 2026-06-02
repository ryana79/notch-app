//
//  PanGesture.swift
//  notchpro
//
//  Created by Richard Kunkli on 21/08/2024.
//

import AppKit
import SwiftUI

enum PanDirection {
    case left, right, up, down

    var isHorizontal: Bool { self == .left || self == .right }
    var sign: CGFloat { (self == .right || self == .down) ? 1 : -1 }

    func signed(from translation: CGSize) -> CGFloat { (isHorizontal ? translation.width : translation.height) * sign }
    func signed(deltaX: CGFloat, deltaY: CGFloat) -> CGFloat { (isHorizontal ? deltaX : deltaY) * sign }
}

extension View {
    func panGesture(
        direction: PanDirection,
        threshold: CGFloat = 4,
        onScrollInteraction: ((Bool) -> Void)? = nil,
        action: @escaping (CGFloat, NSEvent.Phase) -> Void
    ) -> some View {
        self
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let s = direction.signed(from: value.translation)
                        guard s > 0, s.magnitude >= threshold else { return }
                        action(s.magnitude, .changed)
                    }
                    .onEnded { _ in action(0, .ended) }
            )
            .background(
                ScrollMonitor(
                    direction: direction,
                    threshold: threshold,
                    onScrollInteraction: onScrollInteraction,
                    action: action
                )
            )
    }
}

private struct ScrollMonitor: NSViewRepresentable {
    let direction: PanDirection
    let threshold: CGFloat
    let onScrollInteraction: ((Bool) -> Void)?
    let action: (CGFloat, NSEvent.Phase) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.hostView = view
        context.coordinator.installMonitor(on: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.hostView = nsView
        context.coordinator.onScrollInteraction = onScrollInteraction
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(direction: direction, threshold: threshold, onScrollInteraction: onScrollInteraction, action: action)
    }

    @MainActor final class Coordinator: NSObject {
        private let direction: PanDirection
        private let threshold: CGFloat
        var onScrollInteraction: ((Bool) -> Void)?
        private let action: (CGFloat, NSEvent.Phase) -> Void
        weak var hostView: NSView?
        private var monitor: Any?
        private var accumulated: CGFloat = 0
        private var active = false
        private var endTask: Task<Void, Never>?
        private let noiseThreshold: CGFloat = 0.2

        init(
            direction: PanDirection,
            threshold: CGFloat,
            onScrollInteraction: ((Bool) -> Void)?,
            action: @escaping (CGFloat, NSEvent.Phase) -> Void
        ) {
            self.direction = direction
            self.threshold = threshold
            self.onScrollInteraction = onScrollInteraction
            self.action = action
        }

        private func scheduleEndTimeout() {
            endTask?.cancel()
            endTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                if active {
                    action(accumulated.magnitude, .ended)
                } else {
                    action(0, .ended)
                }
                active = false
                accumulated = 0
                onScrollInteraction?(false)
            }
        }

        func installMonitor(on view: NSView) {
            removeMonitor()
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { [weak self, weak view] event in
                guard let self = self, event.window === view?.window else { return event }
                self.handleScroll(event)
                return event
            }
        }

        func removeMonitor() {
            if let monitor = monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            accumulated = 0
            active = false
            endTask?.cancel()
            endTask = nil
            onScrollInteraction?(false)
        }

        private func handleScroll(_ event: NSEvent) {
            if event.phase == .ended || event.momentumPhase == .ended {
                if active {
                    action(accumulated.magnitude, .ended)
                } else {
                    action(0, .ended)
                }
                active = false
                accumulated = 0
                onScrollInteraction?(false)
                return
            }

            let absDX = abs(event.scrollingDeltaX)
            let absDY = abs(event.scrollingDeltaY)
            let axisDominanceFactor: CGFloat = 1.5
            let isAxisDominant: Bool = direction.isHorizontal
                ? (absDX >= axisDominanceFactor * absDY)
                : (absDY >= axisDominanceFactor * absDX)
            guard isAxisDominant else { return }

            if NotchScrollBoundary.shouldSuppressNotchGesture(
                event: event,
                hostView: hostView,
                direction: direction
            ) {
                onScrollInteraction?(true)
                accumulated = 0
                active = false
                scheduleEndTimeout()
                return
            }

            let raw = direction.signed(deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY)
            let scale: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 8
            let s = raw * scale
            guard s.magnitude > noiseThreshold else { return }
            accumulated = s > 0 ? accumulated + s : 0

            if !active && accumulated >= threshold {
                active = true
                onScrollInteraction?(false)
                action(accumulated.magnitude, .began)
            } else if active {
                action(accumulated.magnitude, .changed)
            }
            scheduleEndTimeout()
        }
    }
}
