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
    let city: String

    var displayText: String {
        "\(temperatureF)° · \(city)"
    }
}

private struct CachedGeoLocation: Codable, Equatable {
    let lat: Double
    let lon: Double
    let city: String
    let fetchedAt: Date

    var isFresh: Bool {
        Date().timeIntervalSince(fetchedAt) < 86_400
    }
}

@MainActor
final class WeatherManager: ObservableObject {
    static let shared = WeatherManager()

    @Published private(set) var weather: WeatherSnapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?

    private var refreshTimer: Timer?
    private var lastFetchDate: Date?
    private var cachedGeo: CachedGeoLocation?
    private var isRefreshScheduled = false

    private let geoCacheKey = "notchpro.weather.geo.v1"

    private init() {
        if let data = UserDefaults.standard.data(forKey: geoCacheKey),
           let cached = try? JSONDecoder().decode(CachedGeoLocation.self, from: data),
           cached.isFresh {
            cachedGeo = cached
        }
    }

    func startIfEnabled() {
        guard Defaults[.showWeatherGlance] else {
            stop()
            return
        }
        if weather == nil {
            fetchWeather()
        }
    }

    func stop() {
        pauseRefreshTimer()
    }

    func pauseRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        isRefreshScheduled = false
    }

    func resumeRefreshTimer() {
        guard Defaults[.showWeatherGlance], !isRefreshScheduled else { return }
        scheduleRefresh()
    }

    func refreshNow() {
        lastFetchDate = nil
        fetchWeather()
    }

    private func scheduleRefresh() {
        refreshTimer?.invalidate()
        isRefreshScheduled = true
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
        lastError = nil

        Task {
            defer { isLoading = false }
            var snapshot = await fetchFromOpenMeteo()
            if snapshot == nil {
                snapshot = await fetchFromWttrIn()
            }
            if let snapshot {
                weather = snapshot
                lastFetchDate = Date()
            } else if weather == nil {
                lastError = "Unavailable"
            }
        }
    }

    private func fetchFromOpenMeteo() async -> WeatherSnapshot? {
        guard let geo = await resolveLocation() else { return nil }
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(geo.lat)),
            URLQueryItem(name: "longitude", value: String(geo.lon)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code"),
            URLQueryItem(name: "temperature_unit", value: "fahrenheit"),
        ]
        guard let url = components.url else { return nil }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 8
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let current = json["current"] as? [String: Any],
                  let temp = current["temperature_2m"] as? Double,
                  let code = current["weather_code"] as? Int
            else { return nil }

            return WeatherSnapshot(
                temperatureF: Int(temp.rounded()),
                condition: condition(forWeatherCode: code),
                iconName: icon(forWeatherCode: code),
                city: geo.city
            )
        } catch {
            return nil
        }
    }

    private func resolveLocation() async -> CachedGeoLocation? {
        if let cachedGeo, cachedGeo.isFresh {
            return cachedGeo
        }

        guard let url = URL(string: "https://ipapi.co/json/") else { return nil }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 6
            request.setValue("NotchPro/1.0", forHTTPHeaderField: "User-Agent")
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let lat = json["latitude"] as? Double,
                  let lon = json["longitude"] as? Double
            else { return nil }

            let city = (json["city"] as? String)
                ?? (json["region"] as? String)
                ?? "Local"

            let geo = CachedGeoLocation(lat: lat, lon: lon, city: city, fetchedAt: .now)
            cachedGeo = geo
            if let data = try? JSONEncoder().encode(geo) {
                UserDefaults.standard.set(data, forKey: geoCacheKey)
            }
            return geo
        } catch {
            return cachedGeo
        }
    }

    private func fetchFromWttrIn() async -> WeatherSnapshot? {
        guard let url = URL(string: "https://wttr.in/?format=j1") else { return nil }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 8
            request.setValue("curl/8.0", forHTTPHeaderField: "User-Agent")
            let (data, _) = try await URLSession.shared.data(for: request)
            return Self.parseWeatherJSON(data)
        } catch {
            return nil
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
        let city = ((json["nearest_area"] as? [[String: Any]])?.first?["areaName"] as? [[String: Any]])?.first?["value"] as? String
            ?? "Local"

        return WeatherSnapshot(
            temperatureF: tempF,
            condition: desc,
            iconName: icon(forWeatherCode: code),
            city: city
        )
    }

    private func condition(forWeatherCode code: Int) -> String {
        switch code {
        case 0: return "Clear"
        case 1, 2, 3: return "Partly cloudy"
        case 45, 48: return "Foggy"
        case 51, 53, 55, 61, 63, 65, 80, 81, 82: return "Rain"
        case 71, 73, 75, 77, 85, 86: return "Snow"
        case 95, 96, 99: return "Thunderstorm"
        default: return "Cloudy"
        }
    }

    private func icon(forWeatherCode code: Int) -> String {
        switch code {
        case 0: return "sun.max.fill"
        case 1, 2: return "cloud.sun.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55, 61, 63, 65, 80, 81, 82: return "cloud.rain.fill"
        case 71, 73, 75, 77, 85, 86: return "cloud.snow.fill"
        case 95, 96, 99: return "cloud.bolt.rain.fill"
        default: return "cloud.sun.fill"
        }
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
