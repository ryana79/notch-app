//
//  NotchScrollExempt.swift
//  NotchPro
//

import AppKit
import SwiftUI

@MainActor
enum NotchScrollBoundary {
    private static let edgeEpsilon: CGFloat = 2

    static func enclosingScrollView(at windowPoint: NSPoint, in window: NSWindow?) -> NSScrollView? {
        guard let contentView = window?.contentView else { return nil }
        let point = contentView.convert(windowPoint, from: nil)
        var view = contentView.hitTest(point)
        while let current = view {
            if let scrollView = current as? NSScrollView {
                return scrollView
            }
            if let scrollView = current.enclosingScrollView {
                return scrollView
            }
            view = current.superview
        }
        return nil
    }

    /// Returns true when the scroll view can still consume this wheel delta (gesture should not close/open the notch).
    static func canScrollViewAbsorb(_ scrollView: NSScrollView, deltaX: CGFloat, deltaY: CGFloat) -> Bool {
        guard let documentView = scrollView.documentView else { return false }

        let absDX = abs(deltaX)
        let absDY = abs(deltaY)
        let isPrimarilyVertical = absDY >= absDX

        if isPrimarilyVertical {
            return canAbsorbVerticalScroll(scrollView, documentView: documentView, deltaY: deltaY)
        }

        return canAbsorbHorizontalScroll(scrollView, documentView: documentView, deltaX: deltaX)
    }

    private static func canAbsorbVerticalScroll(
        _ scrollView: NSScrollView,
        documentView: NSView,
        deltaY: CGFloat
    ) -> Bool {
        let visible = scrollView.documentVisibleRect
        let docHeight = documentView.frame.height
        guard docHeight > visible.height + edgeEpsilon else { return false }

        if deltaY > 0 {
            return visible.origin.y > edgeEpsilon
        }
        if deltaY < 0 {
            return visible.maxY < docHeight - edgeEpsilon
        }
        return false
    }

    private static func canAbsorbHorizontalScroll(
        _ scrollView: NSScrollView,
        documentView: NSView,
        deltaX: CGFloat
    ) -> Bool {
        let visible = scrollView.documentVisibleRect
        let docWidth = documentView.frame.width
        guard docWidth > visible.width + edgeEpsilon else { return false }

        if deltaX > 0 {
            return visible.origin.x > edgeEpsilon
        }
        if deltaX < 0 {
            return visible.maxX < docWidth - edgeEpsilon
        }
        return false
    }

    /// Suppress notch pan gestures when scrolling inside a scroll view that can still move.
    static func shouldSuppressNotchGesture(
        event: NSEvent,
        hostView: NSView?,
        direction: PanDirection
    ) -> Bool {
        guard let hostView, let window = hostView.window else { return false }
        guard let scrollView = enclosingScrollView(at: event.locationInWindow, in: window) else {
            return false
        }

        if direction.isHorizontal {
            return canScrollViewAbsorb(scrollView, deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY)
                && abs(event.scrollingDeltaX) >= abs(event.scrollingDeltaY)
        }

        return canScrollViewAbsorb(scrollView, deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY)
            && abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX)
    }
}

extension View {
    /// Marks this view hierarchy as a scroll region (used for hover-based gesture suppression).
    func notchScrollRegion(onHoverChange: @escaping (Bool) -> Void) -> some View {
        onHover { hovering in
            onHoverChange(hovering)
        }
    }
}

private final class ScrollExemptAnchorView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        _ = findEnclosingScrollView(from: self)
    }

    private func findEnclosingScrollView(from view: NSView) -> NSScrollView? {
        var current: NSView? = view
        while let node = current {
            if let scrollView = node as? NSScrollView {
                return scrollView
            }
            if let scrollView = node.enclosingScrollView {
                return scrollView
            }
            current = node.superview
        }
        return nil
    }
}

struct NotchScrollExemptMarker: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        ScrollExemptAnchorView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

extension View {
    func notchScrollExempt() -> some View {
        background(NotchScrollExemptMarker().frame(width: 0, height: 0))
    }
}
