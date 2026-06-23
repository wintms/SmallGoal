import SwiftData
import SwiftUI

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
    @State private var showingAddInvestmentTransaction = false
    @State private var investmentAmount: Double?
    @State private var investmentNetValue: Double?
    @State private var investmentFee: Double?
    @State private var investmentDate: Date = .now
    @State private var investmentNote = ""
    @State private var isLookingUpInvestmentNetValue = false
    @State private var investmentLookupMessage: String?
    @State private var pendingRecurringPlan: RecurringInvestmentPlan?
    @State private var showingRecurringPlanEditor = false
    @State private var planAmount: Double?
    @State private var planFeeRatePercent: Double?
    @State private var planFrequency: RecurringInvestmentFrequency = .monthly
    @State private var planWeekday: Weekday = .monday
    @State private var planDayOfMonth = 1
    @State private var planNextDate: Date = .now
    @State private var planIsEnabled = true
    @State private var planNote = ""

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
                    DetailRow(quantityTitle, FinanceFormatters.decimal(displayQuantity))
                }
                if asset.type == .stock || asset.type == .fund {
                    DetailRow("成本价", FinanceFormatters.valueWithSymbol(displayCost, symbol: asset.currencySymbol))
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
                    ForEach(sortedInvestmentTransactions) { tx in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tx.note.isEmpty ? defaultInvestmentTransactionTitle : tx.note)
                                    .font(.subheadline)
                                Text(tx.date.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(FinanceFormatters.valueWithSymbol(tx.amount, symbol: asset.currencySymbol))
                                    .monospacedDigit()
                                Text("\(FinanceFormatters.decimal(tx.units)) \(investmentUnitName) @ \(FinanceFormatters.valueWithSymbol(tx.netValue, symbol: asset.currencySymbol))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                    }
                    .onDelete { offsets in
                        let sorted = sortedInvestmentTransactions
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
                        prepareInvestmentTransaction()
                    } label: {
                        Label(addInvestmentButtonTitle, systemImage: "plus.circle")
                    }
                } header: {
                    Text(investmentSectionTitle)
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
        .sheet(isPresented: $showingAddInvestmentTransaction) {
            NavigationStack {
                Form {
                    Section(investmentFormSectionTitle) {
                        TextField(investmentAmountPlaceholder, value: $investmentAmount, format: .number)
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
                        if let investmentTotalAmount {
                            DetailRow("成交金额", FinanceFormatters.valueWithSymbol(investmentTotalAmount, symbol: asset.currencySymbol))
                        }
                        if let estimatedUnits {
                            DetailRow(estimatedUnitsTitle, FinanceFormatters.decimal(estimatedUnits))
                        }
                    }
                    Section("备注") {
                        TextField("可选", text: $investmentNote)
                    }
                }
                .navigationTitle(investmentFormTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") {
                            pendingRecurringPlan = nil
                            investmentLookupMessage = nil
                            showingAddInvestmentTransaction = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("添加") {
                            addInvestmentTransaction()
                            showingAddInvestmentTransaction = false
                        }
                        .disabled(!canAddInvestmentTransaction)
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

    private var defaultInvestmentTransactionTitle: String {
        asset.type == .stock ? "买入" : "申购"
    }

    private var investmentSectionTitle: String {
        asset.type == .stock ? "买入记录" : "申购记录"
    }

    private var investmentFormSectionTitle: String {
        asset.type == .stock ? "买入" : "申购"
    }

    private var investmentFormTitle: String {
        asset.type == .stock ? "添加买入" : "添加申购"
    }

    private var addInvestmentButtonTitle: String {
        asset.type == .stock ? "添加买入" : "添加申购"
    }

    private var investmentAmountPlaceholder: String {
        asset.type == .stock ? "买入数量" : "金额"
    }

    private var investmentPricePlaceholder: String {
        asset.type == .stock ? "成交价" : "成交净值"
    }

    private var estimatedUnitsTitle: String {
        asset.type == .stock ? "预计数量" : "预计份额"
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

    private var investmentTotalAmount: Double? {
        guard let input = investmentAmount,
              let price = investmentNetValue,
              input > 0,
              price > 0 else { return nil }
        let fee = investmentFee ?? 0
        guard fee >= 0 else { return nil }
        if asset.type == .stock {
            return input * price + fee
        }
        guard input > fee else { return nil }
        return input
    }

    private var estimatedUnits: Double? {
        guard let amount = investmentAmount,
              let netValue = investmentNetValue,
              amount > 0,
              netValue > 0 else { return nil }
        let fee = investmentFee ?? 0
        guard fee >= 0 else { return nil }
        if asset.type == .stock {
            return amount
        }
        guard amount > fee else { return nil }
        return (amount - fee) / netValue
    }

    private var canAddInvestmentTransaction: Bool {
        estimatedUnits != nil
    }

    private var canLookupInvestmentNetValue: Bool {
        !isLookingUpInvestmentNetValue && !asset.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func addTransaction() {
        guard let amount = transactionAmount, amount != 0 else { return }
        let tx = CashTransaction(amount: amount, note: transactionNote, date: transactionDate)
        tx.asset = asset
        modelContext.insert(tx)
        try? modelContext.save()
    }

    private func prepareInvestmentTransaction(from plan: RecurringInvestmentPlan? = nil) {
        investmentAmount = plan?.amount
        investmentNetValue = asset.latestPrice > 0 ? asset.latestPrice : nil
        investmentFee = plan.flatMap { plan in
            let fee = plan.amount * plan.feeRate
            return fee > 0 ? fee : nil
        }
        investmentDate = plan?.nextDate ?? .now
        investmentNote = plan == nil ? "" : "定投"
        investmentLookupMessage = nil
        pendingRecurringPlan = plan
        showingAddInvestmentTransaction = true
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

    private func addInvestmentTransaction() {
        guard let totalAmount = investmentTotalAmount,
              let netValue = investmentNetValue,
              let units = estimatedUnits else { return }
        let fee = investmentFee ?? 0
        let seededTransaction = seedInitialInvestmentTransactionIfNeeded()
        let tx = InvestmentTransaction(
            amount: totalAmount,
            units: units,
            netValue: netValue,
            fee: fee,
            date: investmentDate,
            note: investmentNote
        )
        tx.asset = asset
        modelContext.insert(tx)
        recordCashOutflow(amount: totalAmount, date: investmentDate, isRecurring: pendingRecurringPlan != nil)
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

    private func recordCashOutflow(amount: Double, date: Date, isRecurring: Bool) {
        guard amount > 0 else { return }
        let cashAsset = cashAssetForInvestmentPurchase()
        let outflowAmount = asset.needsCNYConversion ? amount * Market.rate(for: asset.resolvedMarket) : amount
        let note: String
        if asset.type == .stock {
            note = "股票买入：\(asset.name)"
        } else {
            note = "\(isRecurring ? "基金定投" : "基金申购")：\(asset.name)"
        }
        let tx = CashTransaction(amount: -outflowAmount, note: note, date: date)
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
        updateInvestmentSnapshotFields(using: transactions)
    }

    private func updateInvestmentSnapshotFields(using transactions: [InvestmentTransaction]) {
        guard asset.type == .stock || asset.type == .fund else { return }
        let units = transactions.reduce(0) { $0 + $1.units }
        let costValue = transactions.reduce(0) { $0 + $1.amount }
        guard units > 0 else {
            asset.quantityOrAmount = 0
            asset.cost = 0
            asset.updatedAt = .now
            return
        }
        asset.quantityOrAmount = units
        asset.cost = costValue / units
        asset.updatedAt = .now
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
