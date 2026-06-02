//
//  BrokerConfig.swift
//  NotchPro
//
//  Shared NotchPro broker app credentials — configured once by the app owner.
//  Friends only tap Connect; they never enter API keys.
//

import Foundation

struct BrokerConfig {
    static let shared = BrokerConfig()

    let schwabClientID: String
    /// Used only for local/dev builds. Prefer SchwabTokenProxyURL for builds you share.
    let schwabClientSecret: String
    let schwabTokenProxyURL: URL?
    let brokerProxyAPIKey: String
    let webullAppKey: String
    let webullAppSecret: String

    var isSchwabConfigured: Bool {
        !schwabClientID.isEmpty && (!schwabClientSecret.isEmpty || schwabTokenProxyURL != nil)
    }

    var isWebullConfigured: Bool {
        !webullAppKey.isEmpty && !webullAppSecret.isEmpty
    }

    private init() {
        let plist = Self.loadPlist(named: "BrokerCredentials")
            ?? Self.loadPlist(named: "BrokerCredentials.example")
            ?? [:]

        schwabClientID = (plist["SchwabClientID"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        schwabClientSecret = (plist["SchwabClientSecret"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        brokerProxyAPIKey = (plist["BrokerProxyAPIKey"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        webullAppKey = (plist["WebullAppKey"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        webullAppSecret = (plist["WebullAppSecret"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        if let proxy = (plist["SchwabTokenProxyURL"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !proxy.isEmpty {
            schwabTokenProxyURL = URL(string: proxy)
        } else {
            schwabTokenProxyURL = nil
        }
    }

    private static func loadPlist(named name: String) -> [String: Any]? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "plist") else { return nil }
        guard let data = try? Data(contentsOf: url),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return nil
        }
        return dict
    }
}

enum BrokerSetupError: LocalizedError {
    case notConfigured(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured(let broker):
            return "\(broker) isn’t set up in this build of NotchPro yet."
        }
    }
}
