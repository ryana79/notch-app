//
//  ScreenshotCaptureManager.swift
//  notchpro
//

import AppKit
import Defaults

@MainActor
final class ScreenshotCaptureManager: ObservableObject {
    static let shared = ScreenshotCaptureManager()

    @Published private(set) var lastStatusMessage: String?

    private var isCapturing = false
    private var statusClearTask: Task<Void, Never>?

    var screenshotsDirectory: URL {
        let dir = documentsDirectory.appendingPathComponent("NotchPro/Screenshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func captureInteractive() {
        guard Defaults[.enableQuickScreenshot] else { return }
        guard !isCapturing else { return }
        isCapturing = true
        showStatus("Select an area…")

        Task.detached(priority: .userInitiated) {
            let success = Self.runInteractiveCapture()
            await MainActor.run {
                ScreenshotCaptureManager.shared.finishCapture(success: success)
            }
        }
    }

    nonisolated private static func runInteractiveCapture() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-c", "-x"]
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func finishCapture(success: Bool) {
        isCapturing = false
        guard success else {
            showStatus(nil)
            return
        }

        guard let image = Self.imageFromGeneralPasteboard(),
              let savedURL = Self.savePNG(image, in: screenshotsDirectory)
        else {
            showStatus("Screenshot failed")
            return
        }

        let fileName = savedURL.lastPathComponent
        Self.writeImageToPasteboard(image)

        if Defaults[.enableClipboardHistory] {
            ClipboardHistoryManager.shared.addScreenshotEntry(fileName: fileName)
        }

        if Defaults[.screenshotPushToShelf], Defaults[.notchProShelf],
           let bookmark = (try? Bookmark(url: savedURL))?.data {
            ShelfStateViewModel.shared.add([
                ShelfItem(kind: .file(bookmark: bookmark)),
            ])
        }

        showStatus("Screenshot copied")
    }

    nonisolated private static func imageFromGeneralPasteboard() -> NSImage? {
        let pasteboard = NSPasteboard.general
        if let data = pasteboard.data(forType: .png), let image = NSImage(data: data) {
            return image
        }
        return NSImage(pasteboard: pasteboard)
    }

    nonisolated private static func writeImageToPasteboard(_ image: NSImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }

    nonisolated private static func savePNG(_ image: NSImage, in directory: URL) -> URL? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:])
        else { return nil }

        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let fileName = "screenshot-\(stamp).png"
        let url = directory.appendingPathComponent(fileName)
        do {
            try png.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    func imageURL(for entry: ClipboardEntry) -> URL? {
        guard entry.contentType == .image else { return nil }
        return screenshotsDirectory.appendingPathComponent(entry.content)
    }

    private func showStatus(_ message: String?) {
        statusClearTask?.cancel()
        lastStatusMessage = message
        guard message != nil else { return }
        statusClearTask = Task {
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if self.lastStatusMessage == message {
                    self.lastStatusMessage = nil
                }
            }
        }
    }
}
