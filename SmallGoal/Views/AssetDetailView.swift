import SwiftUI

struct AssetDetailView: View {
    let asset: Asset
    @State private var showingEditor = false

    private var performance: AssetPerformance {
        PortfolioCalculator.performance(for: asset)
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Image(systemName: asset.type.systemImage)
                            .font(.title2)
                            .foregroundStyle(asset.type.accentColor)
                            .frame(width: 44, height: 44)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(asset.name)
                                .font(.title3.weight(.semibold))
                            Text(asset.displayCode)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack(spacing: 12) {
                        MetricTile(title: "当前价值", value: FinanceFormatters.currency(performance.currentValue), tint: .primary)
                        MetricTile(
                            title: "今日盈亏",
                            value: FinanceFormatters.signedCurrency(performance.dailyProfitLoss),
                            tint: FinanceFormatters.profitColor(performance.dailyProfitLoss)
                        )
                    }
                }
                .padding(.vertical, 6)
            }

            Section("收益") {
                DetailRow("持仓成本", FinanceFormatters.currency(performance.costValue))
                DetailRow("累计盈亏", FinanceFormatters.signedCurrency(performance.cumulativeProfitLoss), tint: FinanceFormatters.profitColor(performance.cumulativeProfitLoss))
                DetailRow("今日盈亏率", FinanceFormatters.percent(performance.dailyProfitLossPercent), tint: FinanceFormatters.profitColor(performance.dailyProfitLoss))
            }

            Section("资产信息") {
                DetailRow("类型", asset.type.title)
                DetailRow(quantityTitle, FinanceFormatters.decimal(asset.quantityOrAmount))
                if asset.type == .stock || asset.type == .fund {
                    DetailRow("成本价", FinanceFormatters.decimal(asset.cost))
                    DetailRow("最新价格", FinanceFormatters.decimal(asset.latestPrice))
                    DetailRow("昨收/上一净值", FinanceFormatters.decimal(asset.previousCloseOrNetValue))
                }
                if asset.type == .wealthProduct {
                    DetailRow("年化收益率", FinanceFormatters.percent(asset.annualYield))
                    DetailRow("起息日", asset.startDate.formatted(date: .abbreviated, time: .omitted))
                    DetailRow("到期日", asset.maturityDate.formatted(date: .abbreviated, time: .omitted))
                }
                if let quoteUpdatedAt = asset.quoteUpdatedAt {
                    DetailRow("行情时间", quoteUpdatedAt.formatted(date: .abbreviated, time: .shortened))
                }
            }

            if !asset.note.isEmpty {
                Section("备注") {
                    Text(asset.note)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("资产详情")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingEditor = true
                } label: {
                    Label("编辑", systemImage: "pencil")
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            AssetEditorView(asset: asset)
        }
    }

    private var quantityTitle: String {
        switch asset.type {
        case .stock: "持仓数量"
        case .fund: "基金份额"
        case .wealthProduct: "本金"
        case .cash: "现金余额"
        }
    }
}

private struct DetailRow: View {
    let title: String
    let value: String
    let tint: Color

    init(_ title: String, _ value: String, tint: Color = .primary) {
        self.title = title
        self.value = value
        self.tint = tint
    }

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .foregroundStyle(tint)
                .monospacedDigit()
        }
    }
}
