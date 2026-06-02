//
//  ClipboardHistoryManager.swift
//  notchpro
//

import AppKit
import Combine
import Defaults
import SwiftUI

struct ClipboardEntry: Identifiable, Codable, Hashable {
    let id: UUID
    let content: String
    let timestamp: Date
    let contentType: ClipboardContentType

    enum ClipboardContentType: String, Codable {
        case text
        case url
    }

    var preview: String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 80 { return trimmed }
        return String(trimmed.prefix(77)) + "..."
    }

    var icon: String {
        switch contentType {
        case .text: return "doc.on.doc"
        case .url: return "link"
        }
    }
}

@MainActor
final class ClipboardHistoryManager: ObservableObject {
    static let shared = ClipboardHistoryManager()

    @Published private(set) var entries: [ClipboardEntry] = []
    @Published var isPanelVisible = false

    private var pollTimer: Timer?
    private var lastChangeCount: Int = NSPasteboard.general.changeCount
    private var lastCopiedContent: String?

    private init() {
        loadEntries()
        startMonitoring()
    }

    func startMonitoring() {
        guard Defaults[.enableClipboardHistory] else { return }
        pollTimer?.invalidate()
        lastChangeCount = NSPasteboard.general.changeCount
        let interval = Defaults[.performanceMode] ? 1.5 : 0.5
        pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkPasteboard()
            }
        }
    }

    func stopMonitoring() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func refreshMonitoring() {
        stopMonitoring()
        if Defaults[.enableClipboardHistory] {
            startMonitoring()
        }
    }

    private func checkPasteboard() {
        guard Defaults[.enableClipboardHistory] else { return }
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        guard let content = readPasteboardContent(pasteboard),
              !content.isEmpty,
              content != lastCopiedContent
        else { return }

        lastCopiedContent = content
        addEntry(content: content)
    }

    private func readPasteboardContent(_ pasteboard: NSPasteboard) -> String? {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           let url = urls.first {
            return url.absoluteString
        }
        return pasteboard.string(forType: .string)
    }

    func addEntry(content: String) {
        guard !SecureClipboardFilter.isSensitive(content) else { return }

        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if entries.first?.content == trimmed { return }

        let type: ClipboardEntry.ClipboardContentType =
            URL(string: trimmed)?.scheme != nil ? .url : .text

        let entry = ClipboardEntry(
            id: UUID(),
            content: trimmed,
            timestamp: Date(),
            contentType: type
        )

        entries.insert(entry, at: 0)
        let limit = Defaults[.clipboardHistoryLimit]
        if entries.count > limit {
            entries = Array(entries.prefix(limit))
        }
        saveEntries()
    }

    func copyToPasteboard(_ entry: ClipboardEntry) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.content, forType: .string)
        lastChangeCount = NSPasteboard.general.changeCount
        lastCopiedContent = entry.content
    }

    func removeEntry(_ entry: ClipboardEntry) {
        entries.removeAll { $0.id == entry.id }
        saveEntries()
    }

    func clearAll() {
        entries.removeAll()
        saveEntries()
    }

    func togglePanel() {
        isPanelVisible.toggle()
        if isPanelVisible {
            ClipboardHistoryPanelController.shared.showWindow()
        } else {
            ClipboardHistoryPanelController.shared.closeWindow()
        }
    }

    private var storageURL: URL {
        documentsDirectory.appendingPathComponent("clipboard_history.json")
    }

    private func loadEntries() {
        guard let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode([ClipboardEntry].self, from: data)
        else { return }
        entries = decoded
    }

    private func saveEntries() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }
}

final class ClipboardHistoryPanelController {
    static let shared = ClipboardHistoryPanelController()

    private var window: NSWindow?

    func showWindow() {
        if window == nil {
            let contentView = ClipboardHistoryView()
            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 360, height: 420),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window?.title = "Clipboard History"
            window?.titlebarAppearsTransparent = true
            window?.isReleasedWhenClosed = false
            window?.contentView = NSHostingView(rootView: contentView)
            window?.center()
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func closeWindow() {
        window?.orderOut(nil)
        Task { @MainActor in
            ClipboardHistoryManager.shared.isPanelVisible = false
        }
    }
}
