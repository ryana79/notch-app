//
//  SecureClipboardFilter.swift
//  NotchPro
//

import Foundation

enum SecureClipboardFilter {
    private static let sensitivePatterns: [NSRegularExpression] = {
        let patterns = [
            #"(?i)(password|passwd|secret|api[_-]?key|token|auth)[\s:=]+[^\s]{4,}"#,
            #"\b(?:\d{4}[\s-]?){3}\d{4}\b"#, // credit card
            #"(?i)-----BEGIN (?:RSA |EC )?PRIVATE KEY-----"#,
            #"\bsk-[a-zA-Z0-9]{20,}\b"#, // OpenAI-style keys
            #"\bgh[pousr]_[A-Za-z0-9_]{20,}\b"#, // GitHub tokens
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0) }
    }()

    static func isSensitive(_ content: String) -> Bool {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }

        if trimmed.count > 10_000 { return true }

        let range = NSRange(trimmed.startIndex..., in: trimmed)
        for regex in sensitivePatterns {
            if regex.firstMatch(in: trimmed, range: range) != nil {
                return true
            }
        }

        if trimmed.allSatisfy({ $0.isNumber || $0.isWhitespace || $0 == "-" }),
           trimmed.filter(\.isNumber).count >= 9 {
            return true
        }

        return false
    }

    static func sanitizedPreview(_ content: String) -> String {
        if isSensitive(content) {
            return "[Sensitive content hidden for security]"
        }
        return content
    }
}
