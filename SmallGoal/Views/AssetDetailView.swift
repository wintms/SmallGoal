import SwiftData
import SwiftUI

private enum InvestmentTransactionMode: String, Identifiable {
    case buy
    case sell

    var id: String { rawValue }
}

struct AssetDetailView: View {
    let asset: Asset
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var quoteRefreshService: QuoteRefreshService
    @Query(sort: \Asset.createdAt) private var allAssets: [Asset]
    @State private var showingEditor = false
    @State private var showingAddTransaction = false
    @State private var transactionAmount: Double?
    @State private var transactionNote = ""
    @State private var transactionDate: Date = .now
    @State private var activeInvestmentTransactionMode: InvestmentTransactionMode?
    @State private var investmentAmount: Double?
    @State private var investmentNetValue: Double?
    @State private var investmentFee: Double?
    @State private var investmentDate: Date = .now
    @State private var investmentNote = ""
    @State private var investmentTransactionMode: InvestmentTransactionMode = .buy
    @State private var isLookingUpInvestmentNetValue = false
    @State private var investmentLookupMessage: String?
    @State private var pendingRecurringPlan: RecurringInvestmentPlan?
    @State private var showingStockDividendEditor = false
    @State private var dividendPerShare: Double?
    @State private var bonusSharesPer10: Double?
    @State private var dividendDate: Date = .now
    @State private var dividendNote = ""
    @State private var showingRecurringPlanEditor = false
    @State private var planAmount: Double?
    @State private var planFeeRatePercent: Double?
    @State private var planFrequency: RecurringInvestmentFrequency = .monthly
    @State private var planWeekday: Weekday = .monday
    @State private var planDayOfMonth = 1
    @State private var planNextDate: Date = .now
    @State private var planIsEnabled = true
    @State private var planNote = ""
    @State private var detailSnapshot: AssetDetailSnapshot?

    private var visibleSnapshot: AssetDetailSnapshot {
        detailSnapshot ?? makeDetailSnapshot()
    }

    private var detailCacheKey: String {
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
            String(asset.quoteUpdatedAt?.timeIntervalSince1970 ?? 0),
            String(asset.transactions?.count ?? 0),
            String(asset.investmentTransactions?.count ?? 0),
            String(asset.recurringInvestmentPlans?.count ?? 0)
        ].joined(separator: "|")
    }

    var body: some View {
        let snapshot = visibleSnapshot
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
                        MetricTile(title: "当前价值", value: snapshot.currentValueText, tint: .primary)
                        MetricTile(
                            title: "累计盈亏",
                            value: snapshot.cumulativeProfitLossText,
                            tint: snapshot.cumulativeProfitLossColor,
                            subtitle: snapshot.cumulativeReturnRateText
                        )
                    }
                }
                .padding(.vertical, 6)
            }

            Section("收益") {
                DetailRow("持仓成本", snapshot.costValueText)
                DetailRow("今日盈亏", snapshot.dailyProfitLossText, tint: snapshot.dailyProfitLossColor)
                DetailRow("今日盈亏率", snapshot.dailyProfitLossPercentText, tint: snapshot.dailyProfitLossColor)
            }

            Section("资产信息") {
                DetailRow("类型", asset.type.title)
                DetailRow("状态", asset.isEffectivelyArchived ? "已清仓" : "持仓中")
                DetailRow("币种", asset.displayCurrency)
                if asset.type != .cash {
                    DetailRow(quantityTitle, snapshot.displayQuantityText)
                }
                if asset.type == .stock || asset.type == .fund {
                    DetailRow("成本价", snapshot.displayCostText)
                    DetailRow("最新价格", snapshot.latestPriceText)
                    DetailRow("昨收/上一净值", snapshot.previousCloseText)
                }
                if asset.type == .wealthProduct {
                    DetailRow("年化收益率", snapshot.annualYieldText)
                    DetailRow("起息日", snapshot.startDateText)
                    DetailRow("到期日", snapshot.maturityDateText)
                }
                if asset.type == .cash {
                    DetailRow("初始现金", snapshot.initialCashText)
                    DetailRow("今日收支", snapshot.dailyProfitLossText)
                }
                if let quoteUpdatedAtText = snapshot.quoteUpdatedAtText {
                    DetailRow("行情时间", quoteUpdatedAtText)
                }
            }

            if asset.type == .stock || asset.type == .fund {
                if asset.type == .fund {
                    Section {
                        if let plan = asset.primaryRecurringInvestmentPlan {
                            DetailRow("金额", FinanceFormatters.valueWithSymbol(plan.amount, symbol: asset.currencySymbol))
                            DetailRow("手续费率", FinanceFormatters.percent(plan.feeRate))
                            DetailRow("周期", recurringPlanScheduleText(plan))
                            DetailRow("下次", plan.nextDate.formatted(date: .abbreviated, time: .omitted))
                            DetailRow("状态", plan.isEnabled ? "启用" : "暂停")
                            if isRecurringPlanDue(plan) {
                                Button {
                                    prepareInvestmentTransaction(from: plan)
                                } label: {
                                    Label("确认本期定投", systemImage: "checkmark.circle")
                                }
                            }
                            Button {
                                prepareRecurringPlanEditor(plan)
                            } label: {
                                Label("编辑计划", systemImage: "calendar.badge.clock")
                            }
                        } else {
                            Button {
                                prepareRecurringPlanEditor(nil)
                            } label: {
                                Label("设置定投计划", systemImage: "calendar.badge.plus")
                            }
                        }
                    } header: {
                        Text("定投计划")
                    }
                }

                Section {
                    ForEach(snapshot.investmentRows) { row in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.title)
                                    .font(.subheadline)
                                Text(row.dateText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(row.amountText)
                                    .foregroundStyle(row.amountColor)
                                    .monospacedDigit()
                                Text(row.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                    }
                    .onDelete { offsets in
                        let sorted = snapshot.investmentRows.map(\.transaction)
                        var remaining = sorted
                        for index in offsets {
                            let tx = sorted[index]
                            modelContext.delete(tx)
                            remaining.removeAll { $0.id == tx.id }
                        }
                        updateInvestmentSnapshotFields(using: remaining)
                        try? modelContext.save()
                    }

                    Button {
                        prepareInvestmentTransaction(mode: .buy)
                    } label: {
                        Label(addInvestmentButtonTitle, systemImage: "plus.circle")
                    }
                    Button {
                        prepareInvestmentTransaction(mode: .sell)
                    } label: {
                        Label(reduceInvestmentButtonTitle, systemImage: "minus.circle")
                    }
                    .disabled(displayQuantity <= 0)
                    if asset.type == .stock {
                        Button {
                            prepareStockDividendEditor()
                        } label: {
                            Label("添加分红/除权", systemImage: "dollarsign.circle")
                        }
                        .disabled(displayQuantity <= 0)
                    }
                } header: {
                    Text(investmentSectionTitle)
                }
            }

            if asset.type == .cash {
                Section {
                    ForEach(snapshot.cashRows) { row in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                if !row.note.isEmpty {
                                    Text(row.note)
                                        .font(.subheadline)
                                }
                                Text(row.dateText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(row.amountText)
                                .foregroundStyle(row.amountColor)
                                .monospacedDigit()
                        }
                    }
                    .onDelete { offsets in
                        let sorted = snapshot.cashRows.map(\.transaction)
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
        .task(id: detailCacheKey) {
            synchronizeArchivedStateIfNeeded()
            detailSnapshot = makeDetailSnapshot()
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
        .sheet(item: $activeInvestmentTransactionMode) { mode in
            NavigationStack {
                Form {
                    Section(investmentFormSectionTitle(for: mode)) {
                        TextField(investmentAmountPlaceholder(for: mode), value: $investmentAmount, format: .number)
                            .keyboardType(.decimalPad)
                        HStack {
                            TextField(investmentPricePlaceholder, value: $investmentNetValue, format: .number)
                                .keyboardType(.decimalPad)
                            Button {
                                Task { await lookupInvestmentNetValue() }
                            } label: {
                                if isLookingUpInvestmentNetValue {
                                    ProgressView()
                                } else {
                                    Image(systemName: "magnifyingglass")
                                }
                            }
                            .disabled(!canLookupInvestmentNetValue)
                            .accessibilityLabel(investmentLookupAccessibilityLabel)
                        }
                        if let investmentLookupMessage {
                            Text(investmentLookupMessage)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        TextField(investmentFeePlaceholder, value: $investmentFee, format: .number)
                            .keyboardType(.decimalPad)
                        DatePicker("日期", selection: $investmentDate, displayedComponents: .date)
                        if let investmentCashAmount = investmentCashAmount(for: mode) {
                            DetailRow("成交金额", FinanceFormatters.valueWithSymbol(investmentCashAmount, symbol: asset.currencySymbol))
                        }
                        if let estimatedUnits = estimatedUnits(for: mode) {
                            DetailRow(estimatedUnitsTitle(for: mode), FinanceFormatters.decimal(estimatedUnits))
                        }
                    }
                    Section("备注") {
                        TextField("可选", text: $investmentNote)
                    }
                }
                .navigationTitle(investmentFormTitle(for: mode))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") {
                            pendingRecurringPlan = nil
                            investmentLookupMessage = nil
                            activeInvestmentTransactionMode = nil
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(investmentConfirmationTitle(for: mode)) {
                            addInvestmentTransaction(mode: mode)
                            activeInvestmentTransactionMode = nil
                        }
                        .disabled(!canAddInvestmentTransaction(for: mode))
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showingStockDividendEditor) {
            NavigationStack {
                Form {
                    Section("分红/除权") {
                        TextField("每股现金分红", value: $dividendPerShare, format: .number)
                            .keyboardType(.decimalPad)
                        TextField("每 10 股送/转股", value: $bonusSharesPer10, format: .number)
                            .keyboardType(.decimalPad)
                        DatePicker("日期", selection: $dividendDate, displayedComponents: .date)
                        if let dividendCashAmount {
                            DetailRow("现金收入", FinanceFormatters.valueWithSymbol(dividendCashAmount, symbol: asset.currencySymbol))
                        }
                        if let bonusShares {
                            DetailRow("新增股数", FinanceFormatters.decimal(bonusShares))
                        }
                    }
                    Section("备注") {
                        TextField("可选", text: $dividendNote)
                    }
                }
                .navigationTitle("添加分红/除权")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { showingStockDividendEditor = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            applyStockDividend()
                            showingStockDividendEditor = false
                        }
                        .disabled(!canApplyStockDividend)
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showingRecurringPlanEditor) {
            NavigationStack {
                Form {
                    Section("计划") {
                        TextField("每期金额", value: $planAmount, format: .number)
                            .keyboardType(.decimalPad)
                        TextField("手续费率(%)，例如 0.15(%)", value: $planFeeRatePercent, format: .number)
                            .keyboardType(.decimalPad)
                        Picker("周期", selection: $planFrequency) {
                            ForEach(RecurringInvestmentFrequency.allCases) { frequency in
                                Text(frequency.title).tag(frequency)
                            }
                        }
                        if planFrequency == .weekly {
                            Picker("定投日", selection: $planWeekday) {
                                ForEach(Weekday.allCases) { weekday in
                                    Text(weekday.title).tag(weekday)
                                }
                            }
                        }
                        if planFrequency == .monthly {
                            Stepper("每月 \(planDayOfMonth) 日", value: $planDayOfMonth, in: 1...31)
                        }
                        DatePicker("下次定投日", selection: $planNextDate, displayedComponents: .date)
                        Toggle("启用", isOn: $planIsEnabled)
                    }
                    Section("备注") {
                        TextField("可选", text: $planNote)
                    }
                }
                .navigationTitle(asset.primaryRecurringInvestmentPlan == nil ? "设置定投" : "编辑定投")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { showingRecurringPlanEditor = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            saveRecurringPlan()
                            showingRecurringPlanEditor = false
                        }
                        .disabled((planAmount ?? 0) <= 0)
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

    private func makeDetailSnapshot() -> AssetDetailSnapshot {
        let performance = PortfolioCalculator.performance(for: asset)
        let currentDisplayQuantity = displayQuantity
        let currentDisplayCost = displayCost
        return AssetDetailSnapshot(
            currentValueText: FinanceFormatters.valueWithSymbol(performance.currentValue, symbol: asset.currencySymbol),
            cumulativeProfitLossText: FinanceFormatters.signedValueWithSymbol(performance.cumulativeProfitLoss, symbol: asset.currencySymbol),
            cumulativeProfitLossColor: FinanceFormatters.profitColor(performance.cumulativeProfitLoss),
            cumulativeReturnRateText: cumulativeReturnRate(for: performance),
            costValueText: FinanceFormatters.valueWithSymbol(performance.costValue, symbol: asset.currencySymbol),
            dailyProfitLossText: FinanceFormatters.signedValueWithSymbol(performance.dailyProfitLoss, symbol: asset.currencySymbol),
            dailyProfitLossColor: FinanceFormatters.profitColor(performance.dailyProfitLoss),
            dailyProfitLossPercentText: FinanceFormatters.percent(performance.dailyProfitLossPercent),
            displayQuantityText: FinanceFormatters.decimal(currentDisplayQuantity),
            displayCostText: FinanceFormatters.valueWithSymbol(currentDisplayCost, symbol: asset.currencySymbol),
            latestPriceText: FinanceFormatters.valueWithSymbol(asset.latestPrice, symbol: asset.currencySymbol),
            previousCloseText: FinanceFormatters.valueWithSymbol(asset.previousCloseOrNetValue, symbol: asset.currencySymbol),
            annualYieldText: FinanceFormatters.percent(asset.annualYield),
            startDateText: asset.startDate.formatted(date: .abbreviated, time: .omitted),
            maturityDateText: asset.maturityDate.formatted(date: .abbreviated, time: .omitted),
            initialCashText: FinanceFormatters.valueWithSymbol(asset.quantityOrAmount, symbol: asset.currencySymbol),
            quoteUpdatedAtText: asset.quoteUpdatedAt?.formatted(date: .abbreviated, time: .shortened),
            investmentRows: makeInvestmentRows(),
            cashRows: makeCashRows()
        )
    }

    private func makeInvestmentRows() -> [InvestmentTransactionRowData] {
        sortedInvestmentTransactions.map { transaction in
            let isSell = transaction.units < 0
            let isAdjustment = transaction.units == 0 || transaction.netValue == 0
            let cashAmount = transactionCashAmount(transaction)
            return InvestmentTransactionRowData(
                transaction: transaction,
                title: transaction.note.isEmpty ? defaultInvestmentTransactionTitle(isSell: isSell, isAdjustment: isAdjustment) : transaction.note,
                dateText: transaction.date.formatted(date: .abbreviated, time: .omitted),
                amountText: transactionDisplayAmount(transaction),
                amountColor: isSell ? FinanceFormatters.profitColor(cashAmount) : .primary,
                subtitle: transactionSubtitle(transaction)
            )
        }
    }

    private func makeCashRows() -> [CashTransactionRowData] {
        sortedTransactions.map { transaction in
            CashTransactionRowData(
                transaction: transaction,
                note: transaction.note,
                dateText: transaction.date.formatted(date: .abbreviated, time: .omitted),
                amountText: FinanceFormatters.signedValueWithSymbol(transaction.amount, symbol: asset.currencySymbol),
                amountColor: FinanceFormatters.profitColor(transaction.amount)
            )
        }
    }

    private var sortedTransactions: [CashTransaction] {
        (asset.transactions ?? []).sorted { $0.date > $1.date }
    }

    private var sortedInvestmentTransactions: [InvestmentTransaction] {
        (asset.investmentTransactions ?? []).sorted { $0.date > $1.date }
    }

    private var displayQuantity: Double {
        asset.type == .fund ? asset.fundUnits : asset.quantityOrAmount
    }

    private var displayCost: Double {
        guard asset.type == .fund else { return asset.cost }
        guard asset.fundUnits > 0 else { return asset.cost }
        return asset.fundCostValue / asset.fundUnits
    }

    private func defaultInvestmentTransactionTitle(isSell: Bool = false, isAdjustment: Bool = false) -> String {
        if isAdjustment {
            return asset.type == .stock ? "分红/除权" : "调整"
        }
        if asset.type == .stock {
            return isSell ? "卖出" : "买入"
        }
        return isSell ? "减仓" : "申购"
    }

    private var investmentSectionTitle: String {
        asset.type == .stock ? "交易记录" : "申购/赎回记录"
    }

    private var investmentFormSectionTitle: String {
        investmentFormSectionTitle(for: investmentTransactionMode)
    }

    private func investmentFormSectionTitle(for mode: InvestmentTransactionMode) -> String {
        if mode == .sell {
            return asset.type == .stock ? "卖出" : "赎回"
        }
        return asset.type == .stock ? "买入" : "申购"
    }

    private var investmentFormTitle: String {
        investmentFormTitle(for: investmentTransactionMode)
    }

    private func investmentFormTitle(for mode: InvestmentTransactionMode) -> String {
        if mode == .sell {
            return asset.type == .stock ? "添加卖出" : "添加赎回"
        }
        return asset.type == .stock ? "添加买入" : "添加申购"
    }

    private var addInvestmentButtonTitle: String {
        asset.type == .stock ? "添加买入" : "添加申购"
    }

    private var reduceInvestmentButtonTitle: String {
        asset.type == .stock ? "添加卖出" : "添加赎回"
    }

    private var investmentAmountPlaceholder: String {
        investmentAmountPlaceholder(for: investmentTransactionMode)
    }

    private func investmentAmountPlaceholder(for mode: InvestmentTransactionMode) -> String {
        if mode == .sell {
            return asset.type == .stock ? "卖出数量" : "赎回份额"
        }
        return asset.type == .stock ? "买入数量" : "金额"
    }

    private var investmentPricePlaceholder: String {
        asset.type == .stock ? "成交价" : "成交净值"
    }

    private var estimatedUnitsTitle: String {
        estimatedUnitsTitle(for: investmentTransactionMode)
    }

    private func estimatedUnitsTitle(for mode: InvestmentTransactionMode) -> String {
        if mode == .sell {
            return asset.type == .stock ? "卖出数量" : "赎回份额"
        }
        return asset.type == .stock ? "预计数量" : "预计份额"
    }

    private var investmentFeePlaceholder: String {
        asset.type == .stock ? "税费" : "手续费"
    }

    private var investmentUnitName: String {
        asset.type == .stock ? "股" : "份"
    }

    private var investmentLookupAccessibilityLabel: String {
        asset.type == .stock ? "获取最新价格" : "获取最新净值"
    }

    private var investmentConfirmationTitle: String {
        investmentConfirmationTitle(for: investmentTransactionMode)
    }

    private func investmentConfirmationTitle(for mode: InvestmentTransactionMode) -> String {
        if mode == .sell {
            return asset.type == .stock ? "卖出" : "减仓"
        }
        return "添加"
    }

    private var investmentCashAmount: Double? {
        investmentCashAmount(for: investmentTransactionMode)
    }

    private func investmentCashAmount(for mode: InvestmentTransactionMode) -> Double? {
        guard let input = investmentAmount,
              let price = investmentNetValue,
              input > 0,
              price > 0 else { return nil }
        let fee = investmentFee ?? 0
        guard fee >= 0 else { return nil }
        if mode == .sell {
            let gross = input * price
            guard gross > fee else { return nil }
            return gross - fee
        }
        if asset.type == .stock {
            return input * price + fee
        }
        guard input > fee else { return nil }
        return input
    }

    private var estimatedUnits: Double? {
        estimatedUnits(for: investmentTransactionMode)
    }

    private func estimatedUnits(for mode: InvestmentTransactionMode) -> Double? {
        guard let amount = investmentAmount,
              let netValue = investmentNetValue,
              amount > 0,
              netValue > 0 else { return nil }
        let fee = investmentFee ?? 0
        guard fee >= 0 else { return nil }
        if mode == .sell {
            guard amount <= displayQuantity else { return nil }
            return amount
        }
        if asset.type == .stock {
            return amount
        }
        guard amount > fee else { return nil }
        return (amount - fee) / netValue
    }

    private var canAddInvestmentTransaction: Bool {
        estimatedUnits != nil && investmentCashAmount != nil
    }

    private func canAddInvestmentTransaction(for mode: InvestmentTransactionMode) -> Bool {
        estimatedUnits(for: mode) != nil && investmentCashAmount(for: mode) != nil
    }

    private var canLookupInvestmentNetValue: Bool {
        !isLookingUpInvestmentNetValue && !asset.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var dividendCashAmount: Double? {
        guard let dividendPerShare, dividendPerShare > 0, displayQuantity > 0 else { return nil }
        return dividendPerShare * displayQuantity
    }

    private var bonusShares: Double? {
        guard let bonusSharesPer10, bonusSharesPer10 > 0, displayQuantity > 0 else { return nil }
        return displayQuantity * bonusSharesPer10 / 10
    }

    private var canApplyStockDividend: Bool {
        dividendCashAmount != nil || bonusShares != nil
    }

    private func addTransaction() {
        guard let amount = transactionAmount, amount != 0 else { return }
        let tx = CashTransaction(amount: amount, note: transactionNote, date: transactionDate)
        tx.asset = asset
        modelContext.insert(tx)
        try? modelContext.save()
    }

    private func prepareStockDividendEditor() {
        dividendPerShare = nil
        bonusSharesPer10 = nil
        dividendDate = .now
        dividendNote = ""
        showingStockDividendEditor = true
    }

    private func prepareInvestmentTransaction(from plan: RecurringInvestmentPlan? = nil, mode: InvestmentTransactionMode = .buy) {
        investmentTransactionMode = mode
        investmentAmount = plan?.amount
        investmentNetValue = asset.latestPrice > 0 ? asset.latestPrice : nil
        investmentFee = mode == .buy ? plan.flatMap { plan in
            let fee = plan.amount * plan.feeRate
            return fee > 0 ? fee : nil
        } : nil
        investmentDate = plan?.nextDate ?? .now
        investmentNote = plan == nil ? "" : "定投"
        investmentLookupMessage = nil
        pendingRecurringPlan = plan
        activeInvestmentTransactionMode = mode
    }

    private func lookupInvestmentNetValue() async {
        let code = asset.code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return }

        isLookingUpInvestmentNetValue = true
        investmentLookupMessage = nil
        defer { isLookingUpInvestmentNetValue = false }

        do {
            let quote = try await quoteRefreshService.fetchQuote(code: code)
            investmentNetValue = quote.latestPrice
            asset.latestPrice = quote.latestPrice
            asset.previousCloseOrNetValue = quote.previousClose
            asset.quoteUpdatedAt = quote.quoteTime
            asset.updatedAt = .now
            try? modelContext.save()
            let label = asset.type == .stock ? "最新价格" : "最新净值"
            investmentLookupMessage = "已获取\(label)：\(FinanceFormatters.valueWithSymbol(quote.latestPrice, symbol: asset.currencySymbol))"
        } catch {
            investmentLookupMessage = "获取失败：\(error.localizedDescription)"
        }
    }

    private func addInvestmentTransaction(mode: InvestmentTransactionMode? = nil) {
        let resolvedMode = mode ?? investmentTransactionMode
        investmentTransactionMode = resolvedMode
        guard let cashAmount = investmentCashAmount(for: resolvedMode),
              let netValue = investmentNetValue,
              let units = estimatedUnits(for: resolvedMode) else { return }
        let fee = investmentFee ?? 0
        let seededTransaction = seedInitialInvestmentTransactionIfNeeded()
        let isSell = resolvedMode == .sell
        let transactionUnits = isSell ? -units : units
        let transactionAmount = isSell ? -(units * displayCost) : cashAmount
        let tx = InvestmentTransaction(
            amount: transactionAmount,
            units: transactionUnits,
            netValue: netValue,
            fee: fee,
            date: investmentDate,
            note: investmentNote.isEmpty && isSell ? defaultInvestmentTransactionTitle(isSell: true) : investmentNote
        )
        tx.asset = asset
        modelContext.insert(tx)
        recordInvestmentCashTransaction(amount: cashAmount, date: investmentDate, isRecurring: pendingRecurringPlan != nil, isSell: isSell)
        if let pendingRecurringPlan {
            pendingRecurringPlan.nextDate = nextRecurringDate(after: pendingRecurringPlan.nextDate, for: pendingRecurringPlan)
            pendingRecurringPlan.updatedAt = .now
            scheduleNotification(for: pendingRecurringPlan)
        }
        updateInvestmentSnapshotFields(adding: [seededTransaction, tx].compactMap { $0 })
        asset.updatedAt = .now
        pendingRecurringPlan = nil
        try? modelContext.save()
    }

    private func recordInvestmentCashTransaction(amount: Double, date: Date, isRecurring: Bool, isSell: Bool) {
        guard amount > 0 else { return }
        let cashAsset = cashAssetForInvestmentPurchase()
        let resolvedAmount = asset.needsCNYConversion ? amount * Market.rate(for: asset.resolvedMarket) : amount
        let note: String
        if asset.type == .stock {
            note = "\(isSell ? "股票卖出" : "股票买入")：\(asset.name)"
        } else {
            note = isSell ? "基金赎回：\(asset.name)" : "\(isRecurring ? "基金定投" : "基金申购")：\(asset.name)"
        }
        let tx = CashTransaction(amount: isSell ? resolvedAmount : -resolvedAmount, note: note, date: date)
        tx.asset = cashAsset
        modelContext.insert(tx)
    }

    private func cashAssetForInvestmentPurchase() -> Asset {
        if let cashAsset = allAssets.first(where: { candidate in
            candidate.type == .cash && (candidate.currency.isEmpty || candidate.currency == "CNY")
        }) {
            return cashAsset
        }

        let cashAsset = Asset(
            type: .cash,
            name: "现金账户",
            quantityOrAmount: 0,
            cost: 0,
            currency: "CNY"
        )
        modelContext.insert(cashAsset)
        return cashAsset
    }

    private func seedInitialInvestmentTransactionIfNeeded() -> InvestmentTransaction? {
        guard asset.type == .stock || asset.type == .fund,
              (asset.investmentTransactions ?? []).isEmpty,
              asset.quantityOrAmount > 0,
              asset.cost > 0 else { return nil }
        let tx = InvestmentTransaction(
            amount: asset.quantityOrAmount * asset.cost,
            units: asset.quantityOrAmount,
            netValue: asset.cost,
            date: asset.createdAt,
            note: "初始持仓"
        )
        tx.asset = asset
        modelContext.insert(tx)
        return tx
    }

    private func updateInvestmentSnapshotFields(adding pendingTransactions: [InvestmentTransaction] = []) {
        guard asset.type == .stock || asset.type == .fund else { return }
        var transactions = asset.investmentTransactions ?? []
        transactions.append(contentsOf: pendingTransactions)
        updateInvestmentSnapshotFields(using: uniqueInvestmentTransactions(transactions))
    }

    private func updateInvestmentSnapshotFields(using transactions: [InvestmentTransaction]) {
        guard asset.type == .stock || asset.type == .fund else { return }
        let units = transactions.reduce(0) { $0 + $1.units }
        let costValue = transactions.reduce(0) { $0 + $1.amount }
        guard units > 0 else {
            asset.quantityOrAmount = 0
            asset.cost = 0
            asset.isArchived = true
            pauseRecurringPlansForArchivedAsset()
            asset.updatedAt = .now
            return
        }
        asset.quantityOrAmount = units
        asset.cost = max(0, costValue) / units
        asset.isArchived = false
        asset.updatedAt = .now
    }

    private func pauseRecurringPlansForArchivedAsset() {
        for plan in asset.recurringInvestmentPlans ?? [] where plan.isEnabled {
            plan.isEnabled = false
            plan.updatedAt = .now
            RecurringInvestmentNotificationService.cancelNotification(for: plan)
        }
    }

    private func synchronizeArchivedStateIfNeeded() {
        guard asset.type == .stock || asset.type == .fund else { return }
        let shouldArchive = asset.currentInvestmentUnits <= 0.000001
        guard asset.isArchived != shouldArchive else { return }
        asset.isArchived = shouldArchive
        if shouldArchive {
            pauseRecurringPlansForArchivedAsset()
        }
        asset.updatedAt = .now
        try? modelContext.save()
    }

    private func uniqueInvestmentTransactions(_ transactions: [InvestmentTransaction]) -> [InvestmentTransaction] {
        var seen: Set<UUID> = []
        return transactions.filter { transaction in
            seen.insert(transaction.id).inserted
        }
    }

    private func applyStockDividend() {
        guard asset.type == .stock else { return }
        let seededTransaction = seedInitialInvestmentTransactionIfNeeded()
        var pendingTransactions: [InvestmentTransaction] = [seededTransaction].compactMap { $0 }

        if let dividendCashAmount, dividendCashAmount > 0 {
            let tx = InvestmentTransaction(
                amount: -dividendCashAmount,
                units: 0,
                netValue: 0,
                date: dividendDate,
                note: dividendNote.isEmpty ? "现金分红" : dividendNote
            )
            tx.asset = asset
            modelContext.insert(tx)
            pendingTransactions.append(tx)

            let cashAsset = cashAssetForInvestmentPurchase()
            let resolvedAmount = asset.needsCNYConversion ? dividendCashAmount * Market.rate(for: asset.resolvedMarket) : dividendCashAmount
            let cashTx = CashTransaction(amount: resolvedAmount, note: "股票分红：\(asset.name)", date: dividendDate)
            cashTx.asset = cashAsset
            modelContext.insert(cashTx)
        }

        if let bonusShares, bonusShares > 0 {
            let tx = InvestmentTransaction(
                amount: 0,
                units: bonusShares,
                netValue: 0,
                date: dividendDate,
                note: dividendNote.isEmpty ? "送股/转增" : dividendNote
            )
            tx.asset = asset
            modelContext.insert(tx)
            pendingTransactions.append(tx)
        }

        updateInvestmentSnapshotFields(adding: pendingTransactions)
        adjustStockQuoteForDividend(cashDividendPerShare: dividendPerShare ?? 0, addedShares: bonusShares ?? 0)
        asset.updatedAt = .now
        try? modelContext.save()
    }

    private func adjustStockQuoteForDividend(cashDividendPerShare: Double, addedShares: Double) {
        guard asset.type == .stock else { return }
        let originalQuantity = max(0, displayQuantity - addedShares)
        if cashDividendPerShare > 0 {
            asset.latestPrice = max(0, asset.latestPrice - cashDividendPerShare)
            asset.previousCloseOrNetValue = max(0, asset.previousCloseOrNetValue - cashDividendPerShare)
        }
        if addedShares > 0, originalQuantity > 0 {
            let factor = originalQuantity / (originalQuantity + addedShares)
            asset.latestPrice = max(0, asset.latestPrice * factor)
            asset.previousCloseOrNetValue = max(0, asset.previousCloseOrNetValue * factor)
        }
    }

    private func transactionCashAmount(_ transaction: InvestmentTransaction) -> Double {
        if transaction.units == 0, transaction.netValue == 0, transaction.amount < 0 {
            return abs(transaction.amount)
        }
        if transaction.units < 0 {
            return abs(transaction.units) * transaction.netValue - transaction.fee
        }
        return transaction.amount
    }

    private func transactionDisplayAmount(_ transaction: InvestmentTransaction) -> String {
        let amount = transactionCashAmount(transaction)
        if transaction.units == 0 || transaction.netValue == 0 {
            return FinanceFormatters.signedValueWithSymbol(amount, symbol: asset.currencySymbol)
        }
        if transaction.units < 0 {
            return FinanceFormatters.signedValueWithSymbol(amount, symbol: asset.currencySymbol)
        }
        return FinanceFormatters.valueWithSymbol(amount, symbol: asset.currencySymbol)
    }

    private func transactionSubtitle(_ transaction: InvestmentTransaction) -> String {
        if transaction.units == 0 {
            return "现金分红"
        }
        if transaction.netValue == 0 {
            return "\(FinanceFormatters.decimal(abs(transaction.units))) \(investmentUnitName)"
        }
        return "\(FinanceFormatters.decimal(abs(transaction.units))) \(investmentUnitName) @ \(FinanceFormatters.valueWithSymbol(transaction.netValue, symbol: asset.currencySymbol))"
    }

    private func prepareRecurringPlanEditor(_ plan: RecurringInvestmentPlan?) {
        let calendar = Calendar.current
        let day = calendar.component(.day, from: .now)
        planAmount = plan?.amount
        planFeeRatePercent = plan.flatMap { plan in
            let percent = plan.feeRate * 100
            return percent > 0 ? percent : nil
        }
        planFrequency = plan?.frequency ?? .monthly
        planWeekday = plan?.selectedWeekday ?? .monday
        planDayOfMonth = plan?.dayOfMonth ?? min(day, 31)
        planNextDate = plan?.nextDate ?? nextRecurringDate(onOrAfter: .now, frequency: plan?.frequency ?? .monthly, weekday: plan?.selectedWeekday ?? .monday, dayOfMonth: min(day, 31))
        planIsEnabled = plan?.isEnabled ?? true
        planNote = plan?.note ?? ""
        showingRecurringPlanEditor = true
    }

    private func saveRecurringPlan() {
        guard let amount = planAmount, amount > 0 else { return }
        let feeRate = max(0, planFeeRatePercent ?? 0) / 100
        let normalizedNextDate = nextRecurringDate(onOrAfter: planNextDate, frequency: planFrequency, weekday: planWeekday, dayOfMonth: planDayOfMonth)
        if let plan = asset.primaryRecurringInvestmentPlan {
            plan.amount = amount
            plan.feeRate = feeRate
            plan.frequency = planFrequency
            plan.selectedWeekday = planWeekday
            plan.dayOfMonth = planDayOfMonth
            plan.nextDate = normalizedNextDate
            plan.isEnabled = planIsEnabled
            plan.note = planNote
            plan.updatedAt = .now
            updateNotification(for: plan)
        } else {
            let plan = RecurringInvestmentPlan(
                amount: amount,
                feeRate: feeRate,
                frequency: planFrequency,
                weekday: planWeekday,
                dayOfMonth: planDayOfMonth,
                nextDate: normalizedNextDate,
                isEnabled: planIsEnabled,
                note: planNote
            )
            plan.asset = asset
            modelContext.insert(plan)
            updateNotification(for: plan)
        }
        asset.updatedAt = .now
        try? modelContext.save()
    }

    private func isRecurringPlanDue(_ plan: RecurringInvestmentPlan) -> Bool {
        guard plan.isEnabled else { return false }
        return Calendar.current.startOfDay(for: plan.nextDate) <= Calendar.current.startOfDay(for: .now)
    }

    private func updateNotification(for plan: RecurringInvestmentPlan) {
        if plan.isEnabled {
            scheduleNotification(for: plan)
        } else {
            RecurringInvestmentNotificationService.cancelNotification(for: plan)
        }
    }

    private func scheduleNotification(for plan: RecurringInvestmentPlan) {
        Task {
            await RecurringInvestmentNotificationService.scheduleNotification(for: plan, assetName: asset.name, symbol: asset.currencySymbol)
        }
    }

    private func recurringPlanScheduleText(_ plan: RecurringInvestmentPlan) -> String {
        switch plan.frequency {
        case .daily:
            return "每日"
        case .weekly:
            return "每周 \(plan.selectedWeekday.title)"
        case .monthly:
            return "每月 \(plan.dayOfMonth) 日"
        }
    }

    private func nextRecurringDate(after date: Date, for plan: RecurringInvestmentPlan) -> Date {
        nextRecurringDate(after: date, frequency: plan.frequency, weekday: plan.selectedWeekday, dayOfMonth: plan.dayOfMonth)
    }

    private func nextRecurringDate(after date: Date, frequency: RecurringInvestmentFrequency, weekday: Weekday, dayOfMonth: Int) -> Date {
        switch frequency {
        case .daily:
            return Calendar.current.date(byAdding: .day, value: 1, to: date) ?? date
        case .weekly:
            return nextWeeklyDate(after: date, weekday: weekday)
        case .monthly:
            return nextMonthlyDate(after: date, dayOfMonth: dayOfMonth)
        }
    }

    private func nextRecurringDate(onOrAfter date: Date, frequency: RecurringInvestmentFrequency, weekday: Weekday, dayOfMonth: Int) -> Date {
        switch frequency {
        case .daily:
            return date
        case .weekly:
            return nextWeeklyDate(onOrAfter: date, weekday: weekday)
        case .monthly:
            return nextMonthlyDate(onOrAfter: date, dayOfMonth: dayOfMonth)
        }
    }

    private func nextWeeklyDate(after date: Date, weekday: Weekday) -> Date {
        let calendar = Calendar.current
        var next = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        while calendar.component(.weekday, from: next) != weekday.rawValue {
            next = calendar.date(byAdding: .day, value: 1, to: next) ?? next
        }
        return next
    }

    private func nextWeeklyDate(onOrAfter date: Date, weekday: Weekday) -> Date {
        let calendar = Calendar.current
        var next = date
        while calendar.component(.weekday, from: next) != weekday.rawValue {
            next = calendar.date(byAdding: .day, value: 1, to: next) ?? next
        }
        return next
    }

    private func nextMonthlyDate(after date: Date, dayOfMonth: Int) -> Date {
        let calendar = Calendar.current
        let base = calendar.date(byAdding: .month, value: 1, to: date) ?? date
        return monthlyDate(containing: base, dayOfMonth: dayOfMonth)
    }

    private func nextMonthlyDate(onOrAfter date: Date, dayOfMonth: Int) -> Date {
        let calendar = Calendar.current
        let currentMonthDate = monthlyDate(containing: date, dayOfMonth: dayOfMonth)
        if calendar.startOfDay(for: currentMonthDate) >= calendar.startOfDay(for: date) {
            return currentMonthDate
        }
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: date) ?? date
        return monthlyDate(containing: nextMonth, dayOfMonth: dayOfMonth)
    }

    private func monthlyDate(containing date: Date, dayOfMonth: Int) -> Date {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month], from: date)
        let days = calendar.range(of: .day, in: .month, for: date)?.count ?? 28
        components.day = max(1, min(days, dayOfMonth))
        return calendar.date(from: components) ?? date
    }

    private func cumulativeReturnRate(for performance: AssetPerformance) -> String? {
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

private struct AssetDetailSnapshot {
    let currentValueText: String
    let cumulativeProfitLossText: String
    let cumulativeProfitLossColor: Color
    let cumulativeReturnRateText: String?
    let costValueText: String
    let dailyProfitLossText: String
    let dailyProfitLossColor: Color
    let dailyProfitLossPercentText: String
    let displayQuantityText: String
    let displayCostText: String
    let latestPriceText: String
    let previousCloseText: String
    let annualYieldText: String
    let startDateText: String
    let maturityDateText: String
    let initialCashText: String
    let quoteUpdatedAtText: String?
    let investmentRows: [InvestmentTransactionRowData]
    let cashRows: [CashTransactionRowData]
}

private struct InvestmentTransactionRowData: Identifiable {
    var id: UUID { transaction.id }
    let transaction: InvestmentTransaction
    let title: String
    let dateText: String
    let amountText: String
    let amountColor: Color
    let subtitle: String
}

private struct CashTransactionRowData: Identifiable {
    var id: UUID { transaction.id }
    let transaction: CashTransaction
    let note: String
    let dateText: String
    let amountText: String
    let amountColor: Color
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
