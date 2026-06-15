//
//  WebullBrokerService.swift
//  NotchPro
//

import Foundation
import NotchProCore

@MainActor
final class WebullBrokerService {
    static let shared = WebullBrokerService()

    private init() {}

    var isConnected: Bool {
        BrokerConnectionCache.webullConnected
    }

    func disconnect() {
        BrokerageConnectionManager.shared.disconnectWebull()
    }

    func fetchHoldings() async throws -> [PortfolioHolding] {
        guard BrokerConfig.shared.isWebullConfigured else {
            throw BrokerageConnectionError.notConfigured(.webull)
        }

        let accessToken = try await WebullAuthService.shared.validAccessToken()
        let accountID = try await WebullAuthService.shared.accountID(for: accessToken)
        let config = BrokerConfig.shared

        let (data, status) = try await WebullAuthService.shared.signedDataRequest(
            method: "GET",
            path: "/openapi/account/positions",
            query: ["account_id": accountID],
            body: nil,
            appKey: config.webullAppKey,
            appSecret: config.webullAppSecret,
            accessToken: accessToken
        )

        if status == 401 {
            disconnect()
            throw BrokerageConnectionError.sessionExpired
        }
        guard (200...299).contains(status) else {
            throw BrokerageConnectionError.apiHTTP(status: status, debugCode: "webull_positions")
        }

        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let holdings = json["holdings"] as? [[String: Any]] ?? json["positions"] as? [[String: Any]] {
            return parseHoldings(holdings)
        }
        if let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return parseHoldings(array)
        }
        return []
    }

    private func parseHoldings(_ items: [[String: Any]]) -> [PortfolioHolding] {
        items.compactMap { item in
            let symbol = (item["symbol"] as? String)
                ?? (item["ticker"] as? String)
                ?? (item["ticker_id"] as? String)
            guard let symbol else { return nil }

            let quantity = doubleValue(item["quantity"] ?? item["qty"] ?? item["position_qty"])
            let marketValue = doubleValue(item["market_value"] ?? item["marketValue"] ?? item["position_value"])
            let dayChange = doubleValue(item["unrealized_day_profit_loss"] ?? item["day_profit_loss"])
            let dayChangePercent = doubleValue(item["unrealized_day_profit_loss_rate"] ?? item["day_profit_loss_ratio"])

            return PortfolioHolding(
                id: "webull-\(symbol)",
                broker: .webull,
                symbol: symbol,
                quantity: quantity,
                marketValue: marketValue,
                dayChange: dayChange == 0 ? nil : dayChange,
                dayChangePercent: dayChangePercent == 0 ? nil : dayChangePercent
            )
        }
    }

    private func doubleValue(_ value: Any?) -> Double {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let s = value as? String { return Double(s) ?? 0 }
        return 0
    }
}
