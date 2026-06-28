import SwiftData
import SwiftUI

struct HoldingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Asset.updatedAt, order: .reverse) private var assets: [Asset]
    @State private var showingAddAsset = false
    @State private var selectedAddType: AssetType?
    @State private var searchText = ""
    @State private var filteredType: AssetType?
    @State private var statusFilter: HoldingStatusFilter = .active
    @State private var sortOption: HoldingSortOption = .updatedAt
    @State private var rowSections: [HoldingSection] = []

    private var cacheKey: String {
        let assetKey = assets.map { asset in
            [
                asset.id.uuidString,
                asset.typeRaw,
                asset.name,
                asset.code,
                asset.market,
                asset.currency,
                asset.note,
                String(asset.quantityOrAmount),
                String(asset.cost),
                String(asset.latestPrice),
                String(asset.previousCloseOrNetValue),
                String(asset.annualYield),
                String(asset.isArchived),
                String(asset.currentInvestmentUnits),
                String(asset.startDate.timeIntervalSince1970),
                String(asset.maturityDate.timeIntervalSince1970),
                String(asset.updatedAt.timeIntervalSince1970),
                String(asset.transactions?.count ?? 0),
                String(asset.investmentTransactions?.count ?? 0)
            ].joined(separator: "|")
        }
        .joined(separator: "#")
        return [searchText, filteredType?.rawValue ?? "all", statusFilter.rawValue, sortOption.rawValue, assetKey].joined(separator: "||")
    }

    private var hasNoMatches: Bool {
        !assets.isEmpty && rowSections.allSatisfy(\.rows.isEmpty)
    }

    private func makeRowSections() -> [HoldingSection] {
        let rows = filteredRows().sorted { lhs, rhs in
            switch sortOption {
            case .updatedAt:
                lhs.updatedAt > rhs.updatedAt
            case .name:
                lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            case .valueHighToLow:
                lhs.cnyValue > rhs.cnyValue
            case .valueLowToHigh:
                lhs.cnyValue < rhs.cnyValue
            case .profitHighToLow:
                lhs.cnyProfit > rhs.cnyProfit
            case .profitLowToHigh:
                lhs.cnyProfit < rhs.cnyProfit
            }
        }
        return AssetType.allCases.compactMap { type in
            let typedRows = rows.filter { $0.type == type }
            return typedRows.isEmpty ? nil : HoldingSection(type: type, rows: typedRows)
        }
    }

    private func filteredRows() -> [HoldingRowData] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return assets.compactMap { asset in
            guard statusFilter.includes(asset) else {
                return nil
            }
            if let filteredType, asset.type != filteredType {
                return nil
            }
            if !query.isEmpty, !searchableText(for: asset).contains(query) {
                return nil
            }
            return makeRowData(for: asset)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(rowSections) { section in
                    Section(section.type.title) {
                        ForEach(section.rows) { row in
                            NavigationLink {
                                AssetDetailView(asset: row.asset)
                            } label: {
                                HoldingRow(row: row)
                            }
                        }
                        .onDelete { offsets in
                            deleteAssets(at: offsets, from: section.rows.map(\.asset))
                        }
                    }
                }
            }
            .overlay {
                if assets.isEmpty {
                    ContentUnavailableView(
                        "还没有资产",
                        systemImage: "plus.circle",
                        description: Text("点击右上角添加第一笔股票、基金、理财或现金。")
                    )
                } else if hasNoMatches {
                    ContentUnavailableView(
                        "没有匹配的持仓",
                        systemImage: "magnifyingglass",
                        description: Text("调整搜索、筛选或排序条件。")
                    )
                }
            }
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索名称、代码或备注")
            .navigationTitle("持仓")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Section("筛选") {
                            ForEach(HoldingStatusFilter.allCases) { filter in
                                Button {
                                    statusFilter = filter
                                } label: {
                                    Label(filter.title, systemImage: statusFilter == filter ? "checkmark" : filter.systemImage)
                                }
                            }
                        }

                        Section("类型") {
                            Button {
                                filteredType = nil
                            } label: {
                                Label("全部类型", systemImage: filteredType == nil ? "checkmark" : "circle")
                            }
                            ForEach(AssetType.allCases) { type in
                                Button {
                                    filteredType = type
                                } label: {
                                    Label(type.title, systemImage: filteredType == type ? "checkmark" : type.systemImage)
                                }
                            }
                        }

                        Section("排序") {
                            ForEach(HoldingSortOption.allCases) { option in
                                Button {
                                    sortOption = option
                                } label: {
                                    Label(option.title, systemImage: sortOption == option ? "checkmark" : option.systemImage)
                                }
                            }
                        }
                    } label: {
                        Label("筛选排序", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(AssetType.allCases) { type in
                            Button {
                                selectedAddType = type
                                showingAddAsset = true
                            } label: {
                                Label(type.title, systemImage: type.systemImage)
                            }
                        }
                    } label: {
                        Label("添加资产", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddAsset) {
                AssetEditorView(initialType: selectedAddType ?? .stock)
            }
            .task(id: cacheKey) {
                rowSections = makeRowSections()
            }
        }
    }

    private func searchableText(for asset: Asset) -> String {
        [
            asset.name,
            asset.code,
            asset.displayCode,
            asset.type.title,
            asset.market,
            asset.currency,
            asset.note
        ]
        .joined(separator: " ")
        .lowercased()
    }

    private func makeRowData(for asset: Asset) -> HoldingRowData {
        let performance = PortfolioCalculator.performance(for: asset)
        let valueText = FinanceFormatters.valueWithSymbol(performance.currentValue, symbol: asset.currencySymbol)
        let profitText = FinanceFormatters.signedValueWithSymbol(performance.cumulativeProfitLoss, symbol: asset.currencySymbol)
        return HoldingRowData(
            asset: asset,
            type: asset.type,
            isArchived: asset.isEffectivelyArchived,
            name: asset.name,
            displayCode: asset.displayCode,
            systemImage: asset.type.systemImage,
            accentColor: asset.type.accentColor,
            valueText: valueText,
            profitText: profitText,
            profitColor: FinanceFormatters.profitColor(performance.cumulativeProfitLoss),
            updatedAt: asset.updatedAt,
            cnyValue: performance.currentValue * cnyRate(for: asset),
            cnyProfit: performance.cumulativeProfitLoss * cnyRate(for: asset)
        )
    }

    private func cnyRate(for asset: Asset) -> Double {
        asset.needsCNYConversion ? Market.rate(for: asset.resolvedMarket) : 1.0
    }

    private func deleteAssets(at offsets: IndexSet, from typedAssets: [Asset]) {
        for index in offsets {
            let asset = typedAssets[index]
            for plan in asset.recurringInvestmentPlans ?? [] {
                RecurringInvestmentNotificationService.cancelNotification(for: plan)
            }
            modelContext.delete(asset)
        }
        try? modelContext.save()
    }
}

private struct HoldingSection: Identifiable {
    var id: AssetType { type }
    let type: AssetType
    let rows: [HoldingRowData]
}

private struct HoldingRowData: Identifiable {
    var id: UUID { asset.id }
    let asset: Asset
    let type: AssetType
    let isArchived: Bool
    let name: String
    let displayCode: String
    let systemImage: String
    let accentColor: Color
    let valueText: String
    let profitText: String
    let profitColor: Color
    let updatedAt: Date
    let cnyValue: Double
    let cnyProfit: Double
}

private enum HoldingStatusFilter: String, CaseIterable, Identifiable {
    case active
    case archived
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .active: "当前持仓"
        case .archived: "已清仓"
        case .all: "全部资产"
        }
    }

    var systemImage: String {
        switch self {
        case .active: "tray.full"
        case .archived: "archivebox"
        case .all: "square.stack"
        }
    }

    func includes(_ asset: Asset) -> Bool {
        switch self {
        case .active:
            !asset.isEffectivelyArchived
        case .archived:
            asset.isEffectivelyArchived
        case .all:
            true
        }
    }
}

private enum HoldingSortOption: String, CaseIterable, Identifiable {
    case updatedAt
    case name
    case valueHighToLow
    case valueLowToHigh
    case profitHighToLow
    case profitLowToHigh

    var id: String { rawValue }

    var title: String {
        switch self {
        case .updatedAt:
            "最近更新"
        case .name:
            "名称 A-Z"
        case .valueHighToLow:
            "市值从高到低"
        case .valueLowToHigh:
            "市值从低到高"
        case .profitHighToLow:
            "盈利从高到低"
        case .profitLowToHigh:
            "盈利从低到高"
        }
    }

    var systemImage: String {
        switch self {
        case .updatedAt:
            "clock"
        case .name:
            "textformat"
        case .valueHighToLow:
            "arrow.down"
        case .valueLowToHigh:
            "arrow.up"
        case .profitHighToLow:
            "chart.line.uptrend.xyaxis"
        case .profitLowToHigh:
            "chart.line.downtrend.xyaxis"
        }
    }
}

private struct HoldingRow: View {
    let row: HoldingRowData

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: row.systemImage)
                .foregroundStyle(row.accentColor)
                .frame(width: 34, height: 34)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(row.name)
                        .font(.headline)
                    if row.isArchived {
                        Text("已清仓")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                }
                Text(row.displayCode)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(row.valueText)
                    .font(.subheadline.weight(.semibold))
                Text(row.profitText)
                    .font(.caption)
                    .foregroundStyle(row.profitColor)
            }
            .monospacedDigit()
        }
        .padding(.vertical, 4)
    }
}
