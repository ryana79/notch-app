//
//  ClipboardHistoryView.swift
//  notchpro
//

import SwiftUI

struct ClipboardHistoryView: View {
    @ObservedObject private var manager = ClipboardHistoryManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Clipboard History")
                    .font(.headline)
                Spacer()
                if !manager.entries.isEmpty {
                    Button("Clear") {
                        manager.clearAll()
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            if manager.entries.isEmpty {
                ContentUnavailableView(
                    "No clips yet",
                    systemImage: "doc.on.doc",
                    description: Text("Copy something and it will appear here.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(manager.entries) { entry in
                        Button {
                            manager.copyToPasteboard(entry)
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: entry.icon)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 18)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.preview)
                                        .font(.body)
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)
                                    Text(entry.timestamp, style: .relative)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Copy") {
                                manager.copyToPasteboard(entry)
                            }
                            Button("Delete", role: .destructive) {
                                manager.removeEntry(entry)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 340, minHeight: 400)
    }
}
