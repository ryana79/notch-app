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
        Group {
            if portfolio.isDetailExpanded {
                PortfolioDetailPanel()
            } else {
                compactCard
            }
        }
        .animation(.smooth(duration: 0.25), value: portfolio.isDetailExpanded)
    }

    @ViewBuilder
    private var compactCard: some View {
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
                                holdingRow(holding, compact: true)
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
                        Label("Details", systemImage: "chevron.right")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .frame(minWidth: 180)
            .contentShape(Rectangle())
            .onTapGesture { portfolio.isDetailExpanded = true }
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

    private func holdingRow(_ holding: PortfolioHolding, compact: Bool) -> some View {
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
            if !compact, let pct = holding.dayChangePercent {
                Text(String(format: "%+.1f%%", pct))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(pct >= 0 ? .green : .red)
                    .frame(width: 44, alignment: .trailing)
            }
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

struct PortfolioDetailPanel: View {
    @ObservedObject private var portfolio = PortfolioManager.shared
    @ObservedObject private var insights = PortfolioInsightsManager.shared
    @Default(.enablePortfolioInsights) private var enablePortfolioInsights

    var body: some View {
        if let snapshot = portfolio.snapshot {
            NotchProCard(accent: snapshot.totalDayChange >= 0 ? .green : .red, accentOpacity: 0.24) {
                VStack(alignment: .leading, spacing: 12) {
                    header(snapshot)
                    holdingsSection(snapshot)
                    newsSection
                    insightsSection
                    footer(snapshot)
                }
            }
            .frame(minWidth: 260)
            .onAppear {
                Task { await PortfolioInsightsManager.shared.refresh(snapshot: snapshot) }
            }
        }
    }

    private func header(_ snapshot: PortfolioSnapshot) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Portfolio")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(formatCurrency(snapshot.totalMarketValue))
                    .font(.title2.weight(.bold).monospacedDigit())
                    .foregroundStyle(.white)
                let dayPct = snapshot.totalMarketValue > 0
                    ? (snapshot.totalDayChange / snapshot.totalMarketValue) * 100
                    : 0
                Text("\(formatSignedCurrency(snapshot.totalDayChange)) (\(String(format: "%+.2f", dayPct))%) today")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(snapshot.totalDayChange >= 0 ? .green : .red)
            }
            Spacer()
            Button {
                portfolio.isDetailExpanded = false
                PortfolioInsightsManager.shared.clear()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.35))
            }
            .buttonStyle(.plain)
        }
    }

    private func holdingsSection(_ snapshot: PortfolioSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Holdings")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(snapshot.holdings) { holding in
                HStack(spacing: 8) {
                    Text(holding.symbol)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 48, alignment: .leading)
                    Text(holding.broker.displayName)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(width: 44, alignment: .leading)
                    Spacer(minLength: 0)
                    if let pct = holding.dayChangePercent {
                        Text(String(format: "%+.1f%%", pct))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(pct >= 0 ? .green : .red)
                    }
                    Text(formatCurrency(holding.marketValue))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(width: 52, alignment: .trailing)
                }
            }
        }
    }

    @ViewBuilder
    private var newsSection: some View {
        if !insights.headlines.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Market news")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(insights.headlines.prefix(4)) { headline in
                    HStack(alignment: .top, spacing: 6) {
                        Text(headline.symbol)
                            .font(.caption2.weight(.bold).monospaced())
                            .foregroundStyle(.cyan)
                            .frame(width: 36, alignment: .leading)
                        Text(headline.title)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(2)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var insightsSection: some View {
        if enablePortfolioInsights {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("AI insights")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if insights.isGenerating {
                        ProgressView().controlSize(.mini)
                    }
                }
                if insights.isGenerating, insights.insight == nil {
                    Text("Analyzing positions and headlines…")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else if let insight = insights.insight {
                    Text(insight)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                } else if !PortfolioInsightsManager.shared.hasAPIKey {
                    Text("Add a free Groq API key in Settings → Integrations for AI insights.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else if let error = insights.lastError {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private func footer(_ snapshot: PortfolioSnapshot) -> some View {
        HStack(spacing: 6) {
            ForEach(snapshot.brokersConnected, id: \.self) { broker in
                Text(broker.displayName)
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
            }
            Spacer()
            Button("Refresh") {
                Task { await portfolio.refresh() }
            }
            .font(.caption2.weight(.semibold))
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.75))
            Text(snapshot.lastUpdated, style: .time)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func formatCurrency(_ value: Double) -> String {
        if value >= 1_000_000 {
            return String(format: "$%.2fM", value / 1_000_000)
        }
        if value >= 1000 {
            return String(format: "$%.1fk", value / 1000)
        }
        return String(format: "$%.0f", value)
    }

    private func formatSignedCurrency(_ value: Double) -> String {
        let prefix = value >= 0 ? "+" : "-"
        return "\(prefix)\(formatCurrency(abs(value)))"
    }
}
