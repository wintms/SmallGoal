import SwiftData
import SwiftUI

struct HoldingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Asset.updatedAt, order: .reverse) private var assets: [Asset]
    @State private var showingAddAsset = false
    @State private var selectedAddType: AssetType?
    @State private var searchText = ""
    @State private var filteredType: AssetType?
    @State private var sortOption: HoldingSortOption = .updatedAt

    private var groupedAssets: [(AssetType, [Asset])] {
        AssetType.allCases.compactMap { type in
            let filtered = sortedAssets.filter { $0.type == type }
            return filtered.isEmpty ? nil : (type, filtered)
        }
    }

    private var performances: [UUID: AssetPerformance] {
        Dictionary(uniqueKeysWithValues: assets.map { ($0.id, PortfolioCalculator.performance(for: $0)) })
    }

    private var sortedAssets: [Asset] {
        filteredAssets.sorted { lhs, rhs in
            switch sortOption {
            case .updatedAt:
                lhs.updatedAt > rhs.updatedAt
            case .name:
                lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            case .valueHighToLow:
                cnyValue(for: lhs) > cnyValue(for: rhs)
            case .valueLowToHigh:
                cnyValue(for: lhs) < cnyValue(for: rhs)
            case .profitHighToLow:
                cnyProfit(for: lhs) > cnyProfit(for: rhs)
            case .profitLowToHigh:
                cnyProfit(for: lhs) < cnyProfit(for: rhs)
            }
        }
    }

    private var filteredAssets: [Asset] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return assets.filter { asset in
            if let filteredType, asset.type != filteredType {
                return false
            }
            guard !query.isEmpty else { return true }
            return searchableText(for: asset).contains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(groupedAssets, id: \.0) { type, typedAssets in
                    Section(type.title) {
                        ForEach(typedAssets) { asset in
                            NavigationLink {
                                AssetDetailView(asset: asset)
                            } label: {
                                HoldingRow(
                                    asset: asset,
                                    performance: performances[asset.id]
                                )
                            }
                        }
                        .onDelete { offsets in
                            deleteAssets(at: offsets, from: typedAssets)
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
                } else if filteredAssets.isEmpty {
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

    private func cnyValue(for asset: Asset) -> Double {
        let value = performances[asset.id]?.currentValue ?? PortfolioCalculator.currentValue(for: asset)
        return value * cnyRate(for: asset)
    }

    private func cnyProfit(for asset: Asset) -> Double {
        let profit = performances[asset.id]?.cumulativeProfitLoss ?? PortfolioCalculator.cumulativeProfitLoss(for: asset)
        return profit * cnyRate(for: asset)
    }

    private func cnyRate(for asset: Asset) -> Double {
        asset.needsCNYConversion ? Market.rate(for: asset.resolvedMarket) : 1.0
    }

    private func deleteAssets(at offsets: IndexSet, from typedAssets: [Asset]) {
        for index in offsets {
            modelContext.delete(typedAssets[index])
        }
        try? modelContext.save()
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
    let asset: Asset
    let performance: AssetPerformance?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: asset.type.systemImage)
                .foregroundStyle(asset.type.accentColor)
                .frame(width: 34, height: 34)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(asset.name)
                    .font(.headline)
                Text(asset.displayCode)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let performance {
                VStack(alignment: .trailing, spacing: 4) {
                    Text(FinanceFormatters.valueWithSymbol(performance.currentValue, symbol: asset.currencySymbol))
                        .font(.subheadline.weight(.semibold))
                    Text(FinanceFormatters.signedValueWithSymbol(performance.cumulativeProfitLoss, symbol: asset.currencySymbol))
                        .font(.caption)
                        .foregroundStyle(FinanceFormatters.profitColor(performance.cumulativeProfitLoss))
                }
                .monospacedDigit()
            }
        }
        .padding(.vertical, 4)
    }
}
