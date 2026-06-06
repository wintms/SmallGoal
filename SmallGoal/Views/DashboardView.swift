import SwiftData
import SwiftUI

struct DashboardView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var quoteRefreshService: QuoteRefreshService
    @Query(sort: \Asset.updatedAt, order: .reverse) private var assets: [Asset]
    @AppStorage("dashboard.lastAutoRefreshAt") private var lastAutoRefreshAt = 0.0
    @State private var isTotalHidden = false
    @State private var selectedAsset: Asset?
    @State private var showsMovers = false

    private var snapshot: PortfolioSnapshot {
        PortfolioCalculator.snapshot(for: assets)
    }

    private var performances: [AssetPerformance] {
        assets.map { PortfolioCalculator.performance(for: $0) }
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

    private func autoRefreshQuotesIfNeeded(now: Date = .now) {
        guard shouldAutoRefreshQuotes(now: now),
              quoteRefreshService.configuration.canRefresh,
              !quoteRefreshService.isRefreshing,
              assets.contains(where: { $0.isQuoteBacked && !$0.code.isEmpty }) else { return }

        lastAutoRefreshAt = now.timeIntervalSinceReferenceDate
        Task {
            await quoteRefreshService.refresh(assets: assets)
        }
    }

    private func shouldAutoRefreshQuotes(now: Date) -> Bool {
        let calendar = Calendar.current
        guard let refreshStart = calendar.date(
            bySettingHour: 21,
            minute: 30,
            second: 0,
            of: now
        ), now >= refreshStart else { return false }

        guard lastAutoRefreshAt > 0 else { return true }
        let lastRefreshDate = Date(timeIntervalSinceReferenceDate: lastAutoRefreshAt)
        return !calendar.isDate(lastRefreshDate, inSameDayAs: now)
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
                totalAssetsSection
                allocationSection
                dailyContributionSection
                moversSection
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(18)
            .safeAreaPadding(.bottom, 20)
            .onAppear {
                autoRefreshQuotesIfNeeded()
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active else { return }
                autoRefreshQuotesIfNeeded()
            }
            .onChange(of: assets.count) { _, _ in autoRefreshQuotesIfNeeded() }
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

    private var totalAssetsSection: some View {
        Section {
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
                            .buttonStyle(.plain)
                        }
                        Text(isTotalHidden ? "****" : FinanceFormatters.totalCurrency(snapshot.totalValue))
                            .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                            .monospacedDigit()
                            .minimumScaleFactor(0.7)
                    }
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
            .padding(.vertical, 8)
        }
    }

    private var allocationSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 14) {
                if snapshot.totalValue <= 0 {
                    ContentUnavailableView("暂无资产", systemImage: "tray", description: Text("添加股票、基金、理财或现金后会显示分布。"))
                        .frame(minHeight: 160)
                } else {
                    AllocationDistributionView(
                        allocations: snapshot.assetAllocation.filter { $0.value > 0 },
                        hidden: isTotalHidden
                    )
                }
            }
            .padding(.vertical, 8)
        } header: {
            Text("资产分布")
        }
    }

    private var dailyContributionSection: some View {
        Section {
            VStack(spacing: 14) {
                ForEach(AssetType.allCases.filter { $0 != .cash }) { type in
                    let contribution = investedPerformances
                        .filter { $0.asset.type == type }
                        .reduce(0) { $0 + dashboardDailyProfitLoss(for: $1) * cnyRate(for: $1.asset) }

                    HStack {
                        Label(type.title, systemImage: type.systemImage)
                            .foregroundStyle(type.subduedAccentColor)
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text(isTotalHidden ? "****" : FinanceFormatters.signedCurrency(contribution))
                            .foregroundStyle(isTotalHidden ? .secondary : FinanceFormatters.profitColor(contribution))
                            .monospacedDigit()
                    }
                    .font(.subheadline)
                }
            }
            .padding(.vertical, 8)
        } header: {
            Text("今日盈亏来源")
        }
    }

    @ViewBuilder
    private var moversSection: some View {
        if !performances.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        showsMovers.toggle()
                    }
                } label: {
                    HStack {
                        Text("主要持仓变动")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Spacer()
                        Text("\(movers.count) 项")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(showsMovers ? 90 : 0))
                    }
                }
                .buttonStyle(.plain)

                if showsMovers {
                    VStack(spacing: 14) {
                        ForEach(movers) { item in
                            MoverRow(item: item, dailyProfitLoss: dashboardDailyProfitLoss(for: item)) {
                                selectedAsset = item.asset
                            }
                        }
                    }
                    .padding(.top, 14)
                }
            }
            .padding(.vertical, 6)
            .animation(.none, value: showsMovers)
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

private struct AllocationDistributionView: View {
    let allocations: [AssetAllocation]
    var hidden = false

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            AllocationDonutChart(allocations: allocations)

            VStack(spacing: 10) {
                ForEach(allocations) { allocation in
                    AllocationLegendRow(allocation: allocation, hidden: hidden)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AllocationLegendRow: View {
    let allocation: AssetAllocation
    var hidden = false

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Circle()
                .fill(allocation.type.subduedAccentColor.opacity(0.9))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 3) {
                Text(allocation.type.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)

                Text(hidden ? "****" : FinanceFormatters.currency(allocation.value))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            Spacer(minLength: 0)

            Text(FinanceFormatters.percent(allocation.percent))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(allocation.type.subduedAccentColor)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }
}

private struct AllocationDonutChart: View {
    let allocations: [AssetAllocation]

    private var leadingAllocation: AssetAllocation? {
        allocations.max { $0.percent < $1.percent }
    }

    private var segments: [PieSegment] {
        var start = 0.0
        return allocations.map { allocation in
            let segment = PieSegment(
                allocation: allocation,
                start: start,
                end: start + allocation.percent
            )
            start += allocation.percent
            return segment
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(.quaternarySystemFill))

            ForEach(segments) { segment in
                PieSliceShape(start: segment.start, end: segment.end)
                    .fill(segment.allocation.type.subduedAccentColor.opacity(0.88))
            }

            Circle()
                .stroke(Color(.systemGroupedBackground), lineWidth: 2)

            Circle()
                .fill(Color(.secondarySystemGroupedBackground))
                .frame(width: 70, height: 70)

            if let leadingAllocation {
                VStack(spacing: 2) {
                    Text(leadingAllocation.type.title)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(FinanceFormatters.percent(leadingAllocation.percent))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(leadingAllocation.type.subduedAccentColor)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .frame(width: 62)
            }
        }
        .frame(width: 112, height: 112)
        .accessibilityLabel("资产分布甜甜圈图")
    }
}

private struct PieSegment: Identifiable {
    let allocation: AssetAllocation
    let start: Double
    let end: Double

    var id: AssetAllocation.ID { allocation.id }
}

private struct PieSliceShape: Shape {
    let start: Double
    let end: Double

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let startAngle = Angle(degrees: start * 360 - 90)
        let endAngle = Angle(degrees: end * 360 - 90)

        var path = Path()
        path.move(to: center)
        path.addArc(
            center: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: false
        )
        path.closeSubpath()
        return path
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
