import SwiftData
import SwiftUI

struct HoldingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Asset.updatedAt, order: .reverse) private var assets: [Asset]
    @State private var showingAddAsset = false
    @State private var selectedType: AssetType?

    var body: some View {
        NavigationStack {
            List {
                ForEach(AssetType.allCases) { type in
                    let typedAssets = assets.filter { $0.type == type }
                    if !typedAssets.isEmpty {
                        Section(type.title) {
                            ForEach(typedAssets) { asset in
                                NavigationLink {
                                    AssetDetailView(asset: asset)
                                } label: {
                                    HoldingRow(asset: asset)
                                }
                            }
                            .onDelete { offsets in
                                deleteAssets(at: offsets, from: typedAssets)
                            }
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
    }
}

private struct HoldingRow: View {
    let asset: Asset
    private var performance: AssetPerformance {
        PortfolioCalculator.performance(for: asset)
    }

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

            VStack(alignment: .trailing, spacing: 4) {
                Text(FinanceFormatters.currency(performance.currentValue))
                    .font(.subheadline.weight(.semibold))
                Text(FinanceFormatters.signedCurrency(performance.dailyProfitLoss))
                    .font(.caption)
                    .foregroundStyle(FinanceFormatters.profitColor(performance.dailyProfitLoss))
            }
            .monospacedDigit()
        }
        .padding(.vertical, 4)
    }
}
