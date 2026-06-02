//
//  WeatherManager.swift
//  notchpro
//

import Combine
import Defaults
import Foundation

struct WeatherSnapshot: Equatable {
    let temperatureF: Int
    let condition: String
    let iconName: String

    var displayText: String {
        "\(temperatureF)° · \(condition)"
    }
}

@MainActor
final class WeatherManager: ObservableObject {
    static let shared = WeatherManager()

    @Published private(set) var weather: WeatherSnapshot?
    @Published private(set) var isLoading = false

    private var refreshTimer: Timer?
    private var lastFetchDate: Date?

    private init() {}

    func startIfEnabled() {
        guard Defaults[.showWeatherGlance] else {
            stop()
            return
        }
        scheduleRefresh()
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func refreshIfEnabled() {
        guard Defaults[.showWeatherGlance] else { return }
        startIfEnabled()
    }

    private func scheduleRefresh() {
        refreshTimer?.invalidate()
        fetchWeather()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: Defaults[.performanceMode] ? 1800 : 900, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.fetchWeather()
            }
        }
    }

    private func fetchWeather() {
        guard !isLoading else { return }
        if let lastFetchDate,
           Date().timeIntervalSince(lastFetchDate) < 120 {
            return
        }

        isLoading = true
        guard let url = URL(string: "https://wttr.in/?format=j1") else {
            isLoading = false
            return
        }

        Task {
            defer { isLoading = false }
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 8
                request.setValue("curl/8.0", forHTTPHeaderField: "User-Agent")
                let (data, _) = try await URLSession.shared.data(for: request)
                if let snapshot = Self.parseWeatherJSON(data) {
                    weather = snapshot
                    lastFetchDate = Date()
                }
            } catch {
                print("Weather fetch failed: \(error.localizedDescription)")
            }
        }
    }

    private static func parseWeatherJSON(_ data: Data) -> WeatherSnapshot? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let current = (json["current_condition"] as? [[String: Any]])?.first,
              let tempFString = (current["temp_F"] as? [String])?.first,
              let tempF = Int(tempFString),
              let desc = (current["weatherDesc"] as? [[String: Any]])?.first?["value"] as? String
        else { return nil }

        let code = (current["weatherCode"] as? [String])?.first ?? "113"
        return WeatherSnapshot(
            temperatureF: tempF,
            condition: desc,
            iconName: icon(forWeatherCode: code)
        )
    }

    private static func icon(forWeatherCode code: String) -> String {
        switch code {
        case "113": return "sun.max.fill"
        case "116": return "cloud.sun.fill"
        case "119", "122": return "cloud.fill"
        case "176", "263", "266", "281", "284", "293", "296", "299", "302", "305", "308", "311", "314", "353", "356", "359", "386", "389", "392", "395":
            return "cloud.rain.fill"
        case "179", "182", "185", "227", "230", "317", "320", "323", "326", "329", "332", "335", "338", "368", "371", "374", "377":
            return "cloud.snow.fill"
        case "200", "386", "389": return "cloud.bolt.rain.fill"
        default: return "cloud.sun.fill"
        }
    }
}
