import SwiftData
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var quoteRefreshService: QuoteRefreshService
    @Query(sort: \Asset.updatedAt, order: .reverse) private var assets: [Asset]
    @State private var isTotalHidden = false
    @State private var performances: [AssetPerformance] = []
    @State private var selectedAsset: Asset?
    @State private var showsMovers = false

    private var snapshot: PortfolioSnapshot {
        PortfolioCalculator.snapshot(for: assets)
    }

    private var investedPerformances: [AssetPerformance] {
        performances.filter { $0.asset.type != .cash }
    }

    private var dashboardDailyProfitLoss: Double {
        investedPerformances.reduce(0) { $0 + dashboardDailyProfitLoss(for: $1) * cnyRate(for: $1.asset) }
    }

    private var dashboardCumulativeProfitLoss: Double {
        investedPerformances.reduce(0) { $0 + $1.cumulativeProfitLoss * cnyRate(for: $1.asset) }
    }

    private var movers: [AssetPerformance] {
        investedPerformances
            .sorted { abs(dashboardDailyProfitLoss(for: $0)) > abs(dashboardDailyProfitLoss(for: $1)) }
            .prefix(5)
            .map { $0 }
    }

    private func refreshPerformances() {
        performances = assets.map { PortfolioCalculator.performance(for: $0) }
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
            List {
                summaryHeader
                allocationSection
                dailyContributionSection
                moversSection
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(18)
            .safeAreaPadding(.bottom, 20)
            .onAppear { refreshPerformances() }
            .onChange(of: assets.count) { _, _ in refreshPerformances() }
            .sheet(item: $selectedAsset) { asset in
                NavigationStack {
                    AssetDetailView(asset: asset)
                }
            }
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
                    Text(isTotalHidden ? "****" : FinanceFormatters.totalCurrency(snapshot.totalValue))
                        .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                        .minimumScaleFactor(0.7)
                }
                Spacer()
                Image(systemName: dashboardDailyProfitLoss >= 0 ? "arrow.up.right" : "arrow.down.right")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(isTotalHidden ? .secondary : FinanceFormatters.profitColor(dashboardDailyProfitLoss))
                    .frame(width: 38, height: 38)
                    .background(Color(.quaternarySystemFill), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            HStack(spacing: 12) {
                MetricTile(
                    title: "今日盈亏",
                    value: isTotalHidden ? "****" : FinanceFormatters.signedCurrency(dashboardDailyProfitLoss),
                    tint: isTotalHidden ? .secondary : FinanceFormatters.profitColor(dashboardDailyProfitLoss),
                    subtitle: isTotalHidden ? nil : dailyReturnRate()
                )
                MetricTile(
                    title: "累计盈亏",
                    value: isTotalHidden ? "****" : FinanceFormatters.signedCurrency(dashboardCumulativeProfitLoss),
                    tint: isTotalHidden ? .secondary : FinanceFormatters.profitColor(dashboardCumulativeProfitLoss),
                    subtitle: isTotalHidden ? nil : cumulativeReturnRate()
                )
            }

            QuoteStatusLine(state: dashboardQuoteState)
        }
        .padding(.vertical, 6)
    }

    private var allocationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("资产分布")

            if snapshot.totalValue <= 0 {
                ContentUnavailableView("暂无资产", systemImage: "tray", description: Text("添加股票、基金、理财或现金后会显示分布。"))
                    .frame(minHeight: 160)
            } else {
                VStack(spacing: 14) {
                    AllocationStrip(allocations: snapshot.assetAllocation.filter { $0.value > 0 })

                    ForEach(snapshot.assetAllocation.filter { $0.value > 0 }) { allocation in
                        AllocationRow(allocation: allocation, hidden: isTotalHidden)
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }

    private var dailyContributionSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle("今日盈亏来源")

            ForEach(AssetType.allCases.filter { $0 != .cash }) { type in
                let contribution = investedPerformances
                    .filter { $0.asset.type == type }
                    .reduce(0) { $0 + dashboardDailyProfitLoss(for: $1) * cnyRate(for: $1.asset) }

                HStack {
                    Label(type.title, systemImage: type.systemImage)
                        .foregroundStyle(type.subduedAccentColor)
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text(FinanceFormatters.signedCurrency(contribution))
                        .foregroundStyle(FinanceFormatters.profitColor(contribution))
                        .monospacedDigit()
                }
                .font(.subheadline)
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var moversSection: some View {
        if !performances.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                DisclosureGroup(isExpanded: $showsMovers) {
                    VStack(spacing: 14) {
                        ForEach(movers) { item in
                            MoverRow(item: item, dailyProfitLoss: dashboardDailyProfitLoss(for: item)) {
                                selectedAsset = item.asset
                            }
                        }
                    }
                    .padding(.top, 10)
                } label: {
                    HStack {
                        Text("主要持仓变动")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Spacer()
                        Text("\(movers.count) 项")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 6)
        }
    }

    private func dailyReturnRate() -> String? {
        let base = snapshot.totalValue - dashboardDailyProfitLoss
        guard base > 0 else { return nil }
        let rate = dashboardDailyProfitLoss / base
        let prefix = rate > 0 ? "+" : ""
        return prefix + rate.formatted(.percent.precision(.fractionLength(2)))
    }

    private func cumulativeReturnRate() -> String? {
        let base = snapshot.totalValue - dashboardCumulativeProfitLoss
        guard base > 0 else { return nil }
        let rate = dashboardCumulativeProfitLoss / base
        let prefix = rate > 0 ? "+" : ""
        return prefix + rate.formatted(.percent.precision(.fractionLength(2)))
    }

    private func cnyRate(for asset: Asset) -> Double {
        asset.needsCNYConversion ? Market.rate(for: asset.resolvedMarket) : 1.0
    }

    private func dashboardDailyProfitLoss(for performance: AssetPerformance) -> Double {
        guard performance.asset.isQuoteBacked else {
            return performance.dailyProfitLoss
        }
        guard let quoteUpdatedAt = performance.asset.quoteUpdatedAt,
              Calendar.current.isDateInToday(quoteUpdatedAt) else {
            return 0
        }
        return performance.dailyProfitLoss
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
                Text(displayMessage)
                    .font(.footnote)
                    .foregroundStyle(tint)
                if let detail = displayDetail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var displayMessage: String {
        switch state {
        case .warning(_, let detail, _):
            if let failedCount {
                return "\(failedCount) 项数据更新失败"
            }
            if detail?.hasPrefix("更新失败：") == true {
                return "部分数据未更新"
            }
            return state.message
        default:
            return state.message
        }
    }

    private var displayDetail: String? {
        switch state {
        case .warning(_, let detail, _):
            if detail?.hasPrefix("更新失败：") == true {
                return "点按刷新或到持仓页检查行情代码。"
            }
            return detail
        default:
            return state.detail
        }
    }

    private var failedCount: Int? {
        guard case .warning(_, let detail, _) = state,
              let detail,
              detail.hasPrefix("更新失败：") else { return nil }

        let codes = detail
            .replacingOccurrences(of: "更新失败：", with: "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return codes.isEmpty ? nil : codes.count
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
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label(allocation.type.title, systemImage: allocation.type.systemImage)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(allocation.type.subduedAccentColor)
                Spacer()
                Text(FinanceFormatters.percent(allocation.percent))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            ProgressView(value: allocation.percent)
                .tint(allocation.type.subduedAccentColor.opacity(0.65))
                .scaleEffect(x: 1, y: 0.55, anchor: .center)
            Text(hidden ? "****" : FinanceFormatters.currency(allocation.value))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}

private struct AllocationStrip: View {
    let allocations: [AssetAllocation]

    var body: some View {
        GeometryReader { proxy in
            let spacing = CGFloat(max(allocations.count - 1, 0)) * 3
            let availableWidth = max(0, proxy.size.width - spacing)

            HStack(spacing: 3) {
                ForEach(allocations) { allocation in
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(allocation.type.subduedAccentColor.opacity(0.72))
                        .frame(width: max(4, availableWidth * allocation.percent))
                }
            }
        }
        .frame(height: 10)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .accessibilityLabel("资产分布")
    }
}

private struct MoverRow: View {
    let item: AssetPerformance
    let dailyProfitLoss: Double
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.asset.type.systemImage)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(item.asset.type.subduedAccentColor)
                .frame(width: 30, height: 30)
                .background(Color(.quaternarySystemFill), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(item.asset.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(item.asset.displayCode)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(FinanceFormatters.signedValueWithSymbol(dailyProfitLoss, symbol: item.asset.currencySymbol))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FinanceFormatters.profitColor(dailyProfitLoss))
                Text(FinanceFormatters.valueWithSymbol(item.currentValue, symbol: item.asset.currencySymbol))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .monospacedDigit()
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }
}
