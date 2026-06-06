//
//  BrokerConnectionCache.swift
//  NotchPro
//

import Foundation

/// Lightweight connection flags so launch doesn't hit the Keychain for UI state.
enum BrokerConnectionCache {
    private static let schwabKey = "notchpro.broker.schwab.connected"
    private static let webullKey = "notchpro.broker.webull.connected"

    static var schwabConnected: Bool {
        UserDefaults.standard.bool(forKey: schwabKey)
    }

    static var webullConnected: Bool {
        UserDefaults.standard.bool(forKey: webullKey)
    }

    static func setSchwabConnected(_ connected: Bool) {
        UserDefaults.standard.set(connected, forKey: schwabKey)
    }

    static func setWebullConnected(_ connected: Bool) {
        UserDefaults.standard.set(connected, forKey: webullKey)
    }
}
