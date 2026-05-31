import SwiftData
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var quoteRefreshService: QuoteRefreshService
    @Query(sort: \Asset.updatedAt, order: .reverse) private var assets: [Asset]
    @State private var isTotalHidden = false

    private var snapshot: PortfolioSnapshot {
        PortfolioCalculator.snapshot(for: assets)
    }

    private var performances: [AssetPerformance] {
        assets
            .map { PortfolioCalculator.performance(for: $0) }
            .sorted { abs($0.dailyProfitLoss) > abs($1.dailyProfitLoss) }
    }

    private var dashboardQuoteState: QuoteRefreshState {
        guard quoteRefreshService.configuration.canRefresh else {
            if quoteRefreshService.configuration.mode == .mxData {
                return .failure(
                    message: "妙想 API Key 尚未配置",
                    detail: "请到设置 > 行情保存妙想 API Key。"
                )
            }
            return .failure(
                message: "行情源尚未配置",
                detail: "请到设置 > 行情填写真实行情接口地址。"
            )
        }
        return quoteRefreshService.state
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    summaryHeader
                    allocationSection
                    dailyContributionSection
                    moversSection
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("小目标")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await quoteRefreshService.refresh(assets: assets) }
                    } label: {
                        if quoteRefreshService.isRefreshing {
                            ProgressView()
                        } else {
                            Label("刷新行情", systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(quoteRefreshService.isRefreshing || !quoteRefreshService.configuration.canRefresh)
                }
            }
        }
    }

    private var summaryHeader: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text("总资产")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button {
                            isTotalHidden.toggle()
                        } label: {
                            Image(systemName: isTotalHidden ? "eye.slash" : "eye")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(isTotalHidden ? "****" : snapshot.totalValue.formatted(.currency(code: "CNY").precision(.fractionLength(1))))
                        .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                        .minimumScaleFactor(0.7)
                }
                Spacer()
                Image(systemName: snapshot.dailyProfitLoss >= 0 ? "arrow.up.right" : "arrow.down.right")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(isTotalHidden ? .secondary : FinanceFormatters.profitColor(snapshot.dailyProfitLoss))
                    .frame(width: 44, height: 44)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            HStack(spacing: 12) {
                MetricTile(
                    title: "今日盈亏",
                    value: isTotalHidden ? "****" : FinanceFormatters.signedCurrency(snapshot.dailyProfitLoss),
                    tint: isTotalHidden ? .secondary : FinanceFormatters.profitColor(snapshot.dailyProfitLoss),
                    subtitle: isTotalHidden ? nil : dailyReturnRate()
                )
                MetricTile(
                    title: "累计盈亏",
                    value: isTotalHidden ? "****" : FinanceFormatters.signedCurrency(snapshot.cumulativeProfitLoss),
                    tint: isTotalHidden ? .secondary : FinanceFormatters.profitColor(snapshot.cumulativeProfitLoss),
                    subtitle: isTotalHidden ? nil : cumulativeReturnRate()
                )
            }

            QuoteStatusLine(state: dashboardQuoteState)
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var allocationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("资产分布")

            if snapshot.totalValue <= 0 {
                ContentUnavailableView("暂无资产", systemImage: "tray", description: Text("添加股票、基金、理财或现金后会显示分布。"))
                    .frame(minHeight: 160)
            } else {
                VStack(spacing: 12) {
                    ForEach(snapshot.assetAllocation.filter { $0.value > 0 }) { allocation in
                        AllocationRow(allocation: allocation, hidden: isTotalHidden)
                    }
                }
            }
        }
        .sectionCard()
    }

    private var dailyContributionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("今日贡献")

            ForEach(AssetType.allCases) { type in
                let contribution = performances
                    .filter { $0.asset.type == type }
                    .reduce(0) { $0 + $1.dailyProfitLoss * cnyRate(for: $1.asset) }

                HStack {
                    Label(type.title, systemImage: type.systemImage)
                        .foregroundStyle(type.accentColor)
                    Spacer()
                    Text(FinanceFormatters.signedCurrency(contribution))
                        .foregroundStyle(FinanceFormatters.profitColor(contribution))
                        .monospacedDigit()
                }
                .font(.subheadline)
            }
        }
        .sectionCard()
    }

    private func dailyReturnRate() -> String? {
        let base = snapshot.totalValue - snapshot.dailyProfitLoss
        guard base > 0 else { return nil }
        let rate = snapshot.dailyProfitLoss / base
        let prefix = rate > 0 ? "+" : ""
        return prefix + rate.formatted(.percent.precision(.fractionLength(2)))
    }

    private func cumulativeReturnRate() -> String? {
        let base = snapshot.totalValue - snapshot.cumulativeProfitLoss
        guard base > 0 else { return nil }
        let rate = snapshot.cumulativeProfitLoss / base
        let prefix = rate > 0 ? "+" : ""
        return prefix + rate.formatted(.percent.precision(.fractionLength(2)))
    }

    private func cnyRate(for asset: Asset) -> Double {
        asset.needsCNYConversion ? Market.rate(for: asset.resolvedMarket) : 1.0
    }

    private var moversSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("持仓异动")

            if performances.isEmpty {
                ContentUnavailableView("暂无持仓", systemImage: "chart.line.uptrend.xyaxis")
                    .frame(minHeight: 120)
            } else {
                ForEach(performances.prefix(5)) { item in
                    NavigationLink {
                        AssetDetailView(asset: item.asset)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: item.asset.type.systemImage)
                                .foregroundStyle(item.asset.type.accentColor)
                                .frame(width: 32, height: 32)
                                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.asset.name)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text(item.asset.displayCode)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 3) {
                                Text(FinanceFormatters.signedValueWithSymbol(item.dailyProfitLoss, symbol: item.asset.currencySymbol))
                                    .foregroundStyle(FinanceFormatters.profitColor(item.dailyProfitLoss))
                                Text(FinanceFormatters.valueWithSymbol(item.currentValue, symbol: item.asset.currencySymbol))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .monospacedDigit()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .sectionCard()
    }
}

private struct QuoteStatusLine: View {
    let state: QuoteRefreshState

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(state.message)
                    .font(.footnote)
                    .foregroundStyle(tint)
                if let detail = state.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var systemImage: String {
        switch state {
        case .idle:
            "info.circle"
        case .refreshing:
            "arrow.clockwise"
        case .success:
            "checkmark.circle"
        case .warning:
            "exclamationmark.triangle"
        case .failure:
            "xmark.octagon"
        }
    }

    private var tint: Color {
        switch state {
        case .idle:
            .secondary
        case .refreshing:
            .blue
        case .success:
            .green
        case .warning:
            .orange
        case .failure:
            .red
        }
    }
}

private struct SectionTitle: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.headline)
    }
}

private struct AllocationRow: View {
    let allocation: AssetAllocation
    var hidden = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(allocation.type.title, systemImage: allocation.type.systemImage)
                    .foregroundStyle(allocation.type.accentColor)
                Spacer()
                Text(FinanceFormatters.percent(allocation.percent))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            ProgressView(value: allocation.percent)
                .tint(allocation.type.accentColor)
            Text(hidden ? "****" : FinanceFormatters.currency(allocation.value))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}
