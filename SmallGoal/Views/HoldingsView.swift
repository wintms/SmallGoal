import SwiftData
import SwiftUI

struct HoldingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Asset.updatedAt, order: .reverse) private var assets: [Asset]
    @State private var showingAddAsset = false
    @State private var selectedType: AssetType?

    private var groupedAssets: [(AssetType, [Asset])] {
        AssetType.allCases.compactMap { type in
            let filtered = assets.filter { $0.type == type }
            return filtered.isEmpty ? nil : (type, filtered)
        }
    }

    private var performances: [UUID: AssetPerformance] {
        Dictionary(uniqueKeysWithValues: assets.map { ($0.id, PortfolioCalculator.performance(for: $0)) })
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
                }
            }
            .navigationTitle("持仓")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(AssetType.allCases) { type in
                            Button {
                                selectedType = type
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
                AssetEditorView(initialType: selectedType ?? .stock)
            }
        }
    }

    private func deleteAssets(at offsets: IndexSet, from typedAssets: [Asset]) {
        for index in offsets {
            modelContext.delete(typedAssets[index])
        }
        try? modelContext.save()
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
