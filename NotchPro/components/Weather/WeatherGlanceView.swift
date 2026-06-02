//
//  WeatherGlanceView.swift
//  NotchPro
//

import Defaults
import SwiftUI

struct NotchWeatherPill: View {
    @ObservedObject private var weatherManager = WeatherManager.shared
    @Default(.showWeatherGlance) private var showWeatherGlance

    var body: some View {
        if showWeatherGlance {
            if let weather = weatherManager.weather {
                NotchProPill(tint: .cyan) {
                    HStack(spacing: 5) {
                        Image(systemName: weather.iconName)
                            .font(.caption)
                            .symbolRenderingMode(.multicolor)
                        Text("\(weather.temperatureF)°")
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }
            } else if weatherManager.isLoading {
                NotchProPill(tint: .cyan) {
                    ProgressView()
                        .controlSize(.mini)
                        .frame(width: 28, height: 14)
                }
            } else {
                Button {
                    weatherManager.refreshNow()
                } label: {
                    NotchProPill(tint: .gray) {
                        HStack(spacing: 4) {
                            Image(systemName: "cloud.slash")
                                .font(.caption2)
                            Text("Weather")
                                .font(.caption2)
                        }
                        .foregroundStyle(.white.opacity(0.75))
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct WeatherGlanceView: View {
    var body: some View {
        NotchWeatherPill()
    }
}

struct WeatherGlanceExpandedView: View {
    @ObservedObject private var weatherManager = WeatherManager.shared

    var body: some View {
        if let weather = weatherManager.weather {
            NotchProCard(accent: .cyan, accentOpacity: 0.22) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [.cyan.opacity(0.25), .blue.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 44, height: 44)
                        Image(systemName: weather.iconName)
                            .font(.title2)
                            .symbolRenderingMode(.multicolor)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(weather.temperatureF)°")
                            .font(.title2.weight(.bold).monospacedDigit())
                            .foregroundStyle(.white)
                        Text(weather.condition)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(minWidth: 140)
        } else if weatherManager.isLoading {
            NotchProCard {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading weather…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            NotchProCard(accent: .gray) {
                Button {
                    weatherManager.refreshNow()
                } label: {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Tap to load weather")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
