import SwiftUI

struct AssetDetailView: View {
    let asset: Asset
    @Environment(\.modelContext) private var modelContext
    @State private var showingEditor = false
    @State private var showingAddTransaction = false
    @State private var transactionAmount: Double?
    @State private var transactionNote = ""
    @State private var transactionDate: Date = .now

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
                        MetricTile(title: "当前价值", value: FinanceFormatters.valueWithSymbol(performance.currentValue, symbol: asset.currencySymbol), tint: .primary)
                        MetricTile(
                            title: "累计盈亏",
                            value: FinanceFormatters.signedValueWithSymbol(performance.cumulativeProfitLoss, symbol: asset.currencySymbol),
                            tint: FinanceFormatters.profitColor(performance.cumulativeProfitLoss),
                            subtitle: cumulativeReturnRate()
                        )
                    }
                }
                .padding(.vertical, 6)
            }

            Section("收益") {
                DetailRow("持仓成本", FinanceFormatters.valueWithSymbol(performance.costValue, symbol: asset.currencySymbol))
                DetailRow("今日盈亏", FinanceFormatters.signedValueWithSymbol(performance.dailyProfitLoss, symbol: asset.currencySymbol), tint: FinanceFormatters.profitColor(performance.dailyProfitLoss))
                DetailRow("今日盈亏率", FinanceFormatters.percent(performance.dailyProfitLossPercent), tint: FinanceFormatters.profitColor(performance.dailyProfitLoss))
            }

            Section("资产信息") {
                DetailRow("类型", asset.type.title)
                DetailRow("币种", asset.displayCurrency)
                if asset.type != .cash {
                    DetailRow(quantityTitle, FinanceFormatters.decimal(asset.quantityOrAmount))
                }
                if asset.type == .stock || asset.type == .fund {
                    DetailRow("成本价", FinanceFormatters.valueWithSymbol(asset.cost, symbol: asset.currencySymbol))
                    DetailRow("最新价格", FinanceFormatters.valueWithSymbol(asset.latestPrice, symbol: asset.currencySymbol))
                    DetailRow("昨收/上一净值", FinanceFormatters.valueWithSymbol(asset.previousCloseOrNetValue, symbol: asset.currencySymbol))
                }
                if asset.type == .wealthProduct {
                    DetailRow("年化收益率", FinanceFormatters.percent(asset.annualYield))
                    DetailRow("起息日", asset.startDate.formatted(date: .abbreviated, time: .omitted))
                    DetailRow("到期日", asset.maturityDate.formatted(date: .abbreviated, time: .omitted))
                }
                if asset.type == .cash {
                    DetailRow("初始现金", FinanceFormatters.valueWithSymbol(asset.quantityOrAmount, symbol: asset.currencySymbol))
                    DetailRow("今日收支", FinanceFormatters.signedValueWithSymbol(performance.dailyProfitLoss, symbol: asset.currencySymbol))
                }
                if let quoteUpdatedAt = asset.quoteUpdatedAt {
                    DetailRow("行情时间", quoteUpdatedAt.formatted(date: .abbreviated, time: .shortened))
                }
            }

            if asset.type == .cash {
                Section {
                    ForEach(sortedTransactions) { tx in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                if !tx.note.isEmpty {
                                    Text(tx.note)
                                        .font(.subheadline)
                                }
                                Text(tx.date.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(FinanceFormatters.signedValueWithSymbol(tx.amount, symbol: asset.currencySymbol))
                                .foregroundStyle(FinanceFormatters.profitColor(tx.amount))
                                .monospacedDigit()
                        }
                    }
                    .onDelete { offsets in
                        let sorted = sortedTransactions
                        for index in offsets {
                            let tx = sorted[index]
                            modelContext.delete(tx)
                        }
                        try? modelContext.save()
                    }

                    Button {
                        transactionAmount = nil
                        transactionNote = ""
                        transactionDate = .now
                        showingAddTransaction = true
                    } label: {
                        Label("添加收支", systemImage: "plus.circle")
                    }
                } header: {
                    Text("收支记录")
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
        .sheet(isPresented: $showingAddTransaction) {
            NavigationStack {
                Form {
                    Section("金额") {
                        TextField("正数收入，负数支出", value: $transactionAmount, format: .number)
                            .keyboardType(.numbersAndPunctuation)
                        DatePicker("日期", selection: $transactionDate, displayedComponents: .date)
                    }
                    Section("备注") {
                        TextField("可选", text: $transactionNote)
                    }
                }
                .navigationTitle("添加收支")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { showingAddTransaction = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("添加") {
                            addTransaction()
                            showingAddTransaction = false
                        }
                        .disabled((transactionAmount ?? 0) == 0)
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

    private var sortedTransactions: [CashTransaction] {
        (asset.transactions ?? []).sorted { $0.date > $1.date }
    }

    private func addTransaction() {
        guard let amount = transactionAmount, amount != 0 else { return }
        let tx = CashTransaction(amount: amount, note: transactionNote, date: transactionDate)
        tx.asset = asset
        modelContext.insert(tx)
        try? modelContext.save()
    }

    private func cumulativeReturnRate() -> String? {
        guard performance.costValue > 0 else { return nil }
        let rate = performance.cumulativeProfitLoss / performance.costValue
        let prefix = rate > 0 ? "+" : ""
        return prefix + FinanceFormatters.percent(rate)
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
