//
//  PortfolioInsightsManager.swift
//  NotchPro
//

import Defaults
import Foundation

struct PortfolioNewsHeadline: Identifiable, Equatable {
    let id: String
    let symbol: String
    let title: String
    let link: URL?
}

@MainActor
final class PortfolioInsightsManager: ObservableObject {
    static let shared = PortfolioInsightsManager()

    @Published private(set) var insight: String?
    @Published private(set) var headlines: [PortfolioNewsHeadline] = []
    @Published private(set) var isGenerating = false
    @Published private(set) var lastError: String?

    private let session: URLSession
    private let groqEndpoint = URL(string: "https://api.groq.com/openai/v1/chat/completions")!

    private init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 25
        session = URLSession(configuration: config)
    }

    var hasAPIKey: Bool {
        guard let key = KeychainStore.load(account: IntegrationCredentialKey.groqAPIKey) else {
            return false
        }
        return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func saveAPIKey(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            clearAPIKey()
            return
        }
        try KeychainStore.save(trimmed, account: IntegrationCredentialKey.groqAPIKey)
    }

    func clearAPIKey() {
        KeychainStore.delete(account: IntegrationCredentialKey.groqAPIKey)
        insight = nil
        headlines = []
        lastError = nil
    }

    func refresh(snapshot: PortfolioSnapshot) async {
        guard Defaults[.enablePortfolioInsights] else { return }

        let symbols = Array(Set(snapshot.holdings.map(\.symbol))).sorted().prefix(6)
        headlines = await fetchNews(symbols: Array(symbols))

        guard hasAPIKey else {
            lastError = nil
            insight = nil
            return
        }

        await generateInsight(snapshot: snapshot)
    }

    func clear() {
        insight = nil
        headlines = []
        lastError = nil
        isGenerating = false
    }

    private func fetchNews(symbols: [String]) async -> [PortfolioNewsHeadline] {
        guard !symbols.isEmpty else { return [] }

        var collected: [PortfolioNewsHeadline] = []
        await withTaskGroup(of: [PortfolioNewsHeadline].self) { group in
            for symbol in symbols {
                group.addTask {
                    await self.fetchNews(for: symbol)
                }
            }
            for await batch in group {
                collected.append(contentsOf: batch)
            }
        }
        return Array(collected.prefix(8))
    }

    private func fetchNews(for symbol: String) async -> [PortfolioNewsHeadline] {
        guard let url = URL(string: "https://feeds.finance.yahoo.com/rss/2.0/headline?s=\(symbol)&region=US&lang=en-US") else {
            return []
        }
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return []
            }
            guard let xml = String(data: data, encoding: .utf8) else { return [] }
            return parseRSS(xml, symbol: symbol)
        } catch {
            return []
        }
    }

    private func parseRSS(_ xml: String, symbol: String) -> [PortfolioNewsHeadline] {
        let items = xml.components(separatedBy: "<item>")
        return items.dropFirst().prefix(2).enumerated().compactMap { index, block in
            guard let title = firstTag("title", in: block)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !title.isEmpty else { return nil }
            let linkString = firstTag("link", in: block)
            return PortfolioNewsHeadline(
                id: "\(symbol)-\(index)",
                symbol: symbol,
                title: title,
                link: linkString.flatMap { URL(string: $0) }
            )
        }
    }

    private func firstTag(_ tag: String, in block: String) -> String? {
        let open = "<\(tag)>"
        let close = "</\(tag)>"
        guard let start = block.range(of: open)?.upperBound,
              let end = block.range(of: close, range: start..<block.endIndex)?.lowerBound else {
            return nil
        }
        return String(block[start..<end])
    }

    private func generateInsight(snapshot: PortfolioSnapshot) async {
        guard let apiKey = KeychainStore.load(account: IntegrationCredentialKey.groqAPIKey) else { return }

        isGenerating = true
        lastError = nil
        defer { isGenerating = false }

        let holdingsSummary = snapshot.holdings.prefix(12).map { holding in
            var line = "\(holding.symbol): $\(String(format: "%.0f", holding.marketValue))"
            if let pct = holding.dayChangePercent {
                line += " (\(String(format: "%+.1f", pct))% today)"
            }
            return line
        }.joined(separator: "\n")

        let newsSummary = headlines.map { "[\($0.symbol)] \($0.title)" }.joined(separator: "\n")
        let dayPct = snapshot.totalMarketValue > 0
            ? (snapshot.totalDayChange / snapshot.totalMarketValue) * 100
            : 0

        let prompt = """
        Portfolio total: $\(String(format: "%.0f", snapshot.totalMarketValue)) (day change \(String(format: "%+.1f", dayPct))%).

        Holdings:
        \(holdingsSummary.isEmpty ? "No open positions." : holdingsSummary)

        Recent headlines:
        \(newsSummary.isEmpty ? "No headlines available." : newsSummary)

        Give 3–4 concise bullet points: portfolio health, notable movers, and any news-driven risks or opportunities. Plain language, under 120 words total.
        """

        var request = URLRequest(url: groqEndpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "model": "llama-3.3-70b-versatile",
            "messages": [
                ["role": "system", "content": "You are a helpful portfolio analyst. Be factual and concise."],
                ["role": "user", "content": prompt],
            ],
            "max_tokens": 350,
            "temperature": 0.35,
        ])

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                lastError = "Could not reach Groq."
                return
            }
            guard (200...299).contains(http.statusCode) else {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let error = json["error"] as? [String: Any],
                   let message = error["message"] as? String {
                    lastError = message
                } else {
                    lastError = "Groq request failed (HTTP \(http.statusCode))."
                }
                return
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let first = choices.first,
                  let message = first["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                lastError = "Unexpected Groq response."
                return
            }
            insight = content.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            lastError = error.localizedDescription
        }
    }
}
