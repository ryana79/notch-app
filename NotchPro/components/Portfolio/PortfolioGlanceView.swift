//
//  PortfolioGlanceView.swift
//  NotchPro
//

import Defaults
import SwiftUI

struct NotchPortfolioPill: View {
    @ObservedObject private var portfolio = PortfolioManager.shared
    @Default(.showPortfolioGlance) private var showPortfolioGlance

    var body: some View {
        if showPortfolioGlance, let snapshot = portfolio.snapshot {
            NotchProPill(tint: snapshot.totalDayChange >= 0 ? .green : .red) {
                HStack(spacing: 5) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.caption2)
                    Text(formatSignedCurrency(snapshot.totalDayChange))
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
        } else if showPortfolioGlance, portfolio.isLoading {
            NotchProPill(tint: .blue) {
                ProgressView()
                    .controlSize(.mini)
                    .frame(width: 28, height: 14)
            }
        } else if showPortfolioGlance, portfolio.hasAnyConnection {
            NotchProPill(tint: .green) {
                HStack(spacing: 4) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.caption2)
                    Text("Portfolio")
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(.white.opacity(0.9))
            }
        }
    }

    private func formatSignedCurrency(_ value: Double) -> String {
        let prefix = value >= 0 ? "+" : "-"
        return "\(prefix)\(String(format: "$%.0f", abs(value)))"
    }
}

struct PortfolioGlanceView: View {
    var body: some View {
        NotchPortfolioPill()
    }
}

struct PortfolioExpandedView: View {
    @ObservedObject private var portfolio = PortfolioManager.shared

    var body: some View {
        if let snapshot = portfolio.snapshot {
            NotchProCard(accent: snapshot.totalDayChange >= 0 ? .green : .red, accentOpacity: 0.22) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Portfolio")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(formatCurrency(snapshot.totalMarketValue))
                                .font(.title3.weight(.bold).monospacedDigit())
                                .foregroundStyle(.white)
                        }
                        Spacer()
                        dayChangeBadge(snapshot.totalDayChange)
                    }

                    if !snapshot.holdings.isEmpty {
                        VStack(spacing: 6) {
                            ForEach(snapshot.holdings.prefix(4)) { holding in
                                holdingRow(holding)
                            }
                        }
                    }

                    HStack(spacing: 6) {
                        ForEach(snapshot.brokersConnected, id: \.self) { broker in
                            Text(broker.displayName)
                                .font(.caption2.weight(.medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.white.opacity(0.08)))
                        }
                        Spacer()
                        Text(snapshot.lastUpdated, style: .time)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .frame(minWidth: 180)
        } else if portfolio.isLoading {
            NotchProCard {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Loading positions…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else if portfolio.hasAnyConnection {
            NotchProCard(accent: .green, accentOpacity: 0.24) {
                VStack(alignment: .leading, spacing: 6) {
                    if let error = portfolio.lastError {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else {
                        Text("No open positions")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button("Refresh") {
                        Task { await portfolio.refresh() }
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.85))
                }
            }
        }
    }

    @ViewBuilder
    private func dayChangeBadge(_ change: Double) -> some View {
        let positive = change >= 0
        Text(formatSignedCurrency(change))
            .font(.caption.weight(.bold).monospacedDigit())
            .foregroundStyle(positive ? .green : .red)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule().fill((positive ? Color.green : Color.red).opacity(0.15))
            )
    }

    private func holdingRow(_ holding: PortfolioHolding) -> some View {
        HStack(spacing: 8) {
            Text(holding.symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 44, alignment: .leading)
            Text("\(holding.quantity, specifier: "%.0f")")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .trailing)
            Spacer(minLength: 0)
            Text(formatCurrency(holding.marketValue))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    private func formatCurrency(_ value: Double) -> String {
        if value >= 1000 {
            return String(format: "$%.1fk", value / 1000)
        }
        return String(format: "$%.0f", value)
    }

    private func formatSignedCurrency(_ value: Double) -> String {
        let prefix = value >= 0 ? "+" : ""
        return "\(prefix)\(formatCurrency(abs(value)))"
    }
}
