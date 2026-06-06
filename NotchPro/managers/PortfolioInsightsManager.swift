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

    var usesBuiltInAI: Bool {
        BrokerConfig.shared.isInsightsProxyConfigured
    }

    var hasAPIKey: Bool {
        guard let key = KeychainStore.load(account: IntegrationCredentialKey.groqAPIKey) else {
            return false
        }
        return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canGenerateInsights: Bool {
        usesBuiltInAI || hasAPIKey
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
    }

    func refresh(snapshot: PortfolioSnapshot) async {
        guard Defaults[.enablePortfolioInsights] else { return }

        let symbols = Array(Set(snapshot.holdings.map(\.symbol))).sorted().prefix(6)
        headlines = await fetchNews(symbols: Array(symbols))

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

    private func buildPrompt(snapshot: PortfolioSnapshot) -> String {
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

        return """
        Portfolio total: $\(String(format: "%.0f", snapshot.totalMarketValue)) (day change \(String(format: "%+.1f", dayPct))%).

        Holdings:
        \(holdingsSummary.isEmpty ? "No open positions." : holdingsSummary)

        Recent headlines:
        \(newsSummary.isEmpty ? "No headlines available." : newsSummary)

        Give 3–4 concise bullet points: portfolio health, notable movers, and any news-driven risks or opportunities. Plain language, under 120 words total.
        """
    }

    private func generateInsight(snapshot: PortfolioSnapshot) async {
        isGenerating = true
        lastError = nil
        defer { isGenerating = false }

        let prompt = buildPrompt(snapshot: snapshot)

        if BrokerConfig.shared.isInsightsProxyConfigured,
           let proxyURL = BrokerConfig.shared.portfolioInsightsProxyURL {
            if await generateViaProxy(prompt: prompt, url: proxyURL) {
                return
            }
        }

        if hasAPIKey, let apiKey = KeychainStore.load(account: IntegrationCredentialKey.groqAPIKey) {
            await generateViaGroq(prompt: prompt, apiKey: apiKey)
            if insight != nil { return }
        }

        insight = generateLocalFallback(snapshot: snapshot)
        lastError = nil
    }

    private func generateLocalFallback(snapshot: PortfolioSnapshot) -> String {
        let dayPct = snapshot.totalMarketValue > 0
            ? (snapshot.totalDayChange / snapshot.totalMarketValue) * 100
            : 0
        let direction = dayPct >= 0 ? "up" : "down"
        var lines = [
            "• Portfolio is \(direction) \(String(format: "%.1f", abs(dayPct)))% today ($\(String(format: "%.0f", abs(snapshot.totalDayChange))))."
        ]
        if let top = snapshot.holdings.first {
            lines.append("• Largest position: \(top.symbol) at $\(String(format: "%.0f", top.marketValue)).")
        }
        if let mover = snapshot.holdings.compactMap({ h -> (PortfolioHolding, Double)? in
            guard let pct = h.dayChangePercent else { return nil }
            return (h, abs(pct))
        }).max(by: { $0.1 < $1.1 })?.0, let pct = mover.dayChangePercent {
            lines.append("• Biggest mover: \(mover.symbol) \(String(format: "%+.1f", pct))%.")
        }
        if let headline = headlines.first {
            lines.append("• News: \(headline.symbol) — \(headline.title)")
        }
        return lines.joined(separator: "\n")
    }

    private func generateViaProxy(prompt: String, url: URL) async -> Bool {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(BrokerConfig.shared.brokerProxyAPIKey, forHTTPHeaderField: "x-notchpro-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["prompt": prompt])

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                lastError = "Could not reach insights service."
                return false
            }
            guard (200...299).contains(http.statusCode) else {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let error = json["error"] as? String {
                    lastError = error
                } else {
                    lastError = "Insights service unavailable (HTTP \(http.statusCode))."
                }
                return false
            }
            return parseGroqResponse(data)
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    private func generateViaGroq(prompt: String, apiKey: String) async {
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
            _ = parseGroqResponse(data)
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func parseGroqResponse(_ data: Data) -> Bool {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            lastError = "Unexpected AI response."
            return false
        }
        insight = content.trimmingCharacters(in: .whitespacesAndNewlines)
        lastError = nil
        return true
    }
}
